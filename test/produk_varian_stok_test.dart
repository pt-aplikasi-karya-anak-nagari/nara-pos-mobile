import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/products/domain/product.dart';

// Produk bervarian tak bisa ditambahkan ke keranjang dari HP.
//
// `product.stock` untuk produk bervarian selalu 0 — yang dijual adalah
// variannya, dan stok hidup di masing-masing varian. Kartu produk membaca kolom
// induk itu, jadi tombol tambahnya mati.
//
// Yang membuatnya menyebalkan: pada kasus stok induk kecil-tapi-positif,
// pemblokirannya terjadi TANPA label "Habis" dan TANPA pesan apa pun. Kasir
// hanya melihat tombol yang tak melakukan apa-apa, dan tak ada di layar yang
// menjelaskan kenapa.

Product _p({int stock = 0, List<int> varian = const []}) => Product(
      remoteId: 'P1',
      name: 'Kopi Susu',
      price: 20000,
      stock: stock,
      variants: varian
          .asMap()
          .entries
          .map((e) => ProductVariant(
                productId: 'P1',
                name: 'Ukuran ${e.key}',
                price: 20000,
                stock: e.value,
              ))
          .toList(),
    );

void main() {
  test('stok jual produk bervarian = jumlah stok variannya', () {
    expect(_p(stock: 0, varian: [50, 30, 20]).stokJual, 100);
  });

  test('produk bervarian TIDAK dinilai habis walau stok induk 0', () {
    // Inti bugnya. Sebelum perbaikan, stokJual = stock = 0 → tombol mati.
    final p = _p(stock: 0, varian: [50, 50]);
    expect(p.stock, 0, reason: 'premis: stok induk memang 0');
    expect(p.stokJual, greaterThan(0),
        reason: 'kasir tak bisa menjual barang yang jelas ada di rak');
  });

  test('habis hanya bila SEMUA varian habis', () {
    // Sisi yang membuat perbaikan ini berarti: penjaga yang selalu bilang
    // "ada" akan membiarkan kasir menjual barang yang benar-benar habis.
    expect(_p(stock: 0, varian: [0, 0, 0]).stokJual, 0);
    expect(_p(stock: 0, varian: [0, 0, 1]).stokJual, 1);
  });

  test('produk TANPA varian tetap memakai stok induknya', () {
    // Perilaku lama untuk produk biasa tak boleh berubah. Perbaikan yang
    // menilai semua produk dari varian akan menganggap SETIAP produk
    // non-varian habis, karena daftar variannya memang kosong.
    expect(_p(stock: 7).stokJual, 7);
    expect(_p(stock: 0).stokJual, 0);
  });
}
