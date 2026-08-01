import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nara_pos_mobile/core/outlet_scope.dart';
import 'package:nara_pos_mobile/features/kasir/domain/cart_item.dart';
import 'package:nara_pos_mobile/features/kasir/providers.dart';
import 'package:nara_pos_mobile/features/outlet/domain/outlet.dart';
import 'package:nara_pos_mobile/features/products/domain/product.dart';
import 'package:nara_pos_mobile/features/user/data/auth_service.dart';

// Pipa dari keranjang ke angka yang dibayar:
//
//   cartProvider
//     ├→ subtotalProvider          seluruh baris
//     ├→ taxableSubtotalProvider   HANYA baris yang kena pajak
//     ├→ originalSubtotalProvider  sebelum diskon item
//     └→ discountTotalProvider     jumlah potongan
//              ↓
//        _taxBreakdownProvider  →  Outlet.computeTaxBreakdown
//              ↓
//   serviceChargeProvider / taxProvider / totalProvider
//
// test/outlet_tax_breakdown_test.dart sudah mengunci aritmetikanya. Yang
// dijaga DI SINI adalah PENYAMBUNGANNYA — apakah angka yang benar sampai ke
// argumen yang benar.
//
// Bahayanya khas: subtotalProvider, taxableSubtotalProvider, dan
// originalSubtotalProvider semuanya Provider<double>. Menukar salah satunya
// dengan yang lain adalah kode yang lolos type-check tanpa satu keluhan pun —
// dan akibatnya item yang BEBAS PAJAK ikut dipajaki di setiap struk.
//
// Tanpa widget, tanpa plugin, tanpa jaringan: cukup ProviderContainer dengan
// dua override.

/// authProvider harus ditimpa karena AuthNotifier.build() membaca
/// authStorageProvider (SharedPreferences), yang tak ada di lingkungan tes.
/// Meng-extend `AuthNotifier` — bukan `Notifier<AuthState>` — karena
/// `NotifierProvider.overrideWith` meminta tipe notifier yang sama persis.
/// Aman: _authStorage & _authApi baru di-assign di dalam build(), dan build()
/// itulah yang kita timpa.
class _FakeAuth extends AuthNotifier {
  @override
  AuthState build() => const AuthState();
}

