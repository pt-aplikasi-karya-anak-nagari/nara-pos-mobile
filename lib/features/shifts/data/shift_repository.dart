import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/connectivity_service.dart';
import '../../../core/outlet_scope.dart';
import '../../../core/offline/entity_cache.dart';
import '../../../core/offline/sale_outbox.dart' show isOfflineError;
import '../../../core/offline/shift_outbox.dart';
import '../../transactions/domain/sale.dart';
import '../domain/shift.dart';
import 'shift_api_service.dart';

/// Cache offline shift aktif terakhir per outlet (objek tunggal). Selain
/// menyimpan shift dari server (drop mid-shift tetap bisa jualan), juga jadi
/// tempat shift OPTIMISTIK saat buka offline sebelum sync.
final _activeShiftCache = EntityCache<Shift>(
  'active_shift',
  toJson: (s) => s.toCacheJson(),
  fromJson: Shift.fromJson,
);

class ShiftRepository {
  final ShiftApiService apiService;
  ShiftRepository(this.apiService);

  Future<Shift?> getActiveShift(String outletId) async {
    return readThroughCacheOne(
      cache: _activeShiftCache,
      outletId: outletId,
      fetch: () => apiService.getActiveShift(outletId),
    );
  }

  Future<List<Shift>> getHistory(String outletId) async {
    return apiService.getShifts(outletId);
  }

  Future<Shift> open(
    String outletId,
    double startingCash,
    String notes, {
    String? clientRef,
    DateTime? occurredAt,
  }) async {
    return apiService.openShift(
      outletId,
      startingCash,
      notes,
      clientRef: clientRef,
      occurredAt: occurredAt,
    );
  }

  Future<Shift> close(
    String outletId,
    String shiftId,
    double closingCash,
    String notes, {
    String? clientRef,
    DateTime? occurredAt,
  }) async {
    return apiService.closeShift(
      outletId,
      shiftId,
      closingCash,
      notes,
      clientRef: clientRef,
      occurredAt: occurredAt,
    );
  }

  double calculateExpectedCash(Shift shift, List<Sale> sales) {
    final totalSales =
        sales.where((s) => s.isPaid).fold(0.0, (sum, s) => sum + s.total);
    return shift.startingCash + totalSales;
  }
}

final shiftRepositoryProvider = Provider<ShiftRepository>((ref) {
  return ShiftRepository(ref.watch(shiftApiServiceProvider));
});

// Kas masuk/keluar (petty cash) untuk sebuah shift (B7).
final cashMovementsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, shiftId) {
  return ref.read(shiftApiServiceProvider).getCashMovements(shiftId);
});

class ActiveShiftNotifier extends AsyncNotifier<Shift?> {
  @override
  Future<Shift?> build() async {
    final outletId = ref.watch(activeOutletIdProvider);
    if (outletId == null) return null;

    final outbox = ref.read(shiftOutboxProvider);
    // Close offline yang belum sync → shift sudah ditutup secara lokal; gate
    // terkunci walau server (atau open yang juga belum sync) masih "open".
    final closes = await outbox.closesPending();
    if (closes.any((op) => op.outletId == outletId)) return null;
    // Open offline yang belum sync → server belum punya; sajikan shift
    // optimistik dari cache, JANGAN overwrite dengan hasil server (yang kosong).
    final opens = await outbox.opensPending();
    if (opens.any((op) => op.outletId == outletId)) {
      final cached = await _activeShiftCache.getAll(outletId);
      return cached.isEmpty ? null : cached.first;
    }
    return ref.read(shiftRepositoryProvider).getActiveShift(outletId);
  }

