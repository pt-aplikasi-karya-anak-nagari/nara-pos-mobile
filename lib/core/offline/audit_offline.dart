import 'dart:async';

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/user/data/auth_service.dart';
import '../connectivity_service.dart';
import '../device_identity.dart';
import '../network/api_endpoint.dart';
import '../network/dio_client.dart';
import '../outlet_scope.dart';
import 'nomor_struk_offline.dart';
import 'offline_sync_service.dart';
import 'sale_outbox.dart';
import '../shared_prefs.dart';
import 'shift_outbox.dart';
import 'tanda_tangan.dart';

/// Pengawasan transaksi offline — sisi perangkat. Lihat package offlineaudit
/// di server untuk celah yang ditutup.
class AuditOfflineApi {
  AuditOfflineApi(this._dio);
  final Dio _dio;

  /// Kirim laporan perangkat. Senyap: berjalan di latar.
  Future<void> laporPerangkat(String outletId, Map<String, dynamic> data) =>
      _dio.post<dynamic>(
        ApiEndpoint.offlineLaporanPerangkat(outletId),
        data: data,
        options: Options(extra: {'senyap': true}),
      );

  /// Daftarkan kunci publik tanda tangan perangkat. true = terdaftar (atau
  /// sudah); false = server menolak karena perangkat ini sudah punya kunci
  /// lain (hanya Pemilik yang bisa mencabutnya). Galat lain dilempar.
  Future<bool> daftarkanKunci(
    String outletId,
    String deviceId,
    String kunciPublik,
  ) async {
    try {
      await _dio.post<dynamic>(
        ApiEndpoint.offlineKunciPerangkat(outletId),
        data: {'device_id': deviceId, 'public_key': kunciPublik},
        options: Options(extra: {'senyap': true}),
      );
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) return false;
      rethrow;
    }
  }

  /// Catat transaksi offline yang akan dibuang. Melempar [GagalCatatBuang]
  /// berisi pesan dari server (mis. PIN salah) — perangkat TIDAK boleh
  /// menghapus salinannya bila ini gagal.
  Future<String> catatBuang(String outletId, Map<String, dynamic> data) async {
    try {
      final res = await _dio.post<dynamic>(
        ApiEndpoint.offlineBuang(outletId),
        data: data,
        options: Options(extra: {'senyap': true}),
      );
      final body = res.data;
      final d = body is Map ? body['data'] : null;
      return d is Map ? (d['disetujui_oleh']?.toString() ?? '') : '';
    } on DioException catch (e) {
      final body = e.response?.data;
      final pesan = body is Map ? body['message']?.toString() : null;
      throw GagalCatatBuang(
        pesan ??
            (e.response == null
                ? 'Tidak ada koneksi ke server.'
                : 'Server menolak (${e.response?.statusCode}).'),
      );
    }
  }
}

class GagalCatatBuang implements Exception {
  GagalCatatBuang(this.pesan);
  final String pesan;
  @override
  String toString() => pesan;
}

final auditOfflineApiProvider = Provider<AuditOfflineApi>(
  (ref) => AuditOfflineApi(ref.watch(dioProvider)),
);

/// Susun laporan perangkat untuk outlet [outletId] dari isi antrian.
///
/// Fungsi murni (tanpa plugin) supaya bisa diuji.
Map<String, dynamic> susunLaporanPerangkat({
  required String outletId,
  required String deviceId,
  required String deviceLabel,
  required String kodeStruk,
  required int urutTerakhir,
  required List<PendingSale> penjualanMenunggu,
  required List<PendingSale> penjualanGagal,
  required int shiftMenunggu,
}) {
  final milikOutlet = [
    ...penjualanMenunggu,
    ...penjualanGagal,
  ].where((s) => s.outletId == outletId).toList();
  DateTime? tertua;
  for (final s in milikOutlet) {
    if (tertua == null || s.createdAt.isBefore(tertua)) tertua = s.createdAt;
  }
  return {
    'device_id': deviceId,
    'device_label': deviceLabel,
    'kode_struk': kodeStruk,
    'urut_terakhir': urutTerakhir,
    'antrian_penjualan': penjualanMenunggu
        .where((s) => s.outletId == outletId)
        .length,
    'antrian_gagal': penjualanGagal.where((s) => s.outletId == outletId).length,
    'antrian_shift': shiftMenunggu,
    'antrian_tertua': tertua?.toUtc().toIso8601String(),
    'ref_tertahan': [
      for (final s in milikOutlet)
        if ((s.payload['offline_ref']?.toString() ?? '').startsWith('OFF-'))
          s.payload['offline_ref'].toString(),
    ],
  };
}

