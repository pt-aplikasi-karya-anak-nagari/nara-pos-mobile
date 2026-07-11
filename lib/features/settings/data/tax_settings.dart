import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/outlet_scope.dart';
import '../../outlet/data/outlet_service.dart';

/// Pengaturan pajak per-outlet, lengket di DB.
class TaxSettings {
  final bool enabled;
  final double percent;
  final double serviceChargePercent;
  final String serviceChargeName;

  const TaxSettings({
    this.enabled = true,
    this.percent = 10.0,
    this.serviceChargePercent = 0,
    this.serviceChargeName = 'Service Charge',
  });

  /// Rate pajak (0..1) — 0 bila disabled.
  double get rate => enabled ? percent / 100.0 : 0.0;

  /// Rate biaya layanan (0..1).
  double get serviceChargeRate => serviceChargePercent / 100.0;

  TaxSettings copyWith({
    bool? enabled,
    double? percent,
    double? serviceChargePercent,
    String? serviceChargeName,
  }) => TaxSettings(
    enabled: enabled ?? this.enabled,
    percent: percent ?? this.percent,
    serviceChargePercent: serviceChargePercent ?? this.serviceChargePercent,
    serviceChargeName: serviceChargeName ?? this.serviceChargeName,
  );
}

/// Provider TaxSettings yang reaktif terhadap outlet aktif. Membaca dari
/// `outletsProvider` (sumber kebenaran) daripada cache lokal — supaya
/// perubahan pengaturan langsung terlihat tanpa restart.
final taxSettingsProvider = Provider<TaxSettings>((ref) {
  final outlet = ref.watch(activeOutletProvider);
  if (outlet == null) return const TaxSettings();
  return TaxSettings(
    enabled: outlet.taxEnabled,
    percent: outlet.taxPercent,
    serviceChargePercent: outlet.serviceChargePercent,
    serviceChargeName: outlet.serviceChargeName,
  );
});

/// Service untuk mutasi pengaturan pajak (PUT /outlets/:id/tax).
class TaxSettingsService {
  final Ref ref;
  TaxSettingsService(this.ref);

  Future<void> save({
    required String outletId,
    required bool enabled,
    required double percent,
    required double serviceChargePercent,
  }) async {
    final dio = ref.read(dioProvider);
    await dio.put('/outlets/$outletId/tax', data: {
      'tax_enabled': enabled,
      'tax_percent': percent,
      'service_charge_percent': serviceChargePercent,
    });
    // Invalidate outlets list supaya activeOutletProvider/taxSettingsProvider
    // ikut ter-refresh dengan nilai baru.
    ref.invalidate(outletsProvider);
  }
}

final taxSettingsServiceProvider = Provider<TaxSettingsService>((ref) {
  return TaxSettingsService(ref);
});
