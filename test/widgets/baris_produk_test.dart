import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nara_pos_mobile/core/auth_storage.dart';
import 'package:nara_pos_mobile/core/shared_prefs.dart';
import 'package:nara_pos_mobile/features/kasir/ui/widgets/baris_produk.dart';
import 'package:nara_pos_mobile/features/kasir/ui/widgets/product_card.dart';
import 'package:nara_pos_mobile/features/products/domain/product.dart';

// Susunan kartu produk di layar Kasir.
//
// # TIGA CARA, DUA SUDAH DITOLAK
//
//   childAspectRatio  Semua petak setinggi SAMA di seluruh daftar. Nama panjang
//                     terpangkas jadi satu baris; kartu bernama pendek
//                     menyisakan lubang sebesar selisihnya terhadap kartu
//                     terpanjang di SELURUH menu.
//
//   masonry           Tiap kartu setinggi isinya sendiri, tapi penempatannya
//                     mengejar kolom TERPENDEK. Urutan bacanya melompat, tepi
//                     kartu tak sejajar, dan di ujung daftar muncul petak
//                     menganggur. Inilah yang dilaporkan: "urutannya jadi aneh,
//                     dan ada yang kosong".
//
//   baris intrinsik   Yang dipakai sekarang. Tinggi ditentukan per BARIS.
//
// # YANG DIJAGA
//
//   - urutan kiri-ke-kanan, persis urutan datanya
//   - semua kartu dalam satu baris BERTINGGI SAMA
//   - tinggi baris ditentukan kartu tertinggi DI BARIS ITU, bukan di seluruh
//     daftar — inilah beda pentingnya dari childAspectRatio
//   - baris terakhir yang tak genap tidak membuat kartunya melar

late AuthStorage _penyimpanan;
late SharedPreferences _prefs;

Future<void> siapkan() async {
  SharedPreferences.setMockInitialValues({});
  _prefs = await SharedPreferences.getInstance();
  _penyimpanan = AuthStorage(_prefs);
}

Product produk(String nama) =>
    Product(name: nama, price: 10000, categoryName: 'MINUMAN');

const pendek = 'Kopi';
const panjang =
    'Kopi Susu Gula Aren Spesial Racikan Barista Ukuran Jumbo Dingin Sekali';

