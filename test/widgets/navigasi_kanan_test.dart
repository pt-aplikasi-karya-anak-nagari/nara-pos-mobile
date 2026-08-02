import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nara_pos_mobile/core/auth_storage.dart';
import 'package:nara_pos_mobile/core/shared_prefs.dart';
import 'package:nara_pos_mobile/features/user/domain/user_role.dart';
import 'package:nara_pos_mobile/shared/widgets/main_shell.dart';

// Letak navigasi utama: rail di KANAN untuk layar lega, bilah bawah untuk
// ponsel sempit.
//
// # KENAPA DIPINDAH
//
// Di tablet melintang, bilah bawah memakan tinggi — dan tinggi justru yang
// paling langka di sana. Rail di samping mengembalikannya, dengan mengambil
// dari lebar yang memang lapang.
//
// # KENAPA TIDAK SELALU DI KANAN
//
// Di ponsel 360 dp, rail selebar 88 dp memakan seperempat lebar layar, dan
// lebar itulah yang menentukan berapa kartu produk muat sebaris. Yang langka di
// ponsel tegak adalah lebar; yang langka di tablet melintang adalah tinggi.
// Navigasinya mengambil dari sisi yang lapang.
//
// # YANG DIJAGA
//
// Bukan "rail-nya ada", melainkan bahwa KEEMPAT tujuan tetap terjangkau dan
// tetap merespons di kedua bentuk. Navigasi yang kehilangan satu tujuan saat
// perangkat diputar adalah kegagalan yang tak terlihat sampai seseorang
// memutarnya.

final tujuan = ['nav.kasir', 'nav.riwayat', 'nav.notifikasi', 'nav.profil'];

/// Label tombol diterjemahkan lewat ref.t(), yang membaca bahasa aktif dari
/// SharedPreferences. Providernya sengaja melempar bila tak ditimpa.
late SharedPreferences _prefs;
late AuthStorage _penyimpanan;

Future<void> siapkan() async {
  SharedPreferences.setMockInitialValues({});
  _prefs = await SharedPreferences.getInstance();
  // Lencana Draft membaca outlet aktif, yang bersandar pada penyimpanan sesi.
  _penyimpanan = AuthStorage(_prefs);
}

Future<List<String>> pasang(
  WidgetTester tester, {
  required bool rail,
  int aktif = 0,
  bool aksi = false,
  Size ukuran = const Size(1024, 768),
}) async {
  final ditekan = <String>[];
  final items = navItemsUtama(UserRole.cashier);

  tester.view.physicalSize = ukuran;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_prefs),
        authStorageProvider.overrideWithValue(_penyimpanan),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: rail
              ? Row(
                  children: [
                    const Expanded(child: SizedBox()),
                    RailKanan(
                      items: items,
                      aktif: aktif,
                      onTap: (i) => ditekan.add(items[i].labelKey),
                      tampilkanAksi: aksi,
                    ),
                  ],
                )
              : const SizedBox(),
          bottomNavigationBar: rail
              ? null
              : BilahBawah(
                  items: items,
                  aktif: aktif,
                  isTablet: false,
                  onTap: (i) => ditekan.add(items[i].labelKey),
                ),
        ),
      ),
    ),
  );
  await tester.pump();
  return ditekan;
}

