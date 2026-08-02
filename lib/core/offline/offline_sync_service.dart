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

      // Op yang SUDAH ditolak di panggilan sync ini. Putaran berikutnya
      // melewatinya: tanpa ini, satu op yang memang rusak akan menaikkan
      // attempts sekali per putaran, dan batas 5 percobaan habis dalam satu
      // kali sambung ulang.
      final ditolakDiPanggilanIni = <String>{};

      // Ulang siklus A→B→C selama masih ada kemajuan.
      //
      // # KENAPA SEKALI SAJA TIDAK CUKUP
      //
      // Urutannya: SELURUH buka, lalu SELURUH sale, lalu SELURUH tutup. Untuk
      // kasir yang berjualan offline melewati dua shift, urutan itu tak bisa
      // selesai dalam satu lintasan:
      //
      //   FASE A  buka hari-1 → sukses
      //           buka hari-2 → DITOLAK, "masih ada shift yang belum ditutup"
      //                         — sebab tutup hari-1 baru jalan di Fase C
      //   FASE B  sale hari-2 → ditolak, shift-nya belum lahir
      //   FASE C  tutup hari-1 → sukses
      //
      // Setelah lintasan itu, prasyarat buka hari-2 SUDAH terpenuhi — tapi
      // sync-nya sudah selesai. Lintasan berikutnya baru terjadi saat koneksi
      // putus lalu tersambung lagi, yang bisa berhari-hari, sementara attempts
      // buka hari-2 sudah naik satu. Lima kali sambung-ulang tanpa sempat
      // ter-drain, dan seluruh omzet hari-2 jadi dead-letter.
      //
      // Putaran kedua di sini menyelesaikannya di panggilan yang sama: buka
      // hari-2 lolos, sale-nya menyusul, tutupnya menyusul. Putaran ketiga tak
      // menemukan kemajuan dan loop berhenti — jadi kasus normal (satu shift)
      // tetap membayar satu putaran saja.
      const maksPutaran = 4;
      for (var putaran = 0; putaran < maksPutaran; putaran++) {
        var adaKemajuan = false;

        // Outlet yang masih punya op TUTUP di antrian. Hanya untuk outlet
        // inilah penolakan "belum ditutup" pada buka shift layak ditunggu —
        // sebab Fase C di bawah memang akan menutupnya.
        //
        // Sengaja TIDAK menyaring server_shift_id di sini. Op tutup hari-1
        // baru mendapat server_shift_id-nya beberapa baris di bawah, saat op
        // BUKA hari-1 sukses di putaran ini juga; menilainya lebih awal berarti
        // syaratnya tak pernah terpenuhi dan seluruh mekanisme ini mati.
        //
        // Yang menjaga dari menunggu selamanya bukan syarat itu, melainkan
        // markDeadCascade: begitu sebuah op buka menembus batas percobaan, op
        // tutup turunannya ikut ditandai 'dead' dan keluar dari closesPending()
        // — jadi tak ada lagi yang bisa dinantikan, dan buka berikutnya kembali
        // menghitung attempts seperti biasa.
        final outletMenungguTutup = <String>{
          for (final op in await shiftOutbox.closesPending()) op.outletId,
        };

        // ── FASE A: drain BUKA shift dulu ──────────────────────────────────
        // Wajib urut: open harus ter-ACK sebelum sales/close, supaya server
        // punya shift aktif saat sale & close menyusul. Saat sukses, catat
        // server_shift_id ke op (dipakai close). Reject permanen → dead-letter
        // + cascade close turunannya.
        for (final op in await shiftOutbox.opensPending()) {
          if (ditolakDiPanggilanIni.contains('shift:${op.localId}')) continue;
          try {
            final shift = await shiftApi.openShift(
              op.outletId,
              (op.payload['start_balance'] as num?)?.toDouble() ?? 0,
              op.payload['notes']?.toString() ?? '',
              clientRef: op.clientRef,
              occurredAt: DateTime.tryParse(op.occurredAt ?? ''),
            );
            if (op.localShiftId != null && (shift.remoteId ?? '').isNotEmpty) {
              await shiftOutbox.setServerShiftId(
                op.localShiftId!,
                shift.remoteId!,
              );
            }
            await shiftOutbox.remove(op.localId);
            shiftChanged = true;
            adaKemajuan = true;
          } catch (e) {
            if (isOfflineError(e)) {
              stoppedOffline = true;
              break;
            }
            // "masih ada shift yang belum ditutup" BUKAN cacat op ini — ia
            // prasyarat yang justru dipenuhi Fase C beberapa baris di bawah.
            // Menaruhnya di daftar-lewati akan membuat putaran kedua
            // melompatinya, dan seluruh perbaikan urutan ini sia-sia. Attempts
            // pun tak dinaikkan: yang salah bukan datanya, hanya gilirannya.
            //
            // Tapi HANYA bila tutup yang dinantikan itu benar-benar ada dan
            // siap kirim. Tanpa syarat itu, op buka yang prasyaratnya tak akan
            // pernah datang akan lolos dari hitungan attempts SELAMANYA: tak
            // pernah berhasil, tak pernah mati, tak pernah muncul di daftar
            // "Perlu dipulihkan" — persis kegagalan diam yang sedang kita
            // singkirkan, hanya berpindah tempat.
            if (_isShiftOrderingError(e) &&
                outletMenungguTutup.contains(op.outletId)) {
              continue;
            }
            ditolakDiPanggilanIni.add('shift:${op.localId}');
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
            if (ditolakDiPanggilanIni.contains('sale:${ps.localId}')) continue;
            try {
              await api.checkout(ps.outletId, ps.payload);
              await outbox.remove(ps.localId);
              synced++;
              adaKemajuan = true;
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
              ditolakDiPanggilanIni.add('sale:${ps.localId}');
              await outbox.markError(ps.localId, e.toString());
              failed++;
            }
          }
        }

        // ── FASE C: drain TUTUP shift ──────────────────────────────────────
        if (!stoppedOffline) {
          for (final op in await shiftOutbox.closesPending()) {
            if (ditolakDiPanggilanIni.contains('shift:${op.localId}')) continue;
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
              adaKemajuan = true;
            } catch (e) {
              if (isOfflineError(e)) {
                stoppedOffline = true;
                break;
              }
              ditolakDiPanggilanIni.add('shift:${op.localId}');
              await shiftOutbox.markError(op.localId, e.toString());
            }
          }
        }

        // Tak ada satu pun yang bergerak — putaran lagi hanya mengulang
        // kegagalan yang sama.
        if (!adaKemajuan || stoppedOffline) break;
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

  /// True bila error backend = sale menyusul sebelum shift-nya ter-sync.
  /// Retryable-ordering, bukan kegagalan nyata.
  ///
  /// Dua bentuk, dari dua cabang server yang berbeda:
  ///
  ///   "harus membuka shift dulu"      sale tak menyebut shift apa pun dan
  ///                                   kasirnya memang belum punya yang aktif.
  ///   "belum tersedia di server"      sale MENYEBUT shift lewat client-ref,
  ///                                   tapi op buka-nya belum ter-drain.
  ///   "belum ditutup"                 buka shift berikutnya menyusul sebelum
  ///                                   tutup shift sebelumnya ter-drain.
  ///
  /// Yang kedua dulunya tak pernah muncul: server diam-diam mengikat sale itu
  /// ke shift lain yang kebetulan terbuka, membalas 200, dan outbox
  /// menghapusnya. Sekarang ia ditolak, dan penolakan itu HARUS dibaca sebagai
  /// "tunggu sebentar" — kalau tidak, seluruh omzet satu shift naik attempts
  /// lalu dead-letter padahal tak ada yang salah dengannya.
  bool _isShiftOrderingError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('membuka shift') ||
        s.contains('buka shift') ||
        s.contains('belum tersedia di server') ||
        s.contains('belum ditutup');
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
