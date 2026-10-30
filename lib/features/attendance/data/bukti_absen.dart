import 'package:geolocator/geolocator.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/device_identity.dart';
import '../../../core/offline/audit_offline.dart';
import '../../../core/offline/tanda_tangan.dart';
import '../../settings/data/app_settings.dart';
import '../../user/data/auth_service.dart';

/// Bukti yang dikirim bersama absen masuk/pulang: tanda tangan perangkat
/// dan — bila outlet mewajibkan radius — lokasi GPS.
///
/// Server yang memutuskan diterima atau tidak (backend
/// internal/attendance/aturan.go). Di sini hanya disiapkan, dan galat yang
/// bisa diketahui lebih dulu (GPS mati, izin ditolak) dijelaskan sebelum
/// permintaan dikirim.
class BuktiAbsen {
  BuktiAbsen(this._ref);
  final Ref _ref;

  Future<Map<String, dynamic>> susun({
    required String outletId,
    required String jenis, // masuk | pulang
  }) async {
    final aturan = await _ref
        .read(outletAppSettingsProvider.future)
        .catchError((_) => const OutletAppSettings());
    final bukti = <String, dynamic>{};

    // Tanda tangan perangkat — selalu disertakan bila memungkinkan, supaya
    // Pemilik bisa melihat absen dilakukan dari perangkat mana.
    final deviceId = DeviceIdentity.current.id;
    final userId = _ref.read(authProvider).user?.remoteId ?? '';
    if (deviceId.isNotEmpty && userId.isNotEmpty) {
      if (aturan.absenPerangkatTerdaftar) {
        await pastikanKunciPerangkatTerdaftar(_ref, outletId);
      }
      final waktu = DateTime.now().toUtc().toIso8601String();
      try {
        bukti
          ..['device_id'] = deviceId
          ..['waktu'] = waktu
          ..['tanda_tangan'] = await _ref
              .read(kunciTandaTanganProvider)
              .tandatanganiTeks(
                pesanAbsen(
                  outletId: outletId,
                  userId: userId,
                  jenis: jenis,
                  waktu: waktu,
                  deviceId: deviceId,
                ),
              );
      } catch (_) {
        bukti.remove('tanda_tangan');
      }
    }

    if (aturan.absenRadiusMeter > 0) {
      final pos = await _lokasi();
      bukti
        ..['latitude'] = pos.latitude
        ..['longitude'] = pos.longitude
        ..['akurasi_m'] = pos.accuracy
        ..['lokasi_palsu'] = pos.isMocked;
    }
    return bukti;
  }

  Future<Position> _lokasi() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw 'GPS mati. Nyalakan lokasi perangkat — outlet ini mewajibkan '
          'absen dari lokasi outlet.';
    }
    var izin = await Geolocator.checkPermission();
    if (izin == LocationPermission.denied) {
      izin = await Geolocator.requestPermission();
    }
    if (izin == LocationPermission.denied ||
        izin == LocationPermission.deniedForever) {
      throw 'Izin lokasi ditolak. Izinkan akses lokasi untuk NARA POS di '
          'pengaturan perangkat — outlet ini mewajibkan absen dari lokasi '
          'outlet.';
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      throw 'Lokasi belum didapat. Coba lagi di tempat terbuka atau dekat '
          'jendela.';
    }
  }
}

final buktiAbsenProvider = Provider<BuktiAbsen>((ref) => BuktiAbsen(ref));
