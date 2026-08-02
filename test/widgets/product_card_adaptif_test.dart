import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nara_pos_mobile/core/auth_storage.dart';
import 'package:nara_pos_mobile/core/shared_prefs.dart';
import 'package:nara_pos_mobile/features/kasir/ui/widgets/product_card.dart';
import 'package:nara_pos_mobile/features/products/domain/product.dart';

// Kartu produk di layar Kasir.
//
// # DUA HAL YANG DILAPORKAN
//
//   1. Hurufnya terlalu kecil, nyaris tak terbaca — justru di perangkat besar.
//      Sebabnya `.sp` milik paket sizer menghitung dari TINGGI layar; tablet
//      yang dipangku melintang punya tinggi kecil, jadi kartu terlebar malah
//      mendapat huruf terkecil.
//
//   2. Semua kartu dipaksa setinggi sama oleh childAspectRatio. Nama panjang
//      dipangkas jadi satu baris + elipsis (dua produk yang berbeda hanya di
//      kata terakhir tampil identik), sementara kartu bernama pendek punya
//      lubang kosong antara harga dan tombol.
//
// # YANG DIJAGA
//
// Bukan angka piksel tertentu — itu boleh berubah saat desainnya disetel.
// Yang dijaga adalah HUBUNGANNYA:
//
//   - kartu lebih lebar  → huruf lebih besar (tak pernah lebih kecil)
//   - nama lebih panjang → kartu lebih tinggi (tak pernah sama)
//   - nama pendek        → tak ada ruang tersisa yang menganggur
//   - lebar berapa pun   → tidak meluber

const lebarKartuUji = <double>[110, 130, 150, 180, 220, 260, 320];

Product produk(String nama, {double harga = 10000}) =>
    Product(name: nama, price: harga, categoryName: 'MINUMAN');

const namaPendek = 'Kopi';
const namaPanjang =
    'Kopi Susu Gula Aren Spesial Racikan Barista Ukuran Jumbo Dingin';

/// Kartu ini membaca outlet aktif, yang bersandar pada penyimpanan sesi.
/// authStorageProvider sengaja melempar bila tak ditimpa — ditimpa di sini
/// dengan SharedPreferences tiruan supaya tesnya tak menyentuh kanal platform.
late AuthStorage _penyimpanan;
late SharedPreferences _prefs;

Future<void> siapkanPenyimpanan() async {
  SharedPreferences.setMockInitialValues({});
  _prefs = await SharedPreferences.getInstance();
  _penyimpanan = AuthStorage(_prefs);
}

Widget bungkus(Widget anak) => ProviderScope(
      overrides: [
        authStorageProvider.overrideWithValue(_penyimpanan),
        sharedPreferencesProvider.overrideWithValue(_prefs),
      ],
      child: MaterialApp(home: Scaffold(body: anak)),
    );

