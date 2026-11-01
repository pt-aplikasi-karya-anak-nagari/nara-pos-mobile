import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/products/domain/product.dart';
import 'package:nara_pos_mobile/features/tables/ui/widgets/pisah_bill_sheet.dart';
import 'package:nara_pos_mobile/features/transactions/domain/sale.dart';
import 'package:nara_pos_mobile/features/transactions/domain/sale_item.dart';

Sale tagihan() {
  // Kopi 20.000 × 3 + Nasi 30.000 × 1 = 90.000, total + pajak 10% = 99.000.
  final s = Sale(
    createdAt: DateTime(2026, 11, 1),
    subtotal: 90000,
    tax: 9000,
    total: 99000,
    paymentMethod: 'Bayar Nanti',
  );
  s.items = [
    SaleItem(productName: 'Kopi', productEmoji: '', price: 20000, qty: 3)
      ..id = 'kopi',
    SaleItem(productName: 'Nasi', productEmoji: '', price: 30000, qty: 1)
      ..id = 'nasi',
  ];
  return s;
}

void main() {
  group('pisah bill', () {
    test('perkiraan mengikuti porsi subtotal', () {
      expect(perkiraanPisah(tagihan(), {'kopi': 2}), 44000);
      expect(perkiraanPisah(tagihan(), {'nasi': 1}), 33000);
      expect(perkiraanPisah(tagihan(), {}), 0);
    });

    test('qty melebihi pesanan dijepit', () {
      expect(perkiraanPisah(tagihan(), {'kopi': 9}), 66000);
    });

    test('alasan tak bisa dipisah', () {
      expect(alasanTakBisaPisah(tagihan(), {}), isNotNull);
      expect(
        alasanTakBisaPisah(tagihan(), {'kopi': 3, 'nasi': 1}),
        contains('Bayar'),
      );
      expect(alasanTakBisaPisah(tagihan(), {'kopi': 1}), isNull);
    });
  });

  group('paket', () {
    test('produk membaca is_bundle & bundle_items, dan round-trip cache', () {
      final p = Product.fromJson({
        'id': 'pkt',
        'name': 'Paket Hemat',
        'price': 30000,
        'track_stock': false,
        'available_portions': 3,
        'is_bundle': true,
        'bundle_items': [
          {'product_id': 'nasi', 'name': 'Nasi', 'qty': 1},
          {
            'product_id': 'kopi',
            'name': 'Kopi',
            'variant_name': 'Large',
            'qty': 2,
          },
        ],
      });
      expect(p.isBundle, isTrue);
      expect(p.bundleLabel, '1× Nasi, 2× Kopi (Large)');
      final lagi = Product.fromJson(p.toJson());
      expect(lagi.isBundle, isTrue);
      expect(lagi.bundleItems.length, 2);
      expect(lagi.availablePortions, 3);
    });

    test('produk lama tanpa field paket tetap produk biasa', () {
      final p = Product.fromJson({'id': 'x', 'name': 'Kopi', 'price': 1});
      expect(p.isBundle, isFalse);
      expect(p.bundleItems, isEmpty);
      expect(p.bundleLabel, '');
    });

    test('isi paket di baris penjualan dikalikan qty', () {
      final it = SaleItem.fromJson({
        'id': 'i1',
        'product_name': 'Paket Hemat',
        'price_at_time': 30000,
        'quantity': 2,
        'bundle_items': [
          {'product_id': 'nasi', 'name': 'Nasi', 'qty': 1},
          {'product_id': 'ayam', 'name': 'Ayam', 'qty': 2},
        ],
      });
      expect(it.bundleLabel, '2× Nasi, 4× Ayam');
    });
  });
}
