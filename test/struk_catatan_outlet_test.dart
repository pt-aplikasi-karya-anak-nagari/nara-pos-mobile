import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/printer/domain/receipt_settings.dart';

// Catatan outlet di struk cetak — diatur Owner per outlet di dashboard web,
// dicetak kasir persis per baris.

void main() {
  OutletReceiptSettings rs(Object? catatan) => OutletReceiptSettings.fromJson({
        'outlet_id': 'O1',
        'footer_note': catatan,
      });

  test('catatan dicetak per baris; baris kosong di tengah dipertahankan', () {
    expect(
      rs('\r\nBarang tidak dapat ditukar.  \r\n\r\nBuka 08.00–22.00\n\n')
          .barisCatatan,
      ['Barang tidak dapat ditukar.', '', 'Buka 08.00–22.00'],
    );
  });

  test('catatan kosong / tak dikirim server lama → tidak dicetak', () {
    expect(rs('').barisCatatan, isEmpty);
    expect(rs('  \n \n').barisCatatan, isEmpty);
    expect(rs(null).barisCatatan, isEmpty);
    expect(OutletReceiptSettings.defaults('O1').barisCatatan, isEmpty);
  });

  test('catatan ikut dikirim balik saat pengaturan disimpan dari aplikasi', () {
    expect(rs('Halo').toJson()['footer_note'], 'Halo');
  });
}
