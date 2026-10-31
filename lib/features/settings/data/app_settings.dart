import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/offline/entity_cache.dart';
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

  /// Batas lama tablet boleh berjualan tanpa tersambung ke server (jam).
  /// Lewat dari itu penjualan offline baru ditolak. `0` = tanpa batas —
  /// juga nilai untuk pengaturan tersimpan dari versi sebelum field ini ada.
  final int maxOfflineHours;

  /// Kasir boleh berganti saat tablet offline (kartu / PIN yang pernah
  /// dipakai online di tablet ini). Aktif bila tak disebut — sama dengan
  /// bawaan server.
  final bool allowOfflineCashierSwitch;

  /// Pemilik mengizinkan "Pesanan Custom" (nama & harga diketik kasir, tanpa
  /// stok). Aktif bila tak disebut — sama dengan bawaan server, yang juga
  /// menolak pesanan custom bila dimatikan.
  final bool allowCustomItems;

  /// Aturan absensi (backend internal/attendance/aturan.go). Aplikasi
  /// memakainya untuk menyiapkan bukti: meminta lokasi hanya bila radius
  /// aktif, dan mewajibkan foto di layar absen. Server tetap yang memutuskan.
  final int absenRadiusMeter;
  final bool absenWajibFoto;
  final bool absenPerangkatTerdaftar;

  /// Suara panggilan antrian diatur Pemilik: nyala/mati untuk seluruh outlet
  /// dan kalimat yang diucapkan (lihat kalimat_panggilan.dart).
  final bool antrianSuaraAktif;

  /// Fitur nomor antrian dipakai outlet ini (Pemilik bisa mematikannya).
  final bool antrianAktif;
  final String antrianTeksPanggilan;

  const OutletAppSettings({
    this.requirePinRefund = false,
    this.requirePinVoid = false,
    this.maxDiscountPercent = 0,
    this.maxOfflineHours = 0,
    this.allowOfflineCashierSwitch = true,
    this.allowCustomItems = true,
    this.absenRadiusMeter = 0,
    this.absenWajibFoto = false,
    this.absenPerangkatTerdaftar = false,
    this.antrianSuaraAktif = true,
    this.antrianAktif = true,
    this.antrianTeksPanggilan = '',
  });

  factory OutletAppSettings.fromJson(Map<String, dynamic> json) {
    final rawMax = json['max_discount_percent'];
    return OutletAppSettings(
      requirePinRefund: json['require_pin_refund'] as bool? ?? false,
      requirePinVoid: json['require_pin_void'] as bool? ?? false,
      // Backend mengirim num; toleran juga bila datang sebagai string.
      maxDiscountPercent: rawMax is num
          ? rawMax
          : num.tryParse('${rawMax ?? ''}') ?? 0,
      maxOfflineHours: switch (json['max_offline_hours']) {
        final num n => n.toInt(),
        final Object? v => int.tryParse('${v ?? ''}') ?? 0,
      },
      allowOfflineCashierSwitch:
          json['allow_offline_cashier_switch'] as bool? ?? true,
      allowCustomItems: json['allow_custom_items'] as bool? ?? true,
      absenRadiusMeter: switch (json['absen_radius_meter']) {
        final num n => n.toInt(),
        final Object? v => int.tryParse('${v ?? ''}') ?? 0,
      },
      absenWajibFoto: json['absen_wajib_foto'] as bool? ?? false,
      absenPerangkatTerdaftar:
          json['absen_perangkat_terdaftar'] as bool? ?? false,
      antrianSuaraAktif: json['antrian_suara_aktif'] as bool? ?? true,
      antrianAktif: json['antrian_aktif'] as bool? ?? true,
      antrianTeksPanggilan: json['antrian_teks_panggilan']?.toString() ?? '',
    );
  }

  /// Round-trip ke payload backend (`PUT /outlets/:id/app-settings`). Saat ini
  /// app kasir hanya membaca app-settings (tidak ada layar edit di mobile),
  /// tapi field disertakan supaya nilai bertahan penuh bila nanti ditulis ulang.
  Map<String, dynamic> toJson() => {
    'require_pin_refund': requirePinRefund,
    'require_pin_void': requirePinVoid,
    'max_discount_percent': maxDiscountPercent,
    'max_offline_hours': maxOfflineHours,
    'allow_offline_cashier_switch': allowOfflineCashierSwitch,
    'allow_custom_items': allowCustomItems,
    'absen_radius_meter': absenRadiusMeter,
    'absen_wajib_foto': absenWajibFoto,
    'absen_perangkat_terdaftar': absenPerangkatTerdaftar,
    'antrian_suara_aktif': antrianSuaraAktif,
    'antrian_aktif': antrianAktif,
    'antrian_teks_panggilan': antrianTeksPanggilan,
  };
}

/// Pengaturan aplikasi outlet aktif. Dipakai dialog refund/void untuk tahu
/// apakah PIN otorisasi manajer wajib diisi.
///
/// FutureProvider — di-cache setelah fetch pertama. Callsite umumnya membaca
/// via `ref.read(outletAppSettingsProvider.future)` supaya nilai terjamin
/// termuat sebelum dialog dibuka. Bila fetch gagal (mis. offline), callsite
/// fallback ke penanganan error 403 dari backend.
final outletAppSettingsProvider = FutureProvider<OutletAppSettings>((
  ref,
) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return const OutletAppSettings();
  // Disimpan untuk offline: batas diskon kasir dibutuhkan saat berjualan
  // tanpa internet (lihat kasir/domain/batas_diskon.dart).
  final st = await readThroughCacheOne<OutletAppSettings>(
    cache: _appSettingsCache,
    outletId: outletId,
    fetch: () async => OutletAppSettings.fromJson(
      await ref.read(outletServiceProvider).getAppSettings(outletId),
    ),
  );
  return st ?? const OutletAppSettings();
});

final _appSettingsCache = EntityCache<OutletAppSettings>(
  'app_settings',
  toJson: (s) => s.toJson(),
  fromJson: OutletAppSettings.fromJson,
);

/// Pengaturan outlet yang terakhir tersimpan di perangkat — TANPA menyentuh
/// jaringan. Dipakai di jalur checkout offline, yang tak boleh menunggu
/// permintaan yang pasti gagal. Kosong (tanpa batas) bila belum pernah
/// tersimpan.
Future<OutletAppSettings> bacaAppSettingsTersimpan(String outletId) async {
  try {
    final ada = await _appSettingsCache.getAll(outletId);
    return ada.isEmpty ? const OutletAppSettings() : ada.first;
  } catch (_) {
    return const OutletAppSettings();
  }
}
