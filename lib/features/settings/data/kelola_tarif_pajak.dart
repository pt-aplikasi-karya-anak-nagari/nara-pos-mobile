import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/network/dio_client.dart';
import 'tarif_pajak.dart';

/// Satu tarif pajak tambahan outlet beserta jumlah produk yang memakainya —
/// bentuk `GET /outlets/:id/tax-rates` (taxrate.TarifView di backend).
class TarifPajakKelola {
  final String id;
  final String nama;
  final double persen;
  final bool aktif;
  final int jumlahProduk;

  const TarifPajakKelola({
    required this.id,
    required this.nama,
    required this.persen,
    required this.aktif,
    this.jumlahProduk = 0,
  });

  factory TarifPajakKelola.fromJson(Map<String, dynamic> j) => TarifPajakKelola(
    id: (j['id'] ?? '').toString(),
    nama: (j['name'] as String?)?.trim() ?? '',
    persen: (j['percent'] as num? ?? 0).toDouble(),
    aktif: j['is_active'] as bool? ?? true,
    jumlahProduk: (j['product_count'] as num? ?? 0).toInt(),
  );

  /// "PPN 11%" / "PPh 2,5%".
  String get label => '$nama ${formatPersenTarif(persen)}';
}

String formatPersenTarif(double p) {
  final s = p == p.roundToDouble()
      ? p.toStringAsFixed(0)
      : p
            .toStringAsFixed(2)
            .replaceAll(RegExp(r'0+$'), '')
            .replaceAll('.', ',');
  return '$s%';
}

/// Validasi formulir tarif — sama dengan backend (internal/taxrate), supaya
/// kesalahan tertangkap sebelum dikirim. null = sah.
String? validasiTarif(String nama, String persenTeks) {
  final n = nama.trim();
  if (n.isEmpty) return 'Nama tarif wajib diisi, mis. PPN atau PB1';
  if (n.length > 40) return 'Nama tarif maksimal 40 karakter';
  final p = double.tryParse(persenTeks.trim().replaceAll(',', '.'));
  if (p == null) return 'Persen tarif harus berupa angka';
  if (p < 0 || p > 100) return 'Persen tarif harus antara 0 dan 100';
  return null;
}

/// CRUD tarif pajak tambahan (pajak multi-tarif). Server memeriksa izin
/// `settings.tax`; pesan galatnya diteruskan apa adanya.
class KelolaTarifPajakRepository {
  KelolaTarifPajakRepository(this._dio);
  final Dio _dio;

  Future<List<TarifPajakKelola>> daftar(String outletId) async {
    final res = await _panggil(() => _dio.get('/outlets/$outletId/tax-rates'));
    final data = res.data is Map ? res.data['data'] : null;
    return [
      for (final j in (data is List ? data : const []).whereType<Map>())
        TarifPajakKelola.fromJson(Map<String, dynamic>.from(j)),
    ];
  }

  Future<void> tambah(
    String outletId, {
    required String nama,
    required double persen,
  }) => _panggil(
    () => _dio.post(
      '/outlets/$outletId/tax-rates',
      data: {'name': nama.trim(), 'percent': persen, 'is_active': true},
    ),
  );

  Future<void> ubah(
    String outletId,
    String id, {
    required String nama,
    required double persen,
    required bool aktif,
  }) => _panggil(
    () => _dio.put(
      '/outlets/$outletId/tax-rates/$id',
      data: {'name': nama.trim(), 'percent': persen, 'is_active': aktif},
    ),
  );

  Future<void> hapus(String outletId, String id) =>
      _panggil(() => _dio.delete('/outlets/$outletId/tax-rates/$id'));

  Future<Response<dynamic>> _panggil(
    Future<Response<dynamic>> Function() f,
  ) async {
    try {
      return await f();
    } on DioException catch (e) {
      final body = e.response?.data;
      final pesan = body is Map ? body['message']?.toString() : null;
      if (pesan != null && pesan.isNotEmpty) throw pesan;
      if (e.response?.statusCode == 403) {
        throw 'Anda tidak punya izin mengatur pajak di outlet ini';
      }
      throw 'Tidak bisa terhubung ke server';
    }
  }
}

final kelolaTarifPajakRepositoryProvider = Provider<KelolaTarifPajakRepository>(
  (ref) => KelolaTarifPajakRepository(ref.read(dioProvider)),
);

/// Daftar tarif (aktif & nonaktif) sebuah outlet untuk layar kelola & pilihan
/// tarif di formulir produk.
final daftarTarifPajakProvider = FutureProvider.autoDispose
    .family<List<TarifPajakKelola>, String>(
      (ref, outletId) =>
          ref.read(kelolaTarifPajakRepositoryProvider).daftar(outletId),
    );

/// Setelah tarif berubah: muat ulang daftar kelola DAN salinan tarif yang
/// dipakai kasir menghitung keranjang (termasuk salinan offline-nya).
void segarkanTarifPajak(WidgetRef ref, String outletId) {
  ref.invalidate(daftarTarifPajakProvider(outletId));
  ref.invalidate(tarifPajakFutureProvider);
}
