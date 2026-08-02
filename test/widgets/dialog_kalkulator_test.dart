import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nara_pos_mobile/features/kasir/ui/widgets/dialog_kalkulator.dart';
import 'package:nara_pos_mobile/features/kasir/ui/widgets/riwayat_kalkulator.dart';

// Kalkulator kasir.
//
// # KENAPA DIUJI SETELITI INI UNTUK "SEKADAR KALKULATOR"
//
// Angka yang keluar dari sini dibacakan ke pelanggan dan diketik ulang ke
// nota. Kalkulator yang salah tidak pernah menampilkan galat — ia menampilkan
// angka yang tampak wajar, dan uang yang keliru berpindah tangan.
//
// Kesalahan klasiknya semuanya berupa angka masuk akal yang salah:
//
//   "05"            digit pertama menempel ke nol awal.
//   8 × ÷ 2 = 32    operator berturut-turut ikut menghitung, operand yang
//                   sama dipakai dua kali.
//   Infinity        pembagian nol; layar macet sampai ditekan C.
//   3333.3333333    pembagian menyisakan desimal panjang yang tak bisa
//                   dibacakan.

/// Lebar layar uji. Di bawah 620 dialognya memakai tata letak satu kolom
/// (riwayat di atas keypad); di atasnya, riwayat pindah ke kiri. Default
/// dibuat SEMPIT supaya tes perilaku hitungan tak bergantung pada tata letak.
Future<void> buka(WidgetTester t, {double lebar = 400}) async {
  t.view.physicalSize = Size(lebar, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    const ProviderScope(
      child: MaterialApp(home: Scaffold(body: DialogKalkulator())),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tekan(WidgetTester t, List<String> urutan) async {
  for (final k in urutan) {
    await t.tap(find.byKey(ValueKey('kalkulator-$k')));
    await t.pump();
  }
}

String layar(WidgetTester t) =>
    t.widget<Text>(find.byKey(const ValueKey('kalkulator-layar'))).data!;

void main() {
  testWidgets('mulai dari nol', (t) async {
    await buka(t);
    expect(layar(t), '0');
  });

  testWidgets('digit pertama MENGGANTI nol, bukan menempel', (t) async {
    await buka(t);
    await tekan(t, ['5']);
    expect(layar(t), '5', reason: '"05" — nol awalnya tak diganti');
    await tekan(t, ['0']);
    expect(layar(t), '50');
  });

  testWidgets('mengetik 0 lalu 5 menghasilkan 5, bukan "05"', (t) async {
    // Urutan INI yang berbahaya, bukan 5-lalu-0. Percobaan pertama tes ini
    // memakai urutan yang salah, dan suntikan yang mencabut penjaganya LOLOS:
    // '5' pertama ditangani cabang "mulai angka baru" yang berbeda, jadi
    // cabang nol-awal tak pernah tersentuh.
    await buka(t);
    await tekan(t, ['0', '5']);
    expect(layar(t), '5', reason: 'layar menampilkan ${layar(t)}');
  });

  testWidgets('Infinity tak pernah sampai ke layar, termasuk saat berantai', (
    t,
  ) async {
    // _format adalah SATU-SATUNYA yang menahannya. Penjaga kedua di _hitung
    // pernah ada dan terbukti tak bisa diamati dari luar — dicabut supaya tak
    // ada perlindungan palsu yang menyesatkan pembaca berikutnya.
    await buka(t);
    await tekan(t, ['8', '÷', '0', '×', '2', '=']);
    expect(layar(t), '0');
    expect(find.textContaining('Infinity'), findsNothing);
  });

  group('empat operasi dasar', () {
    testWidgets('tambah', (t) async {
      await buka(t);
      await tekan(t, ['1', '2', '+', '8', '=']);
      expect(layar(t), '20');
    });

    testWidgets('kurang, dan hasil negatif tidak disembunyikan', (t) async {
      await buka(t);
      await tekan(t, ['5', '−', '8', '=']);
      expect(layar(t), '-3');
    });

    testWidgets('kali', (t) async {
      await buka(t);
      await tekan(t, ['7', '×', '6', '=']);
      expect(layar(t), '42');
    });

    testWidgets('bagi', (t) async {
      await buka(t);
      await tekan(t, ['9', '0', '÷', '3', '=']);
      expect(layar(t), '30');
    });
  });

  testWidgets('pembagian NOL tidak menampilkan Infinity', (t) async {
    // Dart mengembalikan Infinity, bukan galat. Kalau lolos, layar menampilkan
    // "Infinity" dan kalkulatornya macet di situ sampai ditekan C.
    await buka(t);
    await tekan(t, ['8', '÷', '0', '=']);
    expect(
      layar(t),
      '0',
      reason: 'layar menampilkan ${layar(t)} — kalkulatornya buntu',
    );
  });

  testWidgets('hasil pecahan dibulatkan DUA desimal', (t) async {
    // 10000 ÷ 3 = 3333,333… Angka sepanjang itu tak bisa dibacakan ke
    // pelanggan, dan tak muat di layar.
    await buka(t);
    await tekan(t, ['1', '0', '0', '0', '0', '÷', '3', '=']);
    expect(layar(t), '3333.33');
  });

  testWidgets('hasil bulat TIDAK berkoma', (t) async {
    // "20.00" untuk hasil bulat membuat kasir ragu apakah ada sisa.
    await buka(t);
    await tekan(t, ['1', '0', '+', '1', '0', '=']);
    expect(layar(t), '20');
  });

  testWidgets('operator berturut-turut hanya MENGGANTI operatornya', (t) async {
    // 8 × ÷ 2 harus 4. Kalau operator kedua ikut menghitung, operand 8 dipakai
    // dua kali dan hasilnya 32 — angka yang tampak masuk akal dan salah.
    await buka(t);
    await tekan(t, ['8', '×', '÷', '2', '=']);
    expect(layar(t), '4', reason: 'hasilnya ${layar(t)}, seharusnya 4');
  });

  testWidgets('operasi berantai memakai hasil sebelumnya', (t) async {
    await buka(t);
    await tekan(t, ['2', '+', '3', '+', '4', '=']);
    expect(layar(t), '9');
  });

  testWidgets('koma hanya boleh satu', (t) async {
    await buka(t);
    await tekan(t, ['1', '.', '5', '.', '2']);
    expect(layar(t), '1.52', reason: '"1.5.2" bukan angka yang sah');
  });

  testWidgets('% menghitung persen DARI angka sebelumnya', (t) async {
    // Diskon 10% dari 50.000 diketik 50000 − 10 %, dan harus menghasilkan
    // 5.000 untuk dikurangkan. Membagi 100 begitu saja menghasilkan 0,1 —
    // benar secara matematika, tak berguna di kasir.
    await buka(t);
    await tekan(t, ['5', '0', '0', '0', '0', '−', '1', '0', '%']);
    expect(layar(t), '5000');
    await tekan(t, ['=']);
    expect(layar(t), '45000', reason: 'diskon 10% dari 50.000 → 45.000');
  });

  group('koreksi', () {
    testWidgets('⌫ menghapus satu digit', (t) async {
      await buka(t);
      await tekan(t, ['1', '2', '3', '⌫']);
      expect(layar(t), '12');
    });

    testWidgets('⌫ pada digit terakhir kembali ke nol, bukan kosong', (
      t,
    ) async {
      await buka(t);
      await tekan(t, ['7', '⌫']);
      expect(layar(t), '0');
    });

    testWidgets('C membersihkan operasi yang tertunda juga', (t) async {
      // Membersihkan layar tapi menyisakan operator membuat penekanan
      // berikutnya melanjutkan hitungan yang sudah dibatalkan kasir.
      await buka(t);
      await tekan(t, ['9', '+', '5', 'C', '3', '=']);
      expect(
        layar(t),
        '3',
        reason: 'hasilnya ${layar(t)} — operasi lama masih tertinggal',
      );
    });
  });

  testWidgets('= tanpa operasi tidak mengubah apa pun', (t) async {
    await buka(t);
    await tekan(t, ['4', '2', '=']);
    expect(layar(t), '42');
  });

  testWidgets('nilai ditampilkan juga dalam rupiah', (t) async {
    // Kasir membacakan angkanya ke pelanggan; menghitung nol sendiri di layar
    // adalah tempat salah baca terjadi.
    await buka(t);
    await tekan(t, ['5', '0', '0', '0', '0']);
    expect(find.textContaining('50.000'), findsWidgets);
  });

  group('riwayat perhitungan', () {
    testWidgets('hasil masuk riwayat LENGKAP dengan ekspresinya', (t) async {
      // Riwayat berisi "45000" saja tak berguna: kasir tak tahu itu dari
      // hitungan yang mana. Ekspresinya yang membuat baris itu bisa dibaca
      // lagi lima menit kemudian.
      await buka(t);
      await tekan(t, ['5', '0', '0', '0', '0', '−', '5', '0', '0', '0', '=']);
      expect(find.text('50000 − 5000'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('kalkulator-riwayat-0')),
        findsOneWidget,
      );
    });

    testWidgets('yang TERBARU di atas', (t) async {
      await buka(t);
      await tekan(t, ['1', '+', '1', '=']);
      await tekan(t, ['9', '+', '9', '=']);
      final pertama = t.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('kalkulator-riwayat-0')),
          matching: find.textContaining('+'),
        ),
      );
      expect(
        pertama.data,
        '9 + 9',
        reason:
            'baris teratas "${pertama.data}" — yang baru saja dihitung '
            'adalah yang paling mungkin dilihat lagi, jadi harus di atas',
      );
    });

    testWidgets('mengetuk riwayat memuat hasilnya ke layar', (t) async {
      // Riwayat yang hanya bisa dibaca memaksa kasir mengetik ulang, dan
      // mengetik ulang adalah tempat salah ketik terjadi.
      await buka(t);
      await tekan(t, ['2', '5', '0', '0', '0', '+', '5', '0', '0', '0', '=']);
      await tekan(t, ['7']); // layar berpindah ke angka lain
      expect(layar(t), '7');

      await t.tap(find.byKey(const ValueKey('kalkulator-riwayat-0')));
      await t.pump();
      expect(layar(t), '30000');
    });

    testWidgets('angka setelah mengetuk riwayat MENGGANTI, bukan menempel', (
      t,
    ) async {
      // Kalau menempel, mengetuk 30000 lalu menekan 5 menghasilkan 300005 —
      // angka yang tampak wajar dan sama sekali salah.
      await buka(t);
      await tekan(t, ['1', '0', '+', '2', '0', '=']);
      await t.tap(find.byKey(const ValueKey('kalkulator-riwayat-0')));
      await t.pump();
      await tekan(t, ['5']);
      expect(layar(t), '5', reason: 'layar menampilkan ${layar(t)}');
    });

    testWidgets('Bersihkan mengosongkan riwayat', (t) async {
      await buka(t);
      await tekan(t, ['3', '+', '3', '=']);
      expect(
        find.byKey(const ValueKey('kalkulator-riwayat-0')),
        findsOneWidget,
      );

      await t.tap(find.byKey(const ValueKey('kalkulator-riwayat-bersihkan')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('kalkulator-riwayat-0')), findsNothing);
    });

    testWidgets('riwayat kosong menjelaskan dirinya, bukan diam', (t) async {
      await buka(t);
      expect(find.textContaining('Belum ada perhitungan'), findsOneWidget);
      // Tombol bersihkan tak ditampilkan saat tak ada yang bisa dibersihkan.
      expect(
        find.byKey(const ValueKey('kalkulator-riwayat-bersihkan')),
        findsNothing,
      );
    });

    testWidgets('operasi yang belum ditekan = TIDAK masuk riwayat', (t) async {
      // Hitungan setengah jadi bukan hasil. Mencatatnya membuat daftar penuh
      // angka yang tak pernah dipakai siapa pun.
      await buka(t);
      await tekan(t, ['8', '+', '2']);
      expect(find.byKey(const ValueKey('kalkulator-riwayat-0')), findsNothing);
      await tekan(t, ['=']);
      expect(
        find.byKey(const ValueKey('kalkulator-riwayat-0')),
        findsOneWidget,
      );
    });

    test('riwayat dibatasi 50 baris', () {
      // Kasir sibuk menghitung ratusan kali sehari; daftar tanpa batas hanya
      // menghabiskan memori untuk baris yang tak akan pernah digulir orang.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(riwayatKalkulatorProvider.notifier);
      for (var i = 0; i < 60; i++) {
        n.tambah('$i + 0', '$i');
      }
      final r = c.read(riwayatKalkulatorProvider);
      expect(r, hasLength(RiwayatKalkulator.batas));
      expect(r.first.hasil, '59', reason: 'yang terbaru harus bertahan');
    });
  });

  testWidgets('ekspresi yang SEDANG disusun tampil di layar', (t) async {
    // Kasir yang terganggu di tengah hitungan bisa melihat lagi apa yang
    // sedang ia kerjakan — bukan hanya angka terakhir yang diketik.
    await buka(t);
    await tekan(t, ['1', '2', '0', '0', '0', '×', '3']);
    final ekspresi = t.widget<Text>(
      find.byKey(const ValueKey('kalkulator-ekspresi')),
    );
    expect(ekspresi.data, '12000 × 3');
  });
}
