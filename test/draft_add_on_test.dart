import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:nara_pos_mobile/features/drafts/domain/draft_order.dart';
import 'package:nara_pos_mobile/features/kasir/domain/cart_item.dart';
import 'package:nara_pos_mobile/features/products/domain/product.dart';

// Draft (parkir pesanan) membuang add-on.
//
// # KEJADIANNYA
//
// DraftCartItem tidak punya field modifiers sama sekali — bukan hilang
// sebagian, melainkan tak pernah ditulis. Jadi setiap pesanan ber-add-on yang
// pernah diparkir ditagih KURANG saat dilanjutkan, tiket dapur tercetak tanpa
// "+ Boba / + Extra Shot", dan laporan penjualan add-on ikut nol.
//
// # KENAPA SULIT TERLIHAT
//
// Kartu draft menampilkan totalAmount yang disimpan TERPISAH dan sudah memuat
// add-on, jadi angka di daftar draft tampak benar. Yang menyusut baru
// keranjangnya, setelah dipulihkan — dan kasir yang sedang melayani antrean
// tidak akan membandingkan dua angka itu.
//
// # YANG DIJAGA DI SINI
//
// Bukan "modifiers tersimpan", melainkan UANGNYA kembali utuh. Tes yang cuma
// membandingkan panjang daftar akan tetap hijau walau harganya hilang.

Product _produk() => Product(
      remoteId: 'P1',
      name: 'Kopi Susu',
      price: 20000,
      stock: 100,
    );

/// Snapshot produk yang disimpan draft — bentuknya Product.toJson(), bukan peta
/// yang diketik tangan, supaya tes ini ikut gagal kalau bentuknya berubah.
Map<String, dynamic> _snapshot() => _produk().toJson();

CartItem _keranjangDenganAddOn() => CartItem(
      _produk(),
      1,
      modifiers: const [
        CartModifier(
          groupId: 'G1',
          groupName: 'Topping',
          optionId: 'O1',
          name: 'Boba',
          price: 5000,
        ),
        CartModifier(
          groupId: 'G2',
          groupName: 'Extra',
          optionId: 'O2',
          name: 'Extra Shot',
          price: 5000,
        ),
      ],
    );

void main() {
  test('add-on ikut tersimpan saat draft dibuat', () {
    final c = _keranjangDenganAddOn();
    final di = DraftCartItem(
      productSnapshot: _snapshot(),
      qty: c.qty,
      modifiers: c.modifiers,
    );

    expect(di.modifiers, hasLength(2));
    // Yang menentukan adalah HARGANYA, bukan jumlah barisnya.
    expect(
      di.modifiers.fold<double>(0, (s, m) => s + m.price),
      10000,
      reason: 'add-on tersimpan tapi harganya nol — draft tetap ditagih kurang',
    );
  });

  test('add-on selamat melewati JSON — tersimpan DAN terbaca kembali', () {
    // Draft disimpan ke penyimpanan lokal sebagai JSON. Perjalanan bolak-balik
    // itulah tempat field yang terlupakan benar-benar hilang.
    final asli = DraftCartItem(
      productSnapshot: _snapshot(),
      qty: 1,
      modifiers: _keranjangDenganAddOn().modifiers,
    );

    final pulih = DraftCartItem.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(asli.toJson())) as Map),
    );

    expect(pulih.modifiers, hasLength(2));
    expect(pulih.modifiers.map((m) => m.name), containsAll(['Boba', 'Extra Shot']));
    expect(pulih.modifiers.fold<double>(0, (s, m) => s + m.price), 10000);
    // Nama grup ikut, karena tiket dapur mencetaknya sebagai judul.
    expect(pulih.modifiers.first.groupName, 'Topping');
  });

  test('harga baris kembali UTUH sesudah dipulihkan', () {
    // Inti seluruh perbaikan ini. Kopi Rp20.000 + Boba Rp5.000 + Extra Shot
    // Rp5.000 = Rp30.000. Sebelum perbaikan, yang kembali Rp20.000 — selisih
    // Rp10.000 per baris, setiap kali.
    final sebelum = _keranjangDenganAddOn();

    final di = DraftCartItem(
      productSnapshot: _snapshot(),
      qty: sebelum.qty,
      modifiers: sebelum.modifiers,
    );
    final sesudah = CartItem(di.product, di.qty, modifiers: di.modifiers);

    expect(
      sesudah.subtotal,
      sebelum.subtotal,
      reason: 'baris menyusut ${sebelum.subtotal - sesudah.subtotal} setelah '
          'draft dipulihkan — pelanggan ditagih kurang sebanyak itu',
    );
    expect(sesudah.subtotal, 30000);
  });

  test('draft LAMA tanpa kunci modifiers tetap bisa dibuka', () {
    // Draft yang sudah tersimpan di perangkat kasir dibuat sebelum perbaikan
    // ini. Membacanya sebagai galat akan membuang pesanan yang sedang menunggu
    // di meja — kerusakan yang lebih buruk daripada bug yang sedang ditutup.
    final lama = {
      'product': _snapshot(),
      'qty': 2,
      'variant_name': '',
      'variant_price': 0,
      'note': '',
    };

    final pulih = DraftCartItem.fromJson(Map<String, dynamic>.from(lama));
    expect(pulih.qty, 2);
    expect(pulih.modifiers, isEmpty);
  });
}