  Future<void> open(double startingCash, String notes) async {
    final outletId = ref.read(activeOutletIdProvider);
    if (outletId == null) throw 'Outlet belum dipilih';
    final clientRef = _genClientRef('osr');
    final occurredAt = DateTime.now();

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      if (ref.read(isOfflineProvider)) {
        return _enqueueOpen(outletId, startingCash, notes, clientRef, occurredAt);
      }
      try {
        return await ref.read(shiftRepositoryProvider).open(
              outletId,
              startingCash,
              notes,
              clientRef: clientRef,
              occurredAt: occurredAt,
            );
      } catch (e) {
        if (isOfflineError(e)) {
          return _enqueueOpen(
              outletId, startingCash, notes, clientRef, occurredAt);
        }
        rethrow;
      }
    });
  }

  /// Buka shift OFFLINE: shift optimistik lokal + antrikan op buka. Gate kasir
  /// langsung terbuka (cache active_shift), penjualan masuk outbox seperti biasa
  /// (server resolve shift dari active saat sync — open di-drain duluan).
  Future<Shift> _enqueueOpen(
    String outletId,
    double startingCash,
    String notes,
    String clientRef,
    DateTime occurredAt,
  ) async {
    final localShiftId = 'localshift_${DateTime.now().microsecondsSinceEpoch}';
    final shift = Shift(
      startTime: occurredAt,
      startingCash: startingCash,
      cashierName: '',
      cashierRemoteId: '',
      outletRemoteId: outletId,
      notes: notes,
      openingNotes: notes,
      isOpen: true,
      localShiftId: localShiftId,
      clientRef: clientRef,
    );
    await _activeShiftCache.replaceAll(outletId, [shift]);
    await ref.read(shiftOutboxProvider).enqueueOpen(
          outletId: outletId,
          localShiftId: localShiftId,
          clientRef: clientRef,
          payload: {'start_balance': startingCash, 'notes': notes},
          occurredAt: occurredAt,
        );
    await ref.read(pendingShiftSyncCountProvider.notifier).refresh();
    return shift;
  }

  Future<void> close(double closingCash, String notes) async {
    final outletId = ref.read(activeOutletIdProvider);
    final currentShift = state.value;
    // Relaks guard: shift offline cuma punya localShiftId (remoteId null).
    if (outletId == null ||
        currentShift == null ||
        (currentShift.remoteId == null && currentShift.localShiftId == null)) {
      throw 'Tidak ada shift aktif';
    }
    final clientRef = _genClientRef('csr');
    final occurredAt = DateTime.now();

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // Offline ATAU shift belum sync (hanya localShiftId) → antrikan close.
      if (ref.read(isOfflineProvider) || currentShift.remoteId == null) {
        await _enqueueClose(
            outletId, currentShift, closingCash, notes, clientRef, occurredAt);
        return null;
      }
      try {
        await ref.read(shiftRepositoryProvider).close(
              outletId,
              currentShift.remoteId!,
              closingCash,
              notes,
              clientRef: clientRef,
              occurredAt: occurredAt,
            );
        await _activeShiftCache.replaceAll(outletId, []);
        return null;
      } catch (e) {
        if (isOfflineError(e)) {
          await _enqueueClose(
              outletId, currentShift, closingCash, notes, clientRef, occurredAt);
          return null;
        }
        rethrow;
      }
    });

    ref.invalidate(shiftsFutureProvider);
  }

  /// Tutup shift OFFLINE: kunci gate (clear cache) + antrikan op close. Kalau
  /// open shift-nya juga belum sync, close depends_on op open itu (drainer
  /// jamin urutan open → close).
  Future<void> _enqueueClose(
    String outletId,
    Shift shift,
    double closingCash,
    String notes,
    String clientRef,
    DateTime occurredAt,
  ) async {
    await _activeShiftCache.replaceAll(outletId, []);
    final outbox = ref.read(shiftOutboxProvider);
    String? dependsOn;
    final serverShiftId = shift.remoteId;
    if (shift.localShiftId != null && serverShiftId == null) {
      dependsOn = await outbox.openLocalIdFor(shift.localShiftId!);
    }
    await outbox.enqueueClose(
      outletId: outletId,
      localShiftId: shift.localShiftId ?? shift.remoteId ?? '',
      clientRef: clientRef,
      payload: {'actual_balance': closingCash, 'notes': notes},
      occurredAt: occurredAt,
      dependsOn: dependsOn,
      serverShiftId: serverShiftId,
    );
    await ref.read(pendingShiftSyncCountProvider.notifier).refresh();
  }

  Future<Shift?> checkAndRefresh() async {
    final outletId = ref.read(activeOutletIdProvider);
    if (outletId == null) return null;

    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() async {
      return await ref.read(shiftRepositoryProvider).getActiveShift(outletId);
    });
    state = result;
    return result.value;
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

/// Idempotency key unik per operasi (open/close) — dipakai backend untuk dedup
/// retry sync. prefix 'osr' (open) / 'csr' (close).
String _genClientRef(String prefix) =>
    '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(0x7fffffff)}';

final activeShiftProvider = AsyncNotifierProvider<ActiveShiftNotifier, Shift?>(() {
  return ActiveShiftNotifier();
});

final shiftsFutureProvider = FutureProvider<List<Shift>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return [];
  return ref.watch(shiftRepositoryProvider).getHistory(outletId);
});
