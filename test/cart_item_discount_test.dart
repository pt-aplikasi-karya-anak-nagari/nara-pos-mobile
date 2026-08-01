import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/kasir/domain/cart_item.dart';
import 'package:nara_pos_mobile/features/products/domain/product.dart';

// Aritmetika satu baris keranjang. Angka yang keluar dari sini masuk ke
// subtotal, ke basis pajak, dan ke laporan diskon — jadi salah di sini salah
// di tiga tempat sekaligus, dan ketiganya uang.
//
// Yang paling mudah rusak adalah URUTAN PRIORITAS diskonnya. Ada tiga sumber
// yang bisa menyala bersamaan:
//
//   1. diskon manual kasir   — hak veto, mengalahkan semuanya
//   2. diskon varian         — hanya untuk pilihan varian eksplisit
//   3. diskon produk         — hanya untuk pilihan "Regular"
//
// Ketiganya bertipe sama (String tipe + double nilai), jadi menukar urutan
// pemeriksaannya adalah kode yang sah sempurna. Yang berubah hanya angka yang
// dibayar pelanggan.

Product _produk({
  double harga = 10000,
  String tipeDiskon = 'none',
  double nilaiDiskon = 0,
  bool kenaPajak = true,
}) => Product(
  remoteId: 'P1',
  name: 'Kopi',
  price: harga,
  discountType: tipeDiskon,
  discountValue: nilaiDiskon,
  discountName: 'Promo Produk',
  isTaxable: kenaPajak,
);

// remoteId WAJIB diisi. CartItem.from mengambil variantId dari
// variant?.remoteId — varian tanpa remoteId menghasilkan variantId null, dan
// baris itu diam-diam diperlakukan sebagai "Regular". Tes yang lupa mengisinya
// akan menguji cabang yang sama sekali berbeda dari yang ia kira.
ProductVariant _varian({
  double harga = 15000,
  String tipeDiskon = 'none',
  double nilaiDiskon = 0,
  String? remoteId = 'V1',
}) => ProductVariant(
  remoteId: remoteId,
  productId: 'P1',
  name: 'Large',
  price: harga,
  discountType: tipeDiskon,
  discountValue: nilaiDiskon,
  discountName: 'Promo Varian',
);