Future<void> pasangBaris(
  WidgetTester tester, {
  required List<String> nama,
  required int kolom,
  double lebar = 700,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStorageProvider.overrideWithValue(_penyimpanan),
        sharedPreferencesProvider.overrideWithValue(_prefs),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: lebar,
              child: BarisProduk(
                produk: nama.map(produk).toList(),
                kolom: kolom,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

List<Rect> kotakKartu(WidgetTester tester) => tester
    .widgetList<ProductCard>(find.byType(ProductCard))
    .map((w) => tester.getRect(find.byWidget(w)))
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(siapkan);

  group('potongJadiBaris', () {
    test('memotong tepat sebanyak kolomnya', () {
      final semua = List.generate(7, (i) => produk('P$i'));
      final baris = potongJadiBaris(semua, 3);
      expect(baris.map((b) => b.length).toList(), [3, 3, 1]);
    });

    test('urutannya tidak berubah', () {
      // Ini yang dilanggar masonry. Kasir menghafal posisi produk yang sering
      // dijual; urutan yang melompat membuat hafalan itu tak berguna.
      final semua = List.generate(6, (i) => produk('P$i'));
      final rata = potongJadiBaris(semua, 2).expand((b) => b).toList();
      expect(rata.map((p) => p.name).toList(),
          ['P0', 'P1', 'P2', 'P3', 'P4', 'P5']);
    });

    test('daftar kosong menghasilkan nol baris', () {
      expect(potongJadiBaris(<Product>[], 3), isEmpty);
    });

    test('kolom nol tidak menggantung selamanya', () {
      // i += 0 akan berputar tanpa henti dan membekukan aplikasinya.
      expect(potongJadiBaris([produk('P')], 0), isEmpty);
    });

    test('produk lebih sedikit daripada kolom tetap jadi satu baris', () {
      expect(potongJadiBaris([produk('A'), produk('B')], 5).length, 1);
    });
  });

  group('kartu dalam satu baris sejajar', () {
    testWidgets('tinggi & tepi atas-bawahnya sama persis', (tester) async {
      // Isi yang sangat berbeda panjangnya: pendek, panjang, pendek.
      await pasangBaris(
        tester,
        nama: [pendek, panjang, pendek],
        kolom: 3,
      );

      final kotak = kotakKartu(tester);
      expect(kotak.length, 3);
      for (final k in kotak.skip(1)) {
        expect(k.top, moreOrLessEquals(kotak.first.top, epsilon: 0.5),
            reason: 'tepi atas kartu tidak sejajar');
        expect(k.height, moreOrLessEquals(kotak.first.height, epsilon: 0.5),
            reason: 'tinggi kartu berbeda-beda dalam satu baris — inilah '
                'tampilan bergerigi yang dilaporkan');
      }
    });

    testWidgets('urutan kiri ke kanan mengikuti urutan datanya',
        (tester) async {
      await pasangBaris(tester, nama: ['Satu', 'Dua', 'Tiga'], kolom: 3);
      final kiri = ['Satu', 'Dua', 'Tiga']
          .map((n) => tester.getRect(find.text(n)).left)
          .toList();
      expect(kiri[0], lessThan(kiri[1]));
      expect(kiri[1], lessThan(kiri[2]));
    });

    testWidgets('lebar tiap kartu sama', (tester) async {
      await pasangBaris(tester, nama: [pendek, panjang, pendek], kolom: 3);
      final kotak = kotakKartu(tester);
      for (final k in kotak.skip(1)) {
        expect(k.width, moreOrLessEquals(kotak.first.width, epsilon: 0.5));
      }
    });
  });

  group('tombol "+" sejajar', () {
    // Ini yang dilaporkan setelah barisnya sejajar: kartunya memang setinggi
    // sama, tapi ISINYA menumpuk di atas — tiap tombol berhenti tepat di bawah
    // harganya, jadi tingginya berbeda-beda mengikuti berapa baris nama
    // produknya.
    //
    // Rangkaian tes sebelumnya TIDAK menangkap ini: ia mengukur kotak KARTU,
    // dan kartunya memang sudah sejajar. Yang tak diukur siapa pun adalah
    // posisi tombol di dalamnya.

    Rect kotakTombol(WidgetTester tester, int ke) {
      final tombol = find.byType(ElevatedButton);
      return tester.getRect(tombol.at(ke));
    }

    testWidgets('tombol sejajar walau nama produknya beda jumlah baris',
        (tester) async {
      await pasangBaris(
        tester,
        nama: [pendek, panjang, pendek, panjang],
        kolom: 4,
        lebar: 900,
      );

      final atas = List.generate(4, (i) => kotakTombol(tester, i).top);
      for (final t in atas.skip(1)) {
        expect(t, moreOrLessEquals(atas.first, epsilon: 0.5),
            reason: 'tombol "+" tidak sejajar: $atas — kartunya sejajar tapi '
                'isinya menumpuk di atas');
      }
    });

    testWidgets('tombol menempel ke DASAR kartu, bukan menggantung di tengah',
        (tester) async {
      await pasangBaris(
        tester,
        nama: [pendek, panjang, pendek],
        kolom: 3,
        lebar: 700,
      );

      final kartu = kotakKartu(tester);
      for (var i = 0; i < 3; i++) {
        final sisa = kartu[i].bottom - kotakTombol(tester, i).bottom;
        expect(sisa, lessThan(16.0),
            reason: 'ada $sisa dp menganggur di bawah tombol kartu ke-$i — '
                'tombolnya menggantung, bukan menempel ke dasar');
      }
    });

    testWidgets('tombol tetap sejajar di baris tak genap', (tester) async {
      await pasangBaris(tester, nama: [panjang, pendek], kolom: 4, lebar: 900);
      final a = kotakTombol(tester, 0).top;
      final b = kotakTombol(tester, 1).top;
      expect(b, moreOrLessEquals(a, epsilon: 0.5));
    });

    testWidgets('semua tombol berukuran sama', (tester) async {
      // Tombol yang tingginya ikut melar akan tampak berbeda-beda walau
      // tepinya sejajar.
      await pasangBaris(
        tester,
        nama: [pendek, panjang, pendek],
        kolom: 3,
        lebar: 700,
      );
      final ukuran = List.generate(3, (i) => kotakTombol(tester, i).size);
      for (final u in ukuran.skip(1)) {
        expect(u.height, moreOrLessEquals(ukuran.first.height, epsilon: 0.5));
      }
    });
  });

  group('tinggi baris ditentukan baris itu sendiri', () {
    testWidgets('baris berisi nama pendek saja LEBIH RENDAH daripada baris '
        'yang memuat nama panjang', (tester) async {
      // Inilah beda pentingnya dari childAspectRatio: di sana SEMUA baris
      // setinggi baris tertinggi, jadi seluruh menu ikut menanggung satu produk
      // bernama panjang.
      await pasangBaris(tester, nama: [pendek, pendek, pendek], kolom: 3);
      final semuaPendek = kotakKartu(tester).first.height;

      await pasangBaris(tester, nama: [pendek, panjang, pendek], kolom: 3);
      final adaPanjang = kotakKartu(tester).first.height;

      expect(adaPanjang, greaterThan(semuaPendek),
          reason: 'baris yang memuat nama panjang tidak lebih tinggi — '
              'namanya kemungkinan terpangkas');
    });

    testWidgets('nama panjang tetap utuh, tidak dipangkas jadi satu baris',
        (tester) async {
      await pasangBaris(tester, nama: [pendek, panjang, pendek], kolom: 3);
      final teks = tester.widget<Text>(find.text(panjang));
      expect(teks.maxLines, 5);
      expect(tester.takeException(), isNull);
    });
  });

  group('baris terakhir yang tak genap', () {
    testWidgets('kartunya TIDAK melar memenuhi lebar', (tester) async {
      // Tanpa petak kosong pengisi, dua kartu terakhir akan membesar dan tampak
      // berbeda dari kartu di baris-baris atasnya.
      await pasangBaris(tester, nama: [pendek, pendek, pendek], kolom: 3,
          lebar: 700);
      final penuh = kotakKartu(tester).first.width;

      await pasangBaris(tester, nama: [pendek, pendek], kolom: 3, lebar: 700);
      final takGenap = kotakKartu(tester).first.width;

      expect(takGenap, moreOrLessEquals(penuh, epsilon: 0.5),
          reason: 'kartu di baris tak genap berlebar $takGenap, sementara di '
              'baris penuh $penuh — ukurannya jadi tidak seragam');
    });

    testWidgets('satu kartu di baris berkolom 5 pun tetap seukuran',
        (tester) async {
      await pasangBaris(tester, nama: List.filled(5, pendek), kolom: 5,
          lebar: 1000);
      final penuh = kotakKartu(tester).first.width;

      await pasangBaris(tester, nama: [pendek], kolom: 5, lebar: 1000);
      expect(kotakKartu(tester).first.width,
          moreOrLessEquals(penuh, epsilon: 0.5));
    });
  });

  group('tidak meluber', () {
    for (final kolom in [2, 3, 4, 5]) {
      for (final lebar in [320.0, 600.0, 1024.0]) {
        testWidgets('$kolom kolom @ ${lebar.toInt()} dp', (tester) async {
          await pasangBaris(
            tester,
            nama: [panjang, pendek, panjang, pendek, panjang].take(kolom).toList(),
            kolom: kolom,
            lebar: lebar,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
