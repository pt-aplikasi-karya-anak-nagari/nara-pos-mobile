import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/outlet_scope.dart';
import '../../outlet/data/outlet_service.dart';

/// Subset pengaturan aplikasi per-outlet yang dikonsumsi aplikasi kasir.
///
/// Sumber: `GET /outlets/:outletId/app-settings` (lihat mako-be
/// internal/appsettings). Payload backend jauh lebih kaya (currency, locale,
/// QR menu, notifikasi, dll); di mobile kita hanya butuh flag keamanan yang
/// menentukan apakah PIN otorisasi manajer wajib saat void/refund, serta batas
/// diskon yang boleh diberikan kasir tanpa otorisasi. Field lain sengaja
/// diabaikan supaya model tetap ringan.
class OutletAppSettings {
  /// Bila true, refund transaksi mensyaratkan `override_pin` manajer berwenang.
  final bool requirePinRefund;

  /// Bila true, void (batalkan) transaksi mensyaratkan `override_pin`.
  final bool requirePinVoid;

  /// B1c: batas diskon (persen, 0-100) yang boleh diberikan kasir tanpa
  /// otorisasi. `0` = tanpa batas. Bila diskon melampaui batas ini, backend
  /// menolak checkout (HTTP 400, pesan mengandung "melebihi batas") kecuali
  /// disertai `override_pin` manajer berwenang.
  final num maxDiscountPercent;

  const OutletAppSettings({
    this.requirePinRefund = false,
    this.requirePinVoid = false,
    this.maxDiscountPercent = 0,
  });

  factory OutletAppSettings.fromJson(Map<String, dynamic> json) {
    final rawMax = json['max_discount_percent'];
    return OutletAppSettings(
      requirePinRefund: json['require_pin_refund'] as bool? ?? false,
      requirePinVoid: json['require_pin_void'] as bool? ?? false,
      // Backend mengirim num; toleran juga bila datang sebagai string.
      maxDiscountPercent:
          rawMax is num ? rawMax : num.tryParse('${rawMax ?? ''}') ?? 0,
    );
  }

  /// Round-trip ke payload backend (`PUT /outlets/:id/app-settings`). Saat ini
  /// app kasir hanya membaca app-settings (tidak ada layar edit di mobile),
  /// tapi field disertakan supaya nilai bertahan penuh bila nanti ditulis ulang.
  Map<String, dynamic> toJson() => {
        'require_pin_refund': requirePinRefund,
        'require_pin_void': requirePinVoid,
        'max_discount_percent': maxDiscountPercent,
      };
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
