import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/shared/widgets/wadah_branch_beranimasi.dart';

// Perpindahan antartab.
//
// # KENAPA DIANIMASIKAN
//
// StatefulShellRoute.indexedStack menukar branch dalam SATU frame: layar Kasir
// hilang, layar Riwayat muncul, tanpa apa pun di antaranya. Di layar POS yang
// padat angka, perpindahan mendadak membuat mata kehilangan jejak dan kasir
// harus memindai ulang dari nol untuk memastikan ia ada di halaman yang benar.
//
// # YANG PALING PENTING DIJAGA
//
// Bukan mulusnya — itu tak bisa diukur tes. Yang dijaga adalah HARGA yang tak
// boleh dibayar untuk kemulusan itu:
//
//   1. STATE SETIAP BRANCH TETAP HIDUP. Cara termudah menganimasikan pergantian
//      adalah AnimatedSwitcher, dan ia MEMBUANG widget lama. Untuk shell ini
//      artinya keranjang yang sedang diisi, posisi gulir daftar produk, dan
//      isian form di tab lain hilang tiap kali kasir menengok tab lain —
//      kebalikan dari yang dijanjikan StatefulShellRoute.
//
//   2. BRANCH TAK AKTIF TIDAK MENERIMA SENTUHAN. Ia masih terpasang di pohon
//      dan menempati seluruh layar; tanpa IgnorePointer, ketukan kasir bisa
//      mendarat di tombol halaman yang tak terlihat.
//
//   3. BRANCH TAK AKTIF TIDAK MEMBAKAR FRAME. Tiga halaman tersembunyi yang
//      ticker-nya tetap jalan menghabiskan baterai tablet sepanjang hari tanpa
//      satu piksel pun yang berubah.

/// Widget ber-state yang menghitung berapa kali ia DIBANGUN ULANG dari nol.
/// Kalau wadahnya membuang lalu membuat ulang anaknya, angka ini bertambah.
class _Jejak extends StatefulWidget {
  final String nama;
  _Jejak(this.nama) : super(key: ValueKey('jejak-$nama'));

  @override
  State<_Jejak> createState() => _JejakState();
}

class _JejakState extends State<_Jejak> {
  static final Map<String, int> dibuat = {};
  int ketukan = 0;

  @override
  void initState() {
    super.initState();
    dibuat[widget.nama] = (dibuat[widget.nama] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => ketukan++),
      behavior: HitTestBehavior.opaque,
      child: Center(child: Text('${widget.nama}:$ketukan')),
    );
  }
}

Future<void> pasang(WidgetTester tester, int aktif) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WadahBranchBeranimasi(
          aktif: aktif,
          anak: [_Jejak('A'), _Jejak('B'), _Jejak('C')],
        ),
      ),
    ),
  );
}

/// Opasitas yang BENAR-BENAR tergambar untuk satu branch.
double opasitasBranch(WidgetTester tester, String nama) {
  final f = find.ancestor(
    of: find.byKey(ValueKey('jejak-$nama')),
    matching: find.byType(FadeTransition),
  );
  return tester.widget<FadeTransition>(f.first).opacity.value;
}