void main() {
  group('prioritas diskon', () {
    test('diskon manual mengalahkan diskon produk', () {
      final item = CartItem(
        _produk(harga: 10000, tipeDiskon: 'percent', nilaiDiskon: 50),
        1,
        manualDiscountType: 'fixed',
        manualDiscountValue: 1000,
      );

      // Produk diskon 50% (→ 5.000), manual potong 1.000 (→ 9.000).
      // Manual menang, jadi 9.000 — BUKAN 5.000, dan bukan 4.000 (bertumpuk).
      expect(item.effectivePrice, 9000);
      expect(item.lineDiscount, 1000);
      expect(item.effectiveDiscountType, 'fixed');
      expect(item.effectiveDiscountValue, 1000);
    });

    test('diskon manual mengalahkan diskon varian', () {
      final item = CartItem.from(
        _produk(),
        1,
        _varian(harga: 20000, tipeDiskon: 'percent', nilaiDiskon: 50),
      ).copyWith(manualDiscountType: 'percent', manualDiscountValue: 10);

      // Varian diskon 50% (→ 10.000), manual 10% (→ 18.000). Manual menang.
      expect(item.effectivePrice, 18000);
      expect(item.effectiveDiscountType, 'percent');
      expect(item.effectiveDiscountValue, 10);
    });

    test('diskon varian dipakai untuk pilihan varian eksplisit', () {
      final item = CartItem.from(
        _produk(tipeDiskon: 'percent', nilaiDiskon: 90),
        1,
        _varian(harga: 20000, tipeDiskon: 'percent', nilaiDiskon: 25),
      );

      // Diskon PRODUK 90% sengaja dipasang besar sekali di sini. Kalau ia yang
      // terpakai, hasilnya 2.000 — jauh meleset dari 15.000. Angkanya dibuat
      // timpang justru supaya kekeliruan cabang tak bisa lolos sebagai
      // pembulatan.
      expect(item.effectivePrice, 15000);
      expect(item.effectiveDiscountType, 'percent');
      expect(item.effectiveDiscountValue, 25);
    });

    test('diskon produk dipakai untuk pilihan Regular', () {
      final item = CartItem(
        _produk(harga: 10000, tipeDiskon: 'fixed', nilaiDiskon: 2500),
        1,
      );

      expect(item.effectivePrice, 7500);
      expect(item.effectiveDiscountType, 'fixed');
      expect(item.effectiveDiscountValue, 2500);
    });

    test('diskon PRODUK tidak ikut terbawa ke baris varian', () {
      // Sisi yang mudah bocor: varian tanpa diskon sendiri harus membayar
      // harga varian PENUH, bukan harga varian dikurangi diskon produk.
      final item = CartItem.from(
        _produk(harga: 10000, tipeDiskon: 'percent', nilaiDiskon: 50),
        1,
        _varian(harga: 20000),
      );

      expect(item.effectivePrice, 20000);
      expect(item.lineDiscount, 0);
      expect(item.effectiveDiscountType, 'none');
    });
  });

  group('varian tanpa remoteId — jebakan diam', () {
    test('varian tanpa remoteId diperlakukan sebagai Regular', () {
      // Bukan tes atas perilaku yang diinginkan, melainkan atas perilaku yang
      // BERLAKU — dan ia jebakan. CartItem.from membaca variant?.remoteId;
      // varian yang belum tersinkron ke server tak punya remoteId, jadi
      // barisnya kehilangan identitas variannya dan jatuh ke cabang produk.
      //
      // Dikunci di sini supaya kalau perilakunya berubah kelak, perubahan itu
      // TERLIHAT — bukan diam-diam menggeser harga di layar kasir.
      final item = CartItem.from(
        _produk(harga: 10000, tipeDiskon: 'percent', nilaiDiskon: 50),
        1,
        _varian(harga: 20000, tipeDiskon: 'fixed', nilaiDiskon: 5000, remoteId: null),
      );

      expect(item.variantId, isNull);
      // basePrice jatuh ke harga PRODUK (10.000), bukan harga varian (20.000),
      // lalu diskon produk 50% berlaku → 5.000.
      expect(item.effectivePrice, 5000);
      expect(item.effectiveDiscountValue, 50);

      // Padahal namanya tetap terbawa — itulah yang membuatnya sulit terlihat:
      // di layar tertulis "Kopi (Large)" dengan harga Regular.
      expect(item.displayName, 'Kopi (Large)');
    });
  });

  group('add-on (modifier)', () {
    test('harga add-on menambah harga per unit', () {
      final item = CartItem(
        _produk(harga: 10000),
        2,
        modifiers: const [
          CartModifier(
            groupId: 'g1',
            groupName: 'Topping',
            optionId: 'o1',
            name: 'Boba',
            price: 3000,
          ),
          CartModifier(
            groupId: 'g1',
            groupName: 'Topping',
            optionId: 'o2',
            name: 'Keju',
            price: 2000,
          ),
        ],
      );

      expect(item.modifiersTotal, 5000);
      expect(item.effectivePrice, 15000);
      expect(item.subtotal, 30000);
    });

    test('add-on TIDAK ikut dihitung sebagai diskon', () {
      // lineDiscount masuk ke laporan diskon. Kalau add-on ikut terhitung di
      // sana, laporan diskon jadi bercampur dengan pendapatan topping — dua
      // hal yang sama sekali berbeda maknanya bagi pemilik.
      final item = CartItem(
        _produk(harga: 10000, tipeDiskon: 'fixed', nilaiDiskon: 2000),
        3,
        modifiers: const [
          CartModifier(
            groupId: 'g1',
            groupName: 'Topping',
            optionId: 'o1',
            name: 'Boba',
            price: 3000,
          ),
        ],
      );

      expect(item.lineDiscount, 6000); // 2.000 × 3 — add-on tak menyentuhnya
      expect(item.effectivePrice, 11000); // (10.000 − 2.000) + 3.000
      expect(item.subtotal, 33000);
    });

    test('diskon berlaku pada base saja, bukan pada base+add-on', () {
      // Urutan operasi. Kalau diskon persen dikenakan setelah add-on
      // ditambahkan, pelanggan mendapat potongan atas toppingnya juga.
      final item = CartItem(
        _produk(harga: 10000, tipeDiskon: 'percent', nilaiDiskon: 50),
        1,
        modifiers: const [
          CartModifier(
            groupId: 'g1',
            groupName: 'Topping',
            optionId: 'o1',
            name: 'Boba',
            price: 4000,
          ),
        ],
      );

      expect(item.effectivePrice, 9000); // 5.000 + 4.000
      expect(item.effectivePrice, isNot(7000)); // bukan (10.000+4.000) × 50%
    });

    test('modifierKey stabil apa pun urutan pilihannya', () {
      CartItem buat(List<String> ids) => CartItem(
        _produk(),
        1,
        modifiers: ids
            .map(
              (id) => CartModifier(
                groupId: 'g1',
                groupName: 'T',
                optionId: id,
                name: id,
                price: 0,
              ),
            )
            .toList(),
      );

      // Dipakai untuk memutuskan dua baris keranjang sama atau beda. Kalau
      // urutannya ikut menentukan, memilih topping yang sama dengan urutan
      // berbeda memecah jadi dua baris.
      expect(buat(['b', 'a']).modifierKey, buat(['a', 'b']).modifierKey);
      expect(buat([]).modifierKey, '');
    });
  });

  group('penjaga nilai negatif', () {
    test('diskon tetap lebih besar dari harga tidak menghasilkan harga minus', () {
      final item = CartItem(
        _produk(harga: 5000),
        2,
        manualDiscountType: 'fixed',
        manualDiscountValue: 9000,
      );

      // Harga minus akan mengurangi total nota — kasir bisa "menjual" dengan
      // nilai negatif dan laci kas jadi kurang tanpa jejak.
      expect(item.effectivePrice, 0);
      expect(item.subtotal, 0);
      expect(item.lineDiscount, 10000); // potongan tercatat penuh: 5.000 × 2
    });

    test('diskon persen di atas 100 juga dijepit ke nol', () {
      final item = CartItem(
        _produk(harga: 5000),
        1,
        manualDiscountType: 'percent',
        manualDiscountValue: 150,
      );

      expect(item.effectivePrice, 0);
    });
  });

  group('basePrice & pajak', () {
    test('basePrice ikut varian bila variantId ada, produk bila tidak', () {
      expect(CartItem.from(_produk(harga: 10000), 1, _varian(harga: 20000)).basePrice, 20000);
      expect(CartItem(_produk(harga: 10000), 1).basePrice, 10000);
    });

    test('status kena pajak diwarisi dari produk, varian tak mengubahnya', () {
      // Basis pajak kasir (taxableSubtotal) disaring dengan flag ini. Kalau
      // varian bisa mengubahnya, preview kasir menyimpang dari server.
      final bebas = CartItem.from(_produk(kenaPajak: false), 1, _varian());
      final kena = CartItem.from(_produk(kenaPajak: true), 1, _varian());

      expect(bebas.isTaxable, isFalse);
      expect(kena.isTaxable, isTrue);
    });
  });

  group('hasAutoDiscount — penjaga tombol "Beri Diskon"', () {
    test('baris Regular mengikuti diskon produk', () {
      expect(CartItem(_produk(tipeDiskon: 'percent', nilaiDiskon: 10), 1).hasAutoDiscount, isTrue);
      expect(CartItem(_produk(), 1).hasAutoDiscount, isFalse);
    });

    test('baris varian mengikuti diskon VARIAN, bukan diskon produk', () {
      // Halus tapi berakibat: varian tanpa diskon pada produk yang berdiskon
      // harus tetap boleh diberi diskon manual oleh kasir, karena diskon
      // produk memang tidak berlaku untuk baris varian.
      final varianPolos = CartItem.from(
        _produk(tipeDiskon: 'percent', nilaiDiskon: 20),
        1,
        _varian(),
      );
      expect(varianPolos.hasAutoDiscount, isFalse);

      final varianBerdiskon = CartItem.from(
        _produk(),
        1,
        _varian(tipeDiskon: 'percent', nilaiDiskon: 20),
      );
      expect(varianBerdiskon.hasAutoDiscount, isTrue);
    });
  });
}
