import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/kasir/domain/pajak_multi_tarif.dart';
import 'package:nara_pos_mobile/features/outlet/domain/outlet.dart';

// PARITAS pajak multi-tarif dengan SERVER.
//
// test/fixtures/paritas_multi_tarif.json direkam server (nara-pos-be
// internal/transaction/paritas_multi_tarif_test.go). Angka di sini wajib sama
// persis: bila kasir menghitung berbeda, total yang dibayar pelanggan tak sama
// dengan yang tersimpan dan laci kas selisih.

void main() {
  final kasus = (jsonDecode(
    File('test/fixtures/paritas_multi_tarif.json').readAsStringSync(),
  ) as List)
      .cast<Map<String, dynamic>>();

  test('fixture paritas tidak kosong', () {
    expect(kasus.length, greaterThanOrEqualTo(5));
  });

  for (final k in kasus) {
    test('paritas server: ${k['name']}', () {
      final o = k['outlet'] as Map<String, dynamic>;
      final outlet = Outlet(
        name: 'Uji',
        taxEnabled: o['tax_enabled'] as bool,
        taxPercent: (o['tax_percent'] as num).toDouble(),
        taxName: o['tax_name'] as String,
        serviceChargePercent: (o['service_charge_percent'] as num).toDouble(),
        taxInclusive: o['tax_inclusive'] as bool,
      );
      final tarif = {
        for (final t in (k['tax_rates'] as List).cast<Map<String, dynamic>>())
          t['id'] as String: TarifPajak.fromJson(t),
      };
      final baris = [
        for (final it in (k['items'] as List).cast<Map<String, dynamic>>())
          BarisHitungPajak(
            subtotal: (it['subtotal'] as num).toDouble(),
            kenaPajak: it['is_taxable'] as bool,
            tarifId: (it['tax_rate_id'] as String).isEmpty
                ? null
                : it['tax_rate_id'] as String,
          ),
      ];

      final h = hitungPajakKeranjang(outlet: outlet, baris: baris, tarif: tarif);
      final e = k['expected'] as Map<String, dynamic>;
      expect(h.subtotal, (e['subtotal'] as num).toDouble(), reason: 'subtotal');
      expect(h.serviceCharge, (e['service_charge'] as num).toDouble(),
          reason: 'service');
      expect(h.tax, (e['tax'] as num).toDouble(), reason: 'pajak');
      expect(h.grandTotal, (e['total'] as num).toDouble(), reason: 'total');

      final rincian = (e['taxes'] as List).cast<Map<String, dynamic>>();
      expect(h.rincian.length, rincian.length, reason: 'jumlah baris rincian');
      for (var i = 0; i < rincian.length; i++) {
        final r = rincian[i];
        final id = r['tax_rate_id'] as String;
        expect(h.rincian[i].tarifId, id.isEmpty ? null : id);
        expect(h.rincian[i].nama, r['tax_name']);
        expect(h.rincian[i].dasar, (r['base_amount'] as num).toDouble(),
            reason: 'dasar ${r['tax_name']}');
        expect(h.rincian[i].pajak, (r['tax_amount'] as num).toDouble(),
            reason: 'pajak ${r['tax_name']}');
      }
    });
  }

  test('label baris: persen bulat tanpa koma, pecahan pakai koma', () {
    const a = BarisPajak(tarifId: null, nama: 'PPN', persen: 11, dasar: 0, pajak: 0);
    const b = BarisPajak(tarifId: 'x', nama: 'Hiburan', persen: 12.5, dasar: 0, pajak: 0);
    expect(a.label, 'PPN (11%)');
    expect(b.label, 'Hiburan (12,5%)');
  });
}