void main() {
  setUp(_JejakState.dibuat.clear);

  testWidgets('state tiap branch TETAP HIDUP saat berpindah', (tester) async {
    await pasang(tester, 0);
    await tester.pumpAndSettle();

    // Ketuk branch A dua kali → hitungannya 2.
    await tester.tap(find.text('A:0'));
    await tester.pump();
    await tester.tap(find.text('A:1'));
    await tester.pump();
    expect(find.text('A:2'), findsOneWidget);

    // Pindah ke B, lalu kembali ke A.
    await pasang(tester, 1);
    await tester.pumpAndSettle();
    await pasang(tester, 0);
    await tester.pumpAndSettle();

    expect(
      find.text('A:2'),
      findsOneWidget,
      reason:
          'hitungan A kembali ke nol — wadahnya membuang lalu membangun '
          'ulang branch-nya, dan keranjang yang sedang diisi kasir ikut '
          'hilang tiap kali ia menengok tab lain',
    );
    expect(
      _JejakState.dibuat['A'],
      1,
      reason: 'branch A dibangun ${_JejakState.dibuat['A']} kali',
    );
  });

  testWidgets('ketiga branch dibangun SEKALI saja, walau berpindah-pindah', (
    tester,
  ) async {
    await pasang(tester, 0);
    await tester.pumpAndSettle();
    for (final i in [1, 2, 0, 2, 1]) {
      await pasang(tester, i);
      await tester.pumpAndSettle();
    }
    expect(_JejakState.dibuat, {'A': 1, 'B': 1, 'C': 1});
  });

  testWidgets('branch tak aktif tidak menangkap sentuhan', (tester) async {
    await pasang(tester, 0);
    await tester.pumpAndSettle();

    // B dan C menempati seluruh layar juga, hanya tak terlihat. Ketukan di
    // tengah layar harus mendarat di A saja.
    await tester.tapAt(tester.getCenter(find.byType(WadahBranchBeranimasi)));
    await tester.pump();

    expect(find.text('A:1'), findsOneWidget);
    expect(
      find.text('B:0'),
      findsOneWidget,
      reason: 'B ikut menerima ketukan padahal tak terlihat',
    );
    expect(find.text('C:0'), findsOneWidget);
  });

  testWidgets('branch tak aktif berhenti mengetik frame', (tester) async {
    await pasang(tester, 1);
    await tester.pumpAndSettle();

    // TickerMode yang mati membuat animasi di dalam branch tersembunyi
    // berhenti. Diperiksa lewat TickerMode.of, sumber kebenaran yang sama yang
    // dibaca setiap AnimationController di dalamnya.
    bool aktifDi(String nama) {
      final ctx = tester.element(find.text('$nama:0'));
      return TickerMode.valuesOf(ctx).enabled;
    }

    expect(aktifDi('B'), isTrue, reason: 'branch aktif justru dibekukan');
    expect(
      aktifDi('A'),
      isFalse,
      reason:
          'branch tersembunyi masih mengetik frame — tiga halaman yang '
          'tak terlihat membakar baterai tablet sepanjang hari',
    );
    expect(aktifDi('C'), isFalse);
  });

  testWidgets('perpindahannya BERTAHAP, bukan seketika', (tester) async {
    await pasang(tester, 0);
    await tester.pumpAndSettle();
    await pasang(tester, 1);

    // Di pertengahan durasi, keduanya harus setengah tampak — itulah yang
    // membedakan animasi silang dari pertukaran satu frame.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(WadahBranchBeranimasi.durasi ~/ 2);

    // Nilai targetnya sudah berganti sejak frame pertama; yang bertahap adalah
    // yang TERGAMBAR. Dibaca dari FadeTransition milik BRANCH-nya sendiri —
    // MaterialApp dan Scaffold memasang FadeTransition-nya sendiri, jadi
    // find.byType saja mengembalikan tujuh dan sebagian besar bukan punya kita.
    final nilai = [
      'A',
      'B',
      'C',
    ].map((n) => opasitasBranch(tester, n)).toList();
    expect(
      nilai.where((v) => v > 0.05 && v < 0.95).isNotEmpty,
      isTrue,
      reason:
          'tak ada branch yang setengah tampak di pertengahan animasi — '
          'perpindahannya masih seketika: $nilai',
    );
  });

  testWidgets('setelah animasi selesai, hanya branch aktif yang tampak', (
    tester,
  ) async {
    await pasang(tester, 2);
    await tester.pumpAndSettle();

    final nilai = [
      'A',
      'B',
      'C',
    ].map((n) => opasitasBranch(tester, n)).toList();
    expect(
      nilai.where((v) => v > 0.99).length,
      1,
      reason: 'lebih dari satu branch tampak penuh: $nilai',
    );
    expect(opasitasBranch(tester, 'C'), greaterThan(0.99));
  });

  testWidgets('durasinya tidak melelahkan untuk dipakai puluhan kali sehari', (
    tester,
  ) async {
    // Kasir berpindah tab puluhan kali per shift. Setengah detik akan terasa
    // lamban pada pemakaian kelima.
    expect(WadahBranchBeranimasi.durasi.inMilliseconds, lessThanOrEqualTo(300));
    expect(
      WadahBranchBeranimasi.durasi.inMilliseconds,
      greaterThanOrEqualTo(120),
    );
  });
}
