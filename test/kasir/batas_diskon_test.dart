import 'package:flutter_test/flutter_test.dart';

import 'package:nara_pos_mobile/features/kasir/domain/batas_diskon.dart';
import 'package:nara_pos_mobile/features/kasir/domain/cart_item.dart';
import 'package:nara_pos_mobile/features/products/domain/product.dart';

// Batas diskon kasir dihitung di tablet saat offline. Rumusnya harus SAMA
// dengan server (internal/transaction/discount.go + CreateTransaction): kalau
// tablet meloloskan diskon yang server tolak, pelanggan menerima diskonnya
// tapi omzetnya tak pernah tercatat.

Product produk({
  double harga = 10000,
  String tipe = 'none',
  double nilai = 0,
}) => Product(
  remoteId: 'p1',
  name: 'Kopi',
  price: harga,
  discountType: tipe,
  discountValue: nilai,
);

void main() {
  test('tanpa diskon → 0%', () {
    expect(persenDiskonKasir([CartItem(produk(), 2)]), 0);
  });

  test('diskon bawaan Pemilik BUKAN diskon kasir', () {
    // Server: kasir yang sekadar meneruskan diskon master tak dibatasi.
    final item = CartItem(produk(tipe: 'percent', nilai: 15), 1);
    expect(persenDiskonKasir([item]), 0);
  });

  test('diskon manual kasir dihitung terhadap harga kotor', () {
    final item = CartItem(
      produk(),
      2,
      manualDiscountType: 'percent',
      manualDiscountValue: 20,
    );
    expect(persenDiskonKasir([item]), closeTo(20, 0.0001));
  });

  test('di atas diskon master: yang dihitung hanya selisihnya', () {
    // Master 15% (8.500), kasir menimpa jadi 30% (7.000) → selisih 1.500
    // dari harga kotor 10.000 = 15%.
    final item = CartItem(
      produk(tipe: 'percent', nilai: 15),
      1,
      manualDiscountType: 'percent',
      manualDiscountValue: 30,
    );
    expect(persenDiskonKasir([item]), closeTo(15, 0.0001));
  });

  test('diskon varian dihitung sebagai diskon kasir — sama seperti server', () {
    final item = CartItem(
      produk(),
      1,
      variantId: 'v1',
      variantPrice: 20000,
      variantDiscountType: 'fixed',
      variantDiscountValue: 4000,
    );
    expect(persenDiskonKasir([item]), closeTo(20, 0.0001));
  });

  test('diskon order (promo / poin) ikut dihitung', () {
    expect(
      persenDiskonKasir([CartItem(produk(), 1)], diskonOrder: 1000),
      closeTo(10, 0.0001),
    );
  });

  test('diskon order = total diskon − diskon per baris', () {
    final item = CartItem(
      produk(),
      2,
      manualDiscountType: 'fixed',
      manualDiscountValue: 1000,
    );
    // Diskon per baris 2 × 1.000 = 2.000; promo 3.000.
    expect(diskonOrderDari(diskonTotal: 5000, keranjang: [item]), 3000);
    // Tak pernah negatif.
    expect(diskonOrderDari(diskonTotal: 0, keranjang: [item]), 0);
  });

  test('batas: toleransi 0,001 dan 0 = tanpa batas', () {
    expect(melebihiBatasDiskon(10.0005, 10), isFalse);
    expect(melebihiBatasDiskon(10.01, 10), isTrue);
    expect(melebihiBatasDiskon(90, 0), isFalse);
  });
}