Future<double> tinggiKartu(
  WidgetTester tester, {
  required String nama,
  required double lebarKartu,
}) async {
  await tester.pumpWidget(
    bungkus(
      SingleChildScrollView(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: lebarKartu,
            child: ProductCard(product: produk(nama)),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.getSize(find.byType(ProductCard)).height;
}

/// Ukuran huruf yang BENAR-BENAR dipakai menggambar sebuah teks.
double ukuranHuruf(WidgetTester tester, String teks) {
  final w = tester.widget<Text>(find.text(teks));
  return w.style!.fontSize!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(siapkanPenyimpanan);

  group('huruf ikut lebar kartu', () {
    testWidgets('makin lebar kartunya, makin besar hurufnya', (tester) async {
      // Inilah kebalikan dari perilaku lama: dulu makin besar perangkatnya,
      // makin kecil hurufnya.
      final ukuran = <double, double>{};
      for (final lebar in lebarKartuUji) {
        await tinggiKartu(tester, nama: namaPendek, lebarKartu: lebar);
        ukuran[lebar] = ukuranHuruf(tester, namaPendek);
      }

      final urut = ukuran.keys.toList()..sort();
      for (var i = 1; i < urut.length; i++) {
        expect(
          ukuran[urut[i]]!,
          greaterThanOrEqualTo(ukuran[urut[i - 1]]!),
          reason: 'kartu ${urut[i]} dp berhuruf ${ukuran[urut[i]]} — lebih '
              'kecil daripada kartu ${urut[i - 1]} dp yang lebih sempit',
        );
      }
      expect(ukuran[urut.last]!, greaterThan(ukuran[urut.first]!),
          reason: 'ukuran hurufnya sama saja di semua lebar — tidak adaptif');
    });

    testWidgets('di kartu tersempit pun huruf tetap terbaca', (tester) async {
      // Batas bawah patokan. Perbaikan yang "adaptif" tanpa batas akan
      // mengecilkan huruf sampai tak terbaca di grid 5 kolom — persis keluhan
      // yang hendak diperbaiki.
      await tinggiKartu(tester, nama: namaPendek, lebarKartu: 110);
      expect(ukuranHuruf(tester, namaPendek), greaterThanOrEqualTo(11.0),
          reason: 'nama produk di bawah 11 dp — inilah ukuran yang dikeluhkan');
      expect(find.textContaining('Rp'), findsWidgets);
    });

    testWidgets('lebih besar daripada ukuran lama di kartu ponsel',
        (tester) async {
      // Kartu ~170 dp = ponsel 2 kolom. Ukuran lama di sana ~10-12 dp menurut
      // .sp; sekarang harus lebih besar, sebab keluhannya "terlalu kecil".
      await tinggiKartu(tester, nama: namaPendek, lebarKartu: 170);
      expect(ukuranHuruf(tester, namaPendek), greaterThan(12.0));
    });
  });

  group('tinggi kartu mengikuti isinya', () {
    testWidgets('nama panjang menghasilkan kartu LEBIH TINGGI', (tester) async {
      // Ini yang membuktikan grid-nya tak lagi memaksa tinggi seragam.
      final pendek = await tinggiKartu(
        tester,
        nama: namaPendek,
        lebarKartu: 170,
      );
      final panjang = await tinggiKartu(
        tester,
        nama: namaPanjang,
        lebarKartu: 170,
      );

      expect(panjang, greaterThan(pendek),
          reason: 'kartu bernama panjang setinggi kartu bernama pendek — '
              'berarti namanya dipangkas, atau tingginya masih dipaksa seragam');
    });

    testWidgets('nama panjang tampil sampai 5 baris, tidak dipangkas ke 1',
        (tester) async {
      await tinggiKartu(tester, nama: namaPanjang, lebarKartu: 170);
      final teks = tester.widget<Text>(find.text(namaPanjang));
      expect(teks.maxLines, 5,
          reason: 'nama produk masih dibatasi ${teks.maxLines} baris — dua '
              'produk yang berbeda di kata terakhir akan tampil identik');
    });

    testWidgets('selisih tingginya sepadan dengan jumlah barisnya',
        (tester) async {
      // Penjaga terhadap "perbaikan" yang menambah tinggi sedikit lalu tetap
      // memangkas teksnya. Nama 63 karakter di kartu 170 dp jadi beberapa
      // baris; selisihnya harus terasa, bukan beberapa piksel.
      final pendek = await tinggiKartu(tester, nama: namaPendek, lebarKartu: 170);
      final panjang = await tinggiKartu(tester, nama: namaPanjang, lebarKartu: 170);
      expect(panjang - pendek, greaterThan(20.0),
          reason: 'hanya bertambah ${panjang - pendek} dp — namanya kemungkinan '
              'masih terpangkas');
    });

    testWidgets('kartu bernama pendek tidak menyisakan ruang menganggur',
        (tester) async {
      // Lubang kosong antara harga dan tombol pada kartu bernama pendek.
      //
      // Diperiksa dengan membandingkan tinggi kartu terhadap tinggi gambar
      // (rasio 1:1 dengan lebar kartu). Sisa di bawah gambar adalah nama +
      // kategori + harga + tombol + jarak-jaraknya; bila jauh lebih besar dari
      // itu, ada ruang yang tak dipakai apa pun.
      const lebar = 170.0;
      final tinggi = await tinggiKartu(
        tester,
        nama: namaPendek,
        lebarKartu: lebar,
      );
      final dibawahGambar = tinggi - lebar;

      expect(dibawahGambar, lessThan(130.0),
          reason: 'ada $dibawahGambar dp di bawah gambar untuk nama satu baris '
              '+ kategori + harga + tombol — terlalu longgar, itu lubang kosong');
      expect(dibawahGambar, greaterThan(50.0),
          reason: 'terlalu sempit, isinya pasti terpotong');
    });
  });

  group('tidak meluber di lebar mana pun', () {
    for (final lebar in lebarKartuUji) {
      testWidgets('${lebar.toInt()} dp — nama pendek', (tester) async {
        await tinggiKartu(tester, nama: namaPendek, lebarKartu: lebar);
        expect(tester.takeException(), isNull);
      });

      testWidgets('${lebar.toInt()} dp — nama sangat panjang', (tester) async {
        await tinggiKartu(tester, nama: namaPanjang, lebarKartu: lebar);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('nama tanpa spasi sepanjang 80 karakter', (tester) async {
      // Nama produk diketik Pemilik dan tak berbatas. Satu kata panjang tak
      // bisa dipotong per kata — ia harus tetap tak merusak kartunya.
      await tinggiKartu(tester, nama: 'A' * 80, lebarKartu: 130);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('harga besar tetap utuh, tidak jadi elipsis', (tester) async {
    // Rp1.500.000 lebih panjang daripada Rp10.000. Harga yang terpotong jadi
    // "Rp1.500…" di layar kasir adalah kesalahan yang langsung berujung uang.
    await tester.pumpWidget(
      bungkus(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 130,
            child: ProductCard(product: produk('Kopi', harga: 1500000)),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('1.500.000'), findsOneWidget);
  });
}
