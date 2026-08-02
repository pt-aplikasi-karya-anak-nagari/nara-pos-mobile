import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/kasir/ui/widgets/modifier_sheet.dart';
import 'package:nara_pos_mobile/features/products/domain/modifier_group.dart';
import 'package:nara_pos_mobile/shared/widgets/sheet_bawah.dart';

// Bottom sheet: tinggi mengikuti isi, dan tak tertimpa sistem.
//
// # DUA HAL YANG DIJAGA, DAN KEDUANYA TAK KELIHATAN DI KODE
//
// TINGGI. Widget scrollable tidak mengecil mengikuti isinya — ListView selalu
// memenuhi tinggi maksimum yang ditawarkan induknya. Pada sheet varian, satu
// grup berisi dua pilihan tetap menghasilkan sheet setinggi 85% layar dengan
// rongga kosong menganga antara pilihan terakhir dan tombol "Tambah". Tak ada
// galat, tak ada peringatan; hanya terlihat kalau dibuka di perangkat.
//
// SISI SISTEM. showModalBottomSheet dengan useSafeArea: false — nilai BAWAAN,
// dan yang dipakai 37 pemanggilan di aplikasi ini — bukan sekadar tak
// melindungi bagian atas. Ia AKTIF membuang padding atas
// (MediaQuery.removePadding(removeTop: true)), sehingga sheet yang tinggi
// menyelinap ke bawah status bar. Bagian bawah tak pernah dijaga Flutter sama
// sekali: gesture bar menimpa baris terakhir kecuali isi sheet mengurusnya
// sendiri, dan hanya sebagian yang melakukannya.

ModifierGroup grup(String id, int jumlahOpsi) => ModifierGroup(
  id: id,
  name: 'Grup $id',
  minSelect: 1,
  maxSelect: 1,
  options: [
    for (var i = 0; i < jumlahOpsi; i++)
      ModifierOption(id: '$id-$i', name: 'Opsi $i', price: 1000),
  ],
);

/// Buka sheet lewat helper dan kembalikan tingginya yang benar-benar tergambar.
Future<double> tinggiSheet(
  WidgetTester tester,
  Widget isi, {
  EdgeInsets padding = EdgeInsets.zero,
  double insetKeyboard = 0,
}) async {
  // Buang pohon dari pengukuran sebelumnya beserta route sheet-nya. Tanpa ini,
  // pengukuran kedua dalam satu tes menemukan DUA WadahSheetBawah dan getSize
  // gagal dengan "Too many elements".
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();

  late BuildContext ctx;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: const Size(400, 800),
        padding: padding,
        viewInsets: EdgeInsets.only(bottom: insetKeyboard),
      ),
      child: MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    ),
  );
  tampilkanSheetBawah<void>(
    context: ctx,
    backgroundColor: Colors.transparent,
    builder: (_) => isi,
  );
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(WadahSheetBawah)).height;
}

