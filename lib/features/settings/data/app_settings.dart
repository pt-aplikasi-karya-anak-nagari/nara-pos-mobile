import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/outlet_scope.dart';
import '../../outlet/data/outlet_service.dart';

/// Subset pengaturan aplikasi per-outlet yang dikonsumsi aplikasi kasir.
///
/// Sumber: `GET /outlets/:outletId/app-settings` (lihat mako-be
/// internal/appsettings). Payload backend jauh lebih kaya (currency, locale,
/// QR menu, notifikasi, dll); di mobile kita hanya butuh flag keamanan yang
/// menentukan apakah PIN otorisasi manajer wajib saat void/refund. Field lain
/// sengaja diabaikan supaya model tetap ringan.
class OutletAppSettings {
  /// Bila true, refund transaksi mensyaratkan `override_pin` manajer berwenang.
  final bool requirePinRefund;

  /// Bila true, void (batalkan) transaksi mensyaratkan `override_pin`.
  final bool requirePinVoid;

  const OutletAppSettings({
    this.requirePinRefund = false,
    this.requirePinVoid = false,
  });

  factory OutletAppSettings.fromJson(Map<String, dynamic> json) {
    return OutletAppSettings(
      requirePinRefund: json['require_pin_refund'] as bool? ?? false,
      requirePinVoid: json['require_pin_void'] as bool? ?? false,
    );
  }
}

/// Pengaturan aplikasi outlet aktif. Dipakai dialog refund/void untuk tahu
/// apakah PIN otorisasi manajer wajib diisi.
///
/// FutureProvider — di-cache setelah fetch pertama. Callsite umumnya membaca
/// via `ref.read(outletAppSettingsProvider.future)` supaya nilai terjamin
/// termuat sebelum dialog dibuka. Bila fetch gagal (mis. offline), callsite
/// fallback ke penanganan error 403 dari backend.
final outletAppSettingsProvider = FutureProvider<OutletAppSettings>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return const OutletAppSettings();
  final json = await ref.watch(outletServiceProvider).getAppSettings(outletId);
  return OutletAppSettings.fromJson(json);
});