/// Laporan perangkat otomatis: setiap koneksi kembali, setiap selesai
/// mengirim antrian, saat ganti outlet, dan tiap 5 menit selama online.
/// Di-watch sekali di shell aplikasi.
///
/// Yang paling penting dari laporan ini adalah nomor struk offline TERTINGGI
/// yang pernah dipakai perangkat: server menyimpannya dan tak pernah
/// menurunkannya. Penjualan offline yang dihapus dari perangkat sebelum
/// terkirim lalu tampil sebagai nomor yang hilang.
final laporanPerangkatOtomatisProvider = Provider<void>((ref) {
  var berjalan = false;

  Future<void> lapor() async {
    if (berjalan) return;
    if (ref.read(authProvider).user == null) return;
    if (ref.read(isOfflineProvider)) return;
    final outletId = ref.read(activeOutletIdProvider);
    if (outletId == null || outletId.isEmpty) return;
    final nomor = ref.read(nomorStrukOfflineProvider);
    final identitas = DeviceIdentity.current;
    berjalan = true;
    try {
      final outbox = ref.read(saleOutboxProvider);
      final data = susunLaporanPerangkat(
        outletId: outletId,
        deviceId: identitas.id,
        deviceLabel: identitas.label,
        kodeStruk: nomor.kodePerangkat,
        urutTerakhir: nomor.urutTerakhir,
        penjualanMenunggu: await outbox.pending(),
        penjualanGagal: await outbox.deadLetters(),
        shiftMenunggu: await ref.read(shiftOutboxProvider).count(),
      );
      await ref.read(auditOfflineApiProvider).laporPerangkat(outletId, data);
      await _daftarkanKunciSekali(ref, outletId, identitas.id);
    } catch (_) {
      // Dicoba lagi pada pemicu berikutnya.
    } finally {
      berjalan = false;
    }
  }

  void jalan() => unawaited(lapor());

  ref.listen<String?>(activeOutletIdProvider, (_, _) => jalan());
  ref.listen<AsyncValue<ConnectionStatus>>(connectivityProvider, (_, next) {
    if (next.value == ConnectionStatus.online) jalan();
  });
  ref.listen<DateTime?>(
    progresSinkronProvider.select((p) => p.selesaiPada),
    (_, _) => jalan(),
  );
  final timer = Timer.periodic(const Duration(minutes: 5), (_) => jalan());
  ref.onDispose(timer.cancel);
  Future.microtask(jalan);
});

/// Daftarkan kunci tanda tangan perangkat ke server, sekali per outlet. Hasil
/// disimpan supaya tak diulang tiap 5 menit; penolakan (perangkat sudah punya
/// kunci lain) juga diingat — mengulanginya tak akan mengubah apa pun.
Future<void> _daftarkanKunciSekali(
  Ref ref,
  String outletId,
  String deviceId,
) async {
  if (deviceId.isEmpty) return;
  final prefs = ref.read(sharedPreferencesProvider);
  final kunciPrefs = 'offline.kunci_terdaftar.$outletId';
  final pub = await ref.read(kunciTandaTanganProvider).kunciPublik();
  final tersimpan = prefs.getString(kunciPrefs);
  if (tersimpan == pub || tersimpan == 'konflik:$pub') return;
  final ok = await ref
      .read(auditOfflineApiProvider)
      .daftarkanKunci(outletId, deviceId, pub);
  await prefs.setString(kunciPrefs, ok ? pub : 'konflik:$pub');
}

/// Pastikan kunci perangkat ini sudah terdaftar di outlet — dipanggil
/// sebelum absen di outlet yang mewajibkan perangkat terdaftar, supaya
/// tablet yang baru dipasang tak perlu menunggu laporan berkala 5 menit.
Future<void> pastikanKunciPerangkatTerdaftar(Ref ref, String outletId) async {
  try {
    await _daftarkanKunciSekali(ref, outletId, DeviceIdentity.current.id);
  } catch (_) {
    // Server yang memutuskan; galatnya muncul sebagai penolakan absen.
  }
}