Rect kotak(WidgetTester tester, String kunci) =>
    tester.getRect(find.byKey(ValueKey('nav-$kunci')));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(siapkan);

  group('rail kanan', () {
    testWidgets('keempat tujuan ada dan tersusun MENURUN', (tester) async {
      await pasang(tester, rail: true);

      final atas = tujuan.map((t) => kotak(tester, t).top).toList();
      for (var i = 1; i < atas.length; i++) {
        expect(atas[i], greaterThan(atas[i - 1]),
            reason: 'tujuan "${tujuan[i]}" tidak berada di bawah '
                '"${tujuan[i - 1]}" — rail-nya tak tersusun tegak');
      }
    });

    testWidgets('menempel di tepi KANAN, bukan kiri', (tester) async {
      await pasang(tester, rail: true, ukuran: const Size(1024, 768));
      final k = kotak(tester, 'nav.kasir');
      expect(k.center.dx, greaterThan(1024 / 2),
          reason: 'rail berada di paruh KIRI layar');
      expect(1024 - k.right, lessThan(24),
          reason: 'rail tidak menempel ke tepi kanan');
    });

    testWidgets('semua tujuan merespons ketukan', (tester) async {
      final ditekan = await pasang(tester, rail: true);
      for (final t in tujuan) {
        await tester.tap(find.byKey(ValueKey('nav-$t')));
        await tester.pump();
      }
      expect(ditekan, tujuan);
    });

    testWidgets('lebarnya tak melebihi seperlima layar tablet',
        (tester) async {
      // Rail yang terlalu gemuk memakan lebar yang seharusnya jadi kartu
      // produk — masalah yang sama dengan yang hendak dihindari di ponsel.
      await pasang(tester, rail: true, ukuran: const Size(1024, 768));
      expect(kotak(tester, 'nav.kasir').width, lessThan(1024 / 5));
    });
  });

  group('bilah bawah (ponsel sempit)', () {
    testWidgets('keempat tujuan ada dan tersusun MENDATAR', (tester) async {
      await pasang(tester, rail: false, ukuran: const Size(360, 780));

      final kiri = tujuan.map((t) => kotak(tester, t).left).toList();
      for (var i = 1; i < kiri.length; i++) {
        expect(kiri[i], greaterThan(kiri[i - 1]),
            reason: 'tujuan "${tujuan[i]}" tidak di kanan "${tujuan[i - 1]}"');
      }
    });

    testWidgets('semua tujuan merespons ketukan', (tester) async {
      final ditekan = await pasang(tester, rail: false,
          ukuran: const Size(360, 780));
      for (final t in tujuan) {
        await tester.tap(find.byKey(ValueKey('nav-$t')));
        await tester.pump();
      }
      expect(ditekan, tujuan);
    });

    testWidgets('tidak meluber di ponsel tersempit', (tester) async {
      await pasang(tester, rail: false, ukuran: const Size(320, 640));
      expect(tester.takeException(), isNull);
    });
  });

  group('penanda tujuan aktif', () {
    for (final bentuk in [true, false]) {
      final nama = bentuk ? 'rail' : 'bilah bawah';
      testWidgets('$nama menandai tepat SATU tujuan sebagai aktif',
          (tester) async {
        // Penanda yang hilang membuat kasir tak tahu ia sedang di mana;
        // penanda ganda lebih buruk lagi.
        await pasang(tester, rail: bentuk, aktif: 2);

        final aktif = tester
            .widgetList<Semantics>(find.byType(Semantics))
            .where((w) => w.properties.selected == true)
            .length;
        expect(aktif, 1, reason: 'ada $aktif tujuan bertanda aktif');
      });
    }

    testWidgets('tujuan aktif diumumkan ke pembaca layar', (tester) async {
      final pegangan = tester.ensureSemantics();
      await pasang(tester, rail: true, aktif: 3);
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .where((w) => w.properties.selected == true && w.properties.button == true)
            .length,
        1,
      );
      pegangan.dispose();
    });
  });

  group('aksi cepat di rail', () {
    // Scan, Custom Order, Meja, dan Draft pindah dari header biru layar Kasir
    // ke rail. Yang dijaga: keempatnya benar-benar ADA di rail, dan hanya
    // muncul di tab Kasir — sheet "Custom Order" yang bisa dibuka dari halaman
    // Profil hanya membingungkan.
    const aksiRail = ['Scan', 'Custom', 'Meja', 'Draft'];

    testWidgets('keempat aksi ada saat di tab Kasir', (tester) async {
      await pasang(tester, rail: true, aksi: true);
      for (final a in aksiRail) {
        expect(find.byKey(ValueKey('aksi-$a')), findsOneWidget,
            reason: 'aksi "$a" hilang dari rail');
      }
    });

    testWidgets('aksi berada DI ATAS tujuan navigasi', (tester) async {
      // Aksi mengubah PESANAN yang sedang dibuat; tujuan memindahkan HALAMAN.
      // Yang lebih sering disentuh saat melayani antrean ada di atas.
      await pasang(tester, rail: true, aksi: true);
      final aksiTerbawah = aksiRail
          .map((a) => tester.getRect(find.byKey(ValueKey('aksi-$a'))).bottom)
          .reduce((a, b) => a > b ? a : b);
      final tujuanTeratas = tujuan
          .map((t) => kotak(tester, t).top)
          .reduce((a, b) => a < b ? a : b);
      expect(aksiTerbawah, lessThan(tujuanTeratas));
    });

    testWidgets('aksi TIDAK muncul di tab selain Kasir', (tester) async {
      await pasang(tester, rail: true, aksi: false);
      for (final a in aksiRail) {
        expect(find.byKey(ValueKey('aksi-$a')), findsNothing,
            reason: 'aksi "$a" tetap muncul padahal bukan di tab Kasir');
      }
      // Tujuannya tetap lengkap — aksi yang disembunyikan tak boleh ikut
      // menyeret navigasinya.
      for (final t in tujuan) {
        expect(find.byKey(ValueKey('nav-$t')), findsOneWidget);
      }
    });

    testWidgets('rail berisi 8 baris tetap terjangkau di layar pendek',
        (tester) async {
      // Ponsel dimiringkan: tinggi tinggal ~360 dp untuk 4 aksi + 4 tujuan.
      // Tanpa gulir, tab Profil di paling bawah jadi tak terjangkau sama
      // sekali — dan tak ada galat apa pun yang memberitahu.
      await pasang(tester, rail: true, aksi: true,
          ukuran: const Size(800, 360));
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsWidgets);
      await tester.drag(find.byKey(const ValueKey('nav-nav.kasir')),
          const Offset(0, -200));
      await tester.pump();
      expect(find.byKey(const ValueKey('nav-nav.profil')), findsOneWidget);
    });
  });

  group('aksi tidak tampil dua kali', () {
    // Saat rail dipakai, header biru layar Kasir HARUS menyembunyikan baris
    // aksinya — kalau tidak, ada dua tombol "Draft" di satu layar dan kasir
    // menekan yang mana pun tanpa tahu keduanya sama.
    //
    // # KENAPA MEMBACA BERKAS SUMBER
    //
    // Prasyaratnya hidup di dalam build() KasirPage, dan memasang KasirPage di
    // tes menuntut hampir seluruh graf provider aplikasi — outlet, produk,
    // keranjang, shift, printer. Yang bisa diperiksa tanpa itu adalah bahwa
    // penjaganya MASIH ADA dan memakai sumber tunggal yang sama. Suntikan yang
    // mencabut penjaga itu lolos dari seluruh tes lain di berkas ini; inilah
    // yang menutupnya.

    test('KasirPage menjaga HeaderAksiKasir dengan pakaiRailNavigasi', () {
      final sumber =
          File('lib/features/kasir/ui/kasir_page.dart').readAsStringSync();
      final i = sumber.indexOf('HeaderAksiKasir(');
      expect(i, greaterThan(0), reason: 'HeaderAksiKasir tak dipakai lagi');

      // Penjaganya harus berada tepat sebelum pemanggilan, bukan di mana pun
      // di berkas.
      final sebelum = sumber.substring(0, i);
      final penjaga = sebelum.lastIndexOf('!context.pakaiRailNavigasi');
      expect(penjaga, greaterThan(0),
          reason: 'HeaderAksiKasir dipanggil TANPA penjaga '
              '!context.pakaiRailNavigasi — di tablet, Scan/Custom/Meja/Draft '
              'akan tampil dua kali: di header dan di rail');
      expect(i - penjaga, lessThan(400),
          reason: 'penjaganya ada tapi terlalu jauh dari pemanggilannya — '
              'kemungkinan menjaga hal lain');
    });

    test('hanya SATU tempat yang memutuskan rail atau bilah', () {
      // Dua tempat membacanya (MainShell & KasirPage). Kalau salah satunya
      // menghitung sendiri dari titik henti, mengubah titik itu akan membuat
      // aksinya dobel atau hilang dari kedua tempat.
      for (final berkas in [
        'lib/shared/widgets/main_shell.dart',
        'lib/features/kasir/ui/kasir_page.dart',
      ]) {
        final isi = File(berkas).readAsStringSync();
        expect(isi.contains('pakaiRailNavigasi'), isTrue,
            reason: '$berkas tak memakai sumber tunggalnya');
        expect(isi.contains('screen != ScreenSize.compact'), isFalse,
            reason: '$berkas menghitung sendiri titik hentinya — '
                'pakai context.pakaiRailNavigasi');
      }
    });
  });
}
