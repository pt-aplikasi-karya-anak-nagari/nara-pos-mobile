import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/kasir/ui/widgets/dialog_kalkulator.dart';

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

Future<void> buka(WidgetTester t) async {
  await t.pumpWidget(
    const MaterialApp(home: Scaffold(body: DialogKalkulator())),
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
}
