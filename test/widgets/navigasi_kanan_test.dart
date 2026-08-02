import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

Future<void> siapkan() async {
  SharedPreferences.setMockInitialValues({});
  _prefs = await SharedPreferences.getInstance();
}

Future<List<String>> pasang(
  WidgetTester tester, {
  required bool rail,
  int aktif = 0,
  Size ukuran = const Size(1024, 768),
}) async {
  final ditekan = <String>[];
  final items = navItemsUtama(UserRole.cashier);

  tester.view.physicalSize = ukuran;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(_prefs)],
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
}
