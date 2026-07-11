import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../connectivity_service.dart';
import '../../features/transactions/data/transaction_repository.dart';
import '../../features/shifts/data/shift_api_service.dart';
import '../../features/shifts/data/shift_repository.dart';
import 'sale_outbox.dart';
import 'shift_outbox.dart';

/// Hasil satu kali drain antrian offline.
class SyncResult {
  final int synced; // berhasil terkirim & dihapus dari antrian
  final int failed; // ditolak server (4xx/5xx), tetap di antrian + di-flag
  final bool stoppedOffline; // berhenti karena masih offline
  const SyncResult({
    this.synced = 0,
    this.failed = 0,
    this.stoppedOffline = false,
  });
}

/// Service yang mengirim ulang transaksi yang tertahan di outbox saat
/// koneksi kembali. Aman dipanggil berkali-kali (guard re-entrancy).
class OfflineSyncService {
  final Ref _ref;
  bool _syncing = false;
  OfflineSyncService(this._ref);

  Future<SyncResult> sync() async {
    if (_syncing) return const SyncResult();
    _syncing = true;
    int synced = 0;
    int failed = 0;
    bool stoppedOffline = false;
    bool shiftChanged = false;
    try {
      final shiftOutbox = _ref.read(shiftOutboxProvider);
      final shiftApi = _ref.read(shiftApiServiceProvider);

      // ── FASE A: drain BUKA shift dulu ──────────────────────────────────
      // Wajib urut: open harus ter-ACK sebelum sales/close, supaya server
      // punya shift aktif saat sale & close menyusul. Saat sukses, catat
      // server_shift_id ke op (dipakai close). Reject permanen → dead-letter
      // + cascade close turunannya.
      for (final op in await shiftOutbox.opensPending()) {
        try {
          final shift = await shiftApi.openShift(
            op.outletId,
            (op.payload['start_balance'] as num?)?.toDouble() ?? 0,
            op.payload['notes']?.toString() ?? '',
            clientRef: op.clientRef,
            occurredAt: DateTime.tryParse(op.occurredAt ?? ''),
          );
          if (op.localShiftId != null && (shift.remoteId ?? '').isNotEmpty) {
            await shiftOutbox.setServerShiftId(op.localShiftId!, shift.remoteId!);
          }
          await shiftOutbox.remove(op.localId);
          shiftChanged = true;
        } catch (e) {
          if (isOfflineError(e)) {
            stoppedOffline = true;
            break;
          }
          await shiftOutbox.markError(op.localId, e.toString());
          if (op.attempts + 1 >= ShiftOutbox.maxSyncAttempts &&
              op.localShiftId != null) {
            await shiftOutbox.markDeadCascade(op.localShiftId!, e.toString());
          }
        }
      }

      // ── FASE B: drain SALES ────────────────────────────────────────────
      if (!stoppedOffline) {
        final outbox = _ref.read(saleOutboxProvider);
        final api = _ref.read(transactionApiServiceProvider);
        // Outlet yang MASIH punya shift-open tertahan di antrian setelah Fase A.
        // Sebuah sale yang ditolak "harus buka shift" hanya layak ditunggu
        // (retryable-ordering) bila open-nya memang masih akan menyusul untuk
        // outlet itu. Kalau open-nya sudah dead-letter / tidak ada lagi, error
        // itu TIDAK akan pernah teratasi → jangan skip attempts selamanya.
        final outletsWithPendingOpen = <String>{
          for (final op in await shiftOutbox.opensPending()) op.outletId,
        };
        for (final ps in await outbox.pending()) {
          try {
            await api.checkout(ps.outletId, ps.payload);
            await outbox.remove(ps.localId);
            synced++;
          } catch (e) {
            if (isOfflineError(e)) {
              stoppedOffline = true;
              break;
            }
            // Sale balapan di depan open shift-nya yang belum sync →
            // RETRYABLE-ORDERING: jangan increment attempts (kalau tidak,
            // seluruh revenue satu shift bisa false-dead-letter). Akan sukses
            // di pass berikut setelah open ter-drain (FIFO).
            //
            // TAPI hanya bila open-nya memang masih pending untuk outlet ini.
            // Kalau open-nya sudah mati (dead-letter cascade di Fase A) atau
            // tak ada, error ordering ini permanen — biarkan jatuh ke markError
            // supaya attempts naik & sale akhirnya jadi dead-letter yang
            // TERLIHAT di UI recovery, bukan loop tak-hingga (omzet hilang).
            if (_isShiftOrderingError(e) &&
                outletsWithPendingOpen.contains(ps.outletId)) {
              continue;
            }
            await outbox.markError(ps.localId, e.toString());
            failed++;
          }
        }
      }

      // ── FASE C: drain TUTUP shift ──────────────────────────────────────
      if (!stoppedOffline) {
        for (final op in await shiftOutbox.closesPending()) {
          final targetId = op.serverShiftId;
          if (targetId == null || targetId.isEmpty) {
            // Open belum ter-resolve (belum sync) → lewati, coba lagi nanti.
            continue;
          }
          try {
            await shiftApi.closeShift(
              op.outletId,
              targetId,
              (op.payload['actual_balance'] as num?)?.toDouble() ?? 0,
              op.payload['notes']?.toString() ?? '',
              clientRef: op.clientRef,
              occurredAt: DateTime.tryParse(op.occurredAt ?? ''),
            );
            await shiftOutbox.remove(op.localId);
            shiftChanged = true;
          } catch (e) {
            if (isOfflineError(e)) {
              stoppedOffline = true;
              break;
            }
            await shiftOutbox.markError(op.localId, e.toString());
          }
        }
      }
    } finally {
      _syncing = false;
      await _ref.read(pendingSyncCountProvider.notifier).refresh();
      // Transaksi yang menembus batas attempts jadi dead-letter → refresh
      // indikator merah supaya owner sadar ada yang gagal permanen.
      await _ref.read(deadLetterCountProvider.notifier).refresh();
      await _ref.read(pendingShiftSyncCountProvider.notifier).refresh();
      await _ref.read(shiftDeadLetterCountProvider.notifier).refresh();
      if (synced > 0) {
        // Data backend berubah → refresh riwayat penjualan.
        _ref.invalidate(salesFutureProvider);
      }
      if (synced > 0 || shiftChanged) {
        // Status shift berubah (open/close ter-sync) → refresh gate kasir.
        _ref.invalidate(activeShiftProvider);
      }
    }
    return SyncResult(
      synced: synced,
      failed: failed,
      stoppedOffline: stoppedOffline,
    );
  }

  /// True bila error backend = "harus membuka shift dulu" (sale menyusul
  /// sebelum open-nya ter-sync). Retryable-ordering, bukan kegagalan nyata.
  bool _isShiftOrderingError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('membuka shift') || s.contains('buka shift');
  }
}

final offlineSyncServiceProvider = Provider<OfflineSyncService>(
  (ref) => OfflineSyncService(ref),
);

/// Provider "keep-alive" yang otomatis men-drain outbox setiap koneksi
/// kembali online. Watch sekali di shell aplikasi supaya aktif sepanjang
/// sesi. Juga memicu satu sync awal saat pertama dipasang (menangani
/// transaksi yang tertinggal dari sesi sebelumnya).
final offlineAutoSyncProvider = Provider<void>((ref) {
  // Sync sekali saat dipasang (mis. saat app start) bila ada yang tertahan.
  Future.microtask(() => ref.read(offlineSyncServiceProvider).sync());

  ref.listen<AsyncValue<ConnectionStatus>>(connectivityProvider, (prev, next) {
    if (next.value == ConnectionStatus.online) {
      ref.read(offlineSyncServiceProvider).sync();
    }
  });
});
