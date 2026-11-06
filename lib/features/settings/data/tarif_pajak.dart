import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/outlet_scope.dart';
import '../../../core/shared_prefs.dart';
import '../../kasir/domain/pajak_multi_tarif.dart';

/// Tarif pajak TAMBAHAN outlet aktif (pajak multi-tarif), dikunci per ID.
///
/// Diambil dari GET /outlets/:id/tax (field `tax_rates`, hanya yang aktif —
/// boleh dibaca kasir), lalu disalin ke SharedPreferences supaya kasir offline
/// tetap menghitung per tarif. Gagal & tanpa salinan → kosong: semua produk
/// memakai tarif default (server tetap otoritatif saat transaksi tersinkron).
final tarifPajakFutureProvider =
    FutureProvider<Map<String, TarifPajak>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null || outletId.isEmpty) return const {};
  final prefs = ref.read(sharedPreferencesProvider);
  final kunci = 'tarif_pajak_$outletId';

  Map<String, TarifPajak> dariDaftar(List<dynamic> daftar) => {
        for (final j in daftar.whereType<Map>())
          if ((j['id'] ?? '').toString().isNotEmpty)
            j['id'].toString():
                TarifPajak.fromJson(Map<String, dynamic>.from(j)),
      };

  try {
    final res = await ref.read(dioProvider).get('/outlets/$outletId/tax');
    final body = res.data;
    final data = body is Map ? body['data'] : null;
    final daftar = data is Map ? (data['tax_rates'] as List? ?? const []) : const [];
    await prefs.setString(kunci, jsonEncode(daftar));
    return dariDaftar(daftar);
  } catch (_) {
    final simpan = prefs.getString(kunci);
    if (simpan == null || simpan.isEmpty) return const {};
    try {
      return dariDaftar(jsonDecode(simpan) as List<dynamic>);
    } catch (_) {
      return const {};
    }
  }
});

/// Versi sinkron untuk provider hitung keranjang. Selama memuat → kosong.
final tarifPajakProvider = Provider<Map<String, TarifPajak>>(
  (ref) => ref.watch(tarifPajakFutureProvider).value ?? const {},
);