ProviderContainer _wadah(Outlet? outlet) {
  final c = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      activeOutletProvider.overrideWithValue(outlet),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Outlet _outlet({
  bool inclusive = false,
  double taxPercent = 11,
  double servicePercent = 0,
  bool taxEnabled = true,
}) => Outlet(
  name: 'Outlet Uji',
  taxEnabled: taxEnabled,
  taxPercent: taxPercent,
  serviceChargePercent: servicePercent,
  taxInclusive: inclusive,
);

Product _produk({
  required String id,
  required double harga,
  bool kenaPajak = true,
  String tipeDiskon = 'none',
  double nilaiDiskon = 0,
}) => Product(
  remoteId: id,
  name: 'Produk $id',
  price: harga,
  isTaxable: kenaPajak,
  discountType: tipeDiskon,
  discountValue: nilaiDiskon,
);

void main() {
  group('basis pajak memisahkan item bebas pajak', () {
    test('subtotal memuat semua, basis pajak hanya yang kena pajak', () {
      final c = _wadah(_outlet());
      c.read(cartProvider.notifier).replaceAll([
        CartItem(_produk(id: 'P1', harga: 25000), 2), // 50.000 kena pajak
        CartItem(_produk(id: 'P2', harga: 5000, kenaPajak: false), 1), // bebas
      ]);

      expect(c.read(subtotalProvider), 55000);
      expect(c.read(taxableSubtotalProvider), 50000);
    });

    test('PPN dihitung dari 50.000, BUKAN dari 55.000', () {
      final c = _wadah(_outlet(taxPercent: 11));
      c.read(cartProvider.notifier).replaceAll([
        CartItem(_produk(id: 'P1', harga: 25000), 2),
        CartItem(_produk(id: 'P2', harga: 5000, kenaPajak: false), 1),
      ]);

      // Inti sambungannya. 11% × 50.000 = 5.500.
      expect(c.read(taxProvider), 5500);
      // Kalau basisnya keliru jadi seluruh nota: 11% × 55.000 = 6.050.
      expect(c.read(taxProvider), isNot(6050));
      expect(c.read(totalProvider), 60500); // 55.000 + 5.500
    });

    test('service charge dihitung dari SELURUH nota, bukan dari basis pajak', () {
      // Sengaja tidak simetris dengan pajak, dan memang begitu aturannya:
      // service charge dikenakan atas seluruh layanan, sedangkan PPN hanya
      // atas barang yang kena pajak. Menyeragamkan keduanya terasa rapi dan
      // salah.
      final c = _wadah(_outlet(taxPercent: 0, servicePercent: 10));
      c.read(cartProvider.notifier).replaceAll([
        CartItem(_produk(id: 'P1', harga: 50000), 1),
        CartItem(_produk(id: 'P2', harga: 50000, kenaPajak: false), 1),
      ]);

      // 10% × 100.000 = 10.000 — bukan 10% × 50.000 = 5.000.
      expect(c.read(serviceChargeProvider), 10000);
      expect(c.read(serviceChargeProvider), isNot(5000));
    });

    test('seluruh keranjang bebas pajak → PPN nol, tapi nota tetap ada', () {
      final c = _wadah(_outlet(taxPercent: 11));
      c.read(cartProvider.notifier).replaceAll([
        CartItem(_produk(id: 'P1', harga: 30000, kenaPajak: false), 1),
      ]);

      expect(c.read(subtotalProvider), 30000);
      expect(c.read(taxableSubtotalProvider), 0);
      expect(c.read(taxProvider), 0);
      expect(c.read(totalProvider), 30000);
    });
  });

  group('mode inclusive sampai ke ujung pipa', () {
    test('total TIDAK menambah PPN di atas harga', () {
      final c = _wadah(_outlet(inclusive: true, taxPercent: 11));
      c.read(cartProvider.notifier).replaceAll([
        CartItem(_produk(id: 'P1', harga: 111000), 1),
      ]);

      // Harga sudah termasuk PPN. Yang dibayar tetap 111.000.
      expect(c.read(totalProvider), 111000);
      expect(c.read(taxProvider), 11000); // 111.000 − 111.000/1,11
    });

    test('angka yang sama, dua mode outlet, total berbeda', () {
      List<CartItem> isi() => [CartItem(_produk(id: 'P1', harga: 100000), 1)];

      final inc = _wadah(_outlet(inclusive: true, taxPercent: 10));
      inc.read(cartProvider.notifier).replaceAll(isi());

      final exc = _wadah(_outlet(taxPercent: 10));
      exc.read(cartProvider.notifier).replaceAll(isi());

      expect(inc.read(totalProvider), 100000);
      expect(exc.read(totalProvider), 110000);
    });

    test('inclusive + item bebas pajak + service charge', () {
      // Kasus paling rumit yang benar-benar terjadi di gerai: sebagian menu
      // kena pajak, sebagian tidak, harga sudah termasuk PPN, dan ada service
      // charge. Angka-angka ini diturunkan tangan lebih dulu:
      //   basis pajak  = 50.000 → net 50.000/1,11 = 45.045,05 → PPN 4.954,95
      //   net nota     = 55.000 − 4.954,95 = 50.045,05
      //   SC 5% × net  = 2.502,25
      //   total        = 50.045,05 + 4.954,95 + 2.502,25 = 57.502,25
      final c = _wadah(
        _outlet(inclusive: true, taxPercent: 11, servicePercent: 5),
      );
      c.read(cartProvider.notifier).replaceAll([
        CartItem(_produk(id: 'P1', harga: 25000), 2),
        CartItem(_produk(id: 'P2', harga: 5000, kenaPajak: false), 1),
      ]);

      expect(c.read(taxProvider), 4955);
      expect(c.read(serviceChargeProvider), 2502);
      expect(c.read(totalProvider), 57502);
    });
  });

  group('diskon per baris', () {
    test('basis pajak memakai harga SESUDAH diskon', () {
      final c = _wadah(_outlet(taxPercent: 10));
      c.read(cartProvider.notifier).replaceAll([
        CartItem(
          _produk(id: 'P1', harga: 100000, tipeDiskon: 'percent', nilaiDiskon: 20),
          1,
        ),
      ]);

      // Pelanggan membayar 80.000, jadi PPN-nya 8.000 — bukan 10.000.
      // Memajaki harga sebelum diskon berarti memungut pajak atas uang yang
      // tak pernah diterima.
      expect(c.read(subtotalProvider), 80000);
      expect(c.read(taxableSubtotalProvider), 80000);
      expect(c.read(taxProvider), 8000);
    });

    test('originalSubtotal & discountTotal dilaporkan terpisah', () {
      final c = _wadah(_outlet(taxEnabled: false));
      c.read(cartProvider.notifier).replaceAll([
        CartItem(
          _produk(id: 'P1', harga: 100000, tipeDiskon: 'fixed', nilaiDiskon: 25000),
          2,
        ),
      ]);

      // Dipakai baris "Subtotal − Diskon" di lembar pembayaran. Keduanya harus
      // konsisten: original − diskon = subtotal.
      expect(c.read(originalSubtotalProvider), 200000);
      expect(c.read(discountTotalProvider), 50000);
      expect(c.read(subtotalProvider), 150000);
    });
  });

  group('keadaan tepi', () {
    test('tanpa outlet aktif, nota lewat tanpa pajak', () {
      // Terjadi sebelum outlet termuat, atau saat pemilik memilih "semua
      // outlet". Yang penting: JANGAN mengarang angka pajak dari outlet
      // sebelumnya.
      final c = _wadah(null);
      c.read(cartProvider.notifier).replaceAll([
        CartItem(_produk(id: 'P1', harga: 50000), 1),
      ]);

      expect(c.read(taxProvider), 0);
      expect(c.read(serviceChargeProvider), 0);
      expect(c.read(totalProvider), 50000);
    });

    test('keranjang kosong → semuanya nol, bukan NaN', () {
      final c = _wadah(_outlet(inclusive: true, taxPercent: 11, servicePercent: 5));

      // Pembagian pada cabang inclusive membuka peluang NaN kalau ada yang
      // mengubah urutan operasinya. Nol harus tetap nol.
      expect(c.read(subtotalProvider), 0);
      expect(c.read(taxProvider), 0);
      expect(c.read(serviceChargeProvider), 0);
      expect(c.read(totalProvider), 0);
      expect(c.read(totalItemsProvider), 0);
    });

    test('totalItems menghitung QTY, bukan jumlah baris', () {
      final c = _wadah(_outlet());
      c.read(cartProvider.notifier).replaceAll([
        CartItem(_produk(id: 'P1', harga: 1000), 3),
        CartItem(_produk(id: 'P2', harga: 1000), 4),
      ]);

      expect(c.read(totalItemsProvider), 7);
      expect(c.read(totalItemsProvider), isNot(2));
    });
  });
}
