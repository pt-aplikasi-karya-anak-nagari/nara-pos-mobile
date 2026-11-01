import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/transactions/domain/sale_item.dart';

// Struk & riwayat merinci harga satu unit: ukuran/varian lalu tiap topping.
// original_price dari server MEMUAT add-on, jadi harga ukuran = asal − add-on.

void main() {
  test('ukuran + topping dari JSON server', () {
    final it = SaleItem.fromJson({
      'id': 'i1',
      'product_name': 'Kopi Susu',
      'variant_name': 'Large',
      'quantity': 2,
      'original_price': 31000,
      'price_at_time': 31000,
      'modifiers': [
        {'name': 'Boba', 'price': 5000, 'group_name': 'Topping'},
        {'name': 'Extra Shot', 'price': 4000},
        {'name': 'Less Sugar', 'price': 0, 'group_name': 'Gula'},
      ],
    });
    expect(it.hargaDasar, 22000);
    expect(
      it.rincianHarga.map((r) => (r.label, r.harga, r.tambahan)).toList(),
      [
        ('Harga dasar (Large)', 22000.0, false),
        ('Topping: Boba', 5000.0, true),
        ('Extra Shot', 4000.0, true),
        ('Gula: Less Sugar', 0.0, true),
      ],
    );
  });

  test('diskon tidak mengubah harga ukuran (pakai harga asal)', () {
    final it = SaleItem.fromJson({
      'product_name': 'Kopi',
      'variant_name': 'Regular',
      'quantity': 1,
      'original_price': 20000,
      'price_at_time': 18000,
      'discount_amount': 2000,
    });
    expect(it.rincianHarga.single.harga, 20000);
  });

  test('topping tanpa varian → label Harga', () {
    final it = SaleItem.fromJson({
      'product_name': 'Roti Bakar',
      'quantity': 1,
      'original_price': 18000,
      'price_at_time': 18000,
      'modifiers': [
        {'name': 'Keju', 'price': 3000},
      ],
    });
    expect(it.rincianHarga.first.label, 'Harga dasar');
    expect(it.rincianHarga.first.harga, 15000);
  });

  test('baris biasa & data lama tidak dirinci', () {
    final biasa = SaleItem.fromJson({
      'product_name': 'Air Mineral',
      'quantity': 1,
      'price_at_time': 5000,
    });
    expect(biasa.rincianHarga, isEmpty);
    expect(AddOnStruk.dariJson(null), isEmpty);
  });

  test('ukuran sebagai add-on (grup Ukuran) berlabel grupnya', () {
    final it = SaleItem.fromJson({
      'product_name': 'Teh Telur',
      'quantity': 1,
      'original_price': 22000,
      'price_at_time': 22000,
      'modifiers': [
        {'name': 'Large', 'price': 7000, 'group_name': 'Ukuran'},
        {'name': 'Boba', 'price': 3000, 'group_name': 'Topping'},
      ],
    });
    expect(it.rincianHarga.map((r) => r.label).toList(), [
      'Harga dasar',
      'Ukuran: Large',
      'Topping: Boba',
    ]);
    expect(it.rincianHarga.fold<double>(0, (s, r) => s + r.harga), 22000);
  });
}
