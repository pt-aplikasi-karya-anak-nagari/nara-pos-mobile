import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';
import '../domain/shift.dart';
import '../domain/z_report.dart';

class ShiftApiService extends BaseApiService {
  ShiftApiService(super.dio);

  Future<Shift?> getActiveShift(String outletId) async {
    return get(
      '/outlets/$outletId/shifts/active',
      converter: (data) => data != null ? Shift.fromJson(data) : null,
    );
  }

  Future<List<Shift>> getShifts(String outletId) async {
    return get(
      '/outlets/$outletId/shifts',
      converter: (data) {
        final List<dynamic> list = data;
        return list.map((json) => Shift.fromJson(json)).toList();
      },
    );
  }

  Future<Shift> openShift(
    String outletId,
    double startingCash,
    String notes, {
    String? clientRef,
    DateTime? occurredAt,
  }) async {
    debugPrint('Opening shift: $outletId, $startingCash, $notes');
    return post(
      '/outlets/$outletId/shifts/open',
      data: {
        'start_balance': startingCash,
        'notes': notes,
        // Idempotency + waktu bisnis untuk replay buka shift offline.
        if (clientRef != null && clientRef.isNotEmpty) 'client_ref': clientRef,
        if (occurredAt != null)
          'occurred_at': occurredAt.toUtc().toIso8601String(),
      },
      converter: (data) => Shift.fromJson(data),
    );
  }

  Future<Shift> closeShift(
    String outletId,
    String shiftId,
    double closingCash,
    String notes, {
    String? clientRef,
    DateTime? occurredAt,
  }) async {
    return post(
      '/shifts/$shiftId/close',
      data: {
        'actual_balance': closingCash,
        'notes': notes,
        if (clientRef != null && clientRef.isNotEmpty) 'client_ref': clientRef,
        if (occurredAt != null)
          'occurred_at': occurredAt.toUtc().toIso8601String(),
      },
      converter: (data) => Shift.fromJson(data),
    );
  }

  // ── Z-Report (laporan tutup shift) ────────────────────────────────────
  /// Ambil Z-Report untuk sebuah shift: info shift, rincian pembayaran per
  /// metode, dan total penjualan/pajak/service/diskon. Agregasi dihitung di
  /// backend supaya konsisten dengan web.
  Future<ZReport> getShiftZReport(String shiftId) async {
    return get(
      '/shifts/$shiftId/z-report',
      converter: (data) =>
          ZReport.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  // ── Kas masuk/keluar (petty cash, B7) ─────────────────────────────────
  Future<List<Map<String, dynamic>>> getCashMovements(String shiftId) async {
    return get(
      '/shifts/$shiftId/cash-movements',
      converter: (data) {
        final list = data as List<dynamic>? ?? const [];
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      },
    );
  }

  Future<void> addCashMovement(
    String shiftId, {
    required String type, // 'in' | 'out'
    required double amount,
    String note = '',
  }) async {
    await post(
      '/shifts/$shiftId/cash-movements',
      data: {'type': type, 'amount': amount, 'note': note},
      converter: (data) => data,
    );
  }
}

final shiftApiServiceProvider = Provider<ShiftApiService>((ref) {
  return ShiftApiService(ref.watch(dioProvider));
});