void main() {
  testWidgets('sheet dengan isi sedikit TIDAK setinggi layar', (tester) async {
    // Satu grup, dua pilihan — persis bentuk sheet varian "Teh Telur".
    final t = await tinggiSheet(
      tester,
      ModifierSheet(
        productName: 'Teh Telur',
        basePrice: 12000,
        groups: [grup('ukuran', 2)],
      ),
    );

    expect(
      t,
      lessThan(500),
      reason:
          'sheet setinggi ${t.toStringAsFixed(0)} dari layar 800 untuk isi '
          'dua baris — ListView-nya memenuhi seluruh ruang yang ditawarkan, '
          'dan rongga kosongnya jatuh di antara pilihan terakhir dan tombol',
    );
  });

  testWidgets('tingginya IKUT bertambah saat isinya bertambah', (tester) async {
    // Yang membedakan "pas dengan isi" dari "kebetulan pendek": tingginya
    // harus bergerak mengikuti isinya, bukan tetap di satu angka.
    final kecil = await tinggiSheet(
      tester,
      ModifierSheet(productName: 'A', basePrice: 1000, groups: [grup('g1', 2)]),
    );
    final sedang = await tinggiSheet(
      tester,
      ModifierSheet(
        productName: 'A',
        basePrice: 1000,
        groups: [grup('g1', 2), grup('g2', 3)],
      ),
    );
    expect(
      sedang,
      greaterThan(kecil),
      reason:
          'isi bertambah tapi tingginya tetap $kecil — berarti tingginya '
          'dipatok sesuatu, bukan mengikuti isi',
    );
  });

  testWidgets('isi yang KEBANYAKAN tetap dibatasi layar, tidak meluber', (
    tester,
  ) async {
    // Sisi yang membuat perbaikan ini tidak berubah jadi bug baru. shrinkWrap
    // tanpa pembatas akan membuat daftar panjang tumbuh melewati layar dan
    // meluber (RenderFlex overflow), bukan digulir.
    final t = await tinggiSheet(
      tester,
      ModifierSheet(
        productName: 'Banyak',
        basePrice: 1000,
        groups: [for (var i = 0; i < 12; i++) grup('g$i', 5)],
      ),
    );
    expect(t, lessThanOrEqualTo(800));
    expect(tester.takeException(), isNull, reason: 'isi sheet meluber');
  });

  group('sisi sistem', () {
    testWidgets('gesture bar bawah tidak menimpa isi sheet', (tester) async {
      // Perangkat dengan navigasi gestur: padding bawah 34 (home indicator).
      final tanpa = await tinggiSheet(
        tester,
        ModifierSheet(
          productName: 'A',
          basePrice: 1000,
          groups: [grup('g', 2)],
        ),
      );
      final dengan = await tinggiSheet(
        tester,
        ModifierSheet(
          productName: 'A',
          basePrice: 1000,
          groups: [grup('g', 2)],
        ),
        padding: const EdgeInsets.only(bottom: 34),
      );
      expect(
        dengan - tanpa,
        closeTo(34, 0.5),
        reason:
            'tinggi sheet tak bertambah saat ada gesture bar — baris terakhir '
            'dan tombolnya berada di bawah bilah sistem',
      );
    });

    testWidgets('keyboard mengangkat sheet, bukan menutupinya', (tester) async {
      final tanpa = await tinggiSheet(
        tester,
        ModifierSheet(
          productName: 'A',
          basePrice: 1000,
          groups: [grup('g', 2)],
        ),
      );
      final dengan = await tinggiSheet(
        tester,
        ModifierSheet(
          productName: 'A',
          basePrice: 1000,
          groups: [grup('g', 2)],
        ),
        insetKeyboard: 300,
      );
      expect(
        dengan - tanpa,
        closeTo(300, 0.5),
        reason:
            'sheet tak terangkat papan ketik — field paling bawah dan '
            'tombol simpannya tertutup papan ketik yang dipakai mengisinya',
      );
    });

    testWidgets('sheet tinggi tidak menyelinap ke bawah status bar', (
      tester,
    ) async {
      // Ini yang paling mudah luput: useSafeArea BUKAN sekadar tak melindungi
      // bagian atas kalau false — ia AKTIF membuang padding atas lewat
      // MediaQuery.removePadding(removeTop: true). Jadi sheet setinggi layar
      // menabrak jam dan indikator baterai, dan judulnya tak terbaca.
      await tinggiSheet(
        tester,
        ListView(children: const [SizedBox(height: 900)]),
        padding: const EdgeInsets.only(top: 50),
      );

      expect(
        tester.getTopLeft(find.byType(WadahSheetBawah)).dy,
        greaterThanOrEqualTo(50),
        reason:
            'tepi atas sheet berada di y='
            '${tester.getTopLeft(find.byType(WadahSheetBawah)).dy} — di bawah '
            'status bar setinggi 50, jadi barisan teratasnya tertimpa jam '
            'dan indikator sistem',
      );
    });

    testWidgets('inset TIDAK dihitung dua kali', (tester) async {
      // Sebelas widget isi sheet sudah menambah inset bawahnya sendiri. Kalau
      // pembungkus hanya menambah tanpa menolkan, keduanya berlaku sekaligus
      // dan ruang kosongnya jadi dua kali lipat — tanpa satu pun berkas yang
      // terlihat salah bila dibaca sendiri.
      late double padingTerbaca;
      late double insetTerbaca;
      await tinggiSheet(
        tester,
        Builder(
          builder: (c) {
            padingTerbaca = MediaQuery.paddingOf(c).bottom;
            insetTerbaca = MediaQuery.viewInsetsOf(c).bottom;
            return const SizedBox(height: 100);
          },
        ),
        padding: const EdgeInsets.only(bottom: 34),
        insetKeyboard: 300,
      );

      expect(
        padingTerbaca,
        0,
        reason:
            'isi sheet masih membaca padding bawah $padingTerbaca — widget '
            'yang menambahnya sendiri akan menghasilkan ruang dua kali lipat',
      );
      expect(insetTerbaca, 0, reason: 'viewInsets bawah masih terbaca');
    });
  });

  group('penjaga', () {
    // Perbaikan ini hidup di SATU tempat. Penjaga berikut memastikan tempat
    // itu tak bisa dilewati — sebab pemanggilan langsung showModalBottomSheet
    // akan lolos kompilasi, lolos analyze, dan lolos code review: tampilannya
    // baru salah di perangkat, dan hanya pada perangkat yang punya notch atau
    // gesture bar.

    test('tak ada showModalBottomSheet langsung di luar helper', () {
      final pelanggar = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('sheet_bawah.dart')) continue;
        if (f.readAsStringSync().contains('showModalBottomSheet')) {
          pelanggar.add(f.path);
        }
      }
      expect(
        pelanggar,
        isEmpty,
        reason:
            'memanggil showModalBottomSheet langsung melewati useSafeArea dan '
            'inset bawah. Pakai tampilkanSheetBawah(). Pelanggar: $pelanggar',
      );
    });

    test('helper benar-benar menyalakan useSafeArea', () {
      // Bukan tautologi: tes tinggi di atas hanya menyentuh sisi bawah. Kalau
      // useSafeArea dicabut, satu-satunya yang memerah adalah tes status bar
      // — dan tes itu mudah ikut terhapus bersama perubahan yang mencabutnya.
      final src = File(
        'lib/shared/widgets/sheet_bawah.dart',
      ).readAsStringSync();
      expect(src.contains('useSafeArea: true'), isTrue);
    });
  });
}
