import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/kasir/domain/pajak_multi_tarif.dart';

// Detail transaksi dulu selalu menampilkan satu baris "PPN" berisi total
// pajak, padahal struk cetak & keranjang sudah merinci per tarif — kasir
// melihat angka yang berbeda dengan kertas yang dipegang pelanggan.

BarisPajak _b(String nama, double persen, double pajak) => BarisPajak(
  tarifId: nama,
  nama: nama,
  persen: persen,
  dasar: pajak * 10,
  pajak: pajak,
);

void main() {
  group('barisPajakTampil', () {
    test('multi-tarif: satu baris per tarif, tarif nol dilewati', () {
      final baris = barisPajakTampil([
        _b('PB1', 10, 10000),
        _b('PPN', 11, 2200),
        _b('Bebas', 0, 0),
      ], 12200);
      expect(baris, [
        (label: 'PB1 (10%)', nilai: 10000.0),
        (label: 'PPN (11%)', nilai: 2200.0),
      ]);
    });

    test('satu tarif (transaksi lama tanpa rincian): satu baris "Pajak"', () {
      expect(barisPajakTampil(const [], 5000), [
        (label: 'Pajak', nilai: 5000.0),
      ]);
    });

    test('tanpa pajak: tidak ada baris', () {
      expect(barisPajakTampil(const [], 0), isEmpty);
    });

    test('persen pecahan memakai koma', () {
      expect(
        barisPajakTampil([_b('PPh', 2.5, 250)], 250).single.label,
        'PPh (2,5%)',
      );
    });
  });

  test(
    'detail transaksi memakai barisPajakTampil, bukan label "PPN" tetap',
    () {
      final sumber = File(
        'lib/features/transactions/ui/transaction_detail_page.dart',
      ).readAsStringSync();
      expect(sumber, contains('barisPajakTampil(sale.rincianPajak, sale.tax)'));
      expect(sumber, isNot(contains("label: 'PPN'")));
    },
  );
}
