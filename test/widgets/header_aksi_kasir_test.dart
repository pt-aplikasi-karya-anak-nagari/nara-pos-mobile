import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nara_pos_mobile/core/outlet_scope.dart';
import 'package:nara_pos_mobile/features/drafts/providers.dart';
import 'package:nara_pos_mobile/features/kasir/ui/widgets/header_aksi_kasir.dart';

// Baris identitas outlet + aksi cepat di puncak layar Kasir.
//
// # KEJADIANNYA
//
// Di layar 390 dp, baris ini meluber 155 piksel. Pita kuning-hitam Flutter
// menutupi tombol Meja dan Draft, dan keduanya tak bisa ditekan sama sekali:
// kasir kehilangan akses ke daftar meja dan ke pesanan tersimpan, di layar yang
// paling sering ia pakai.
//
// Bertahan lama karena meluber hanya terjadi di layar sempit, sementara
// pengembangan sehari-hari berlangsung di tablet.
//
// # YANG DIJAGA
//
// Bukan "modenya benar" — itu detail yang boleh berubah. Yang dijaga adalah
// dua hal yang tak boleh berubah pada lebar berapa pun:
//
//   1. TIDAK MELUBER. Diperiksa lewat exception RenderFlex yang memang
//      dilempar Flutter — bukan lewat perbandingan angka yang saya karang.
//   2. KEEMPAT AKSI TETAP ADA dan tetap bisa ditekan. Susunan yang "rapi"
//      dengan cara membuang tombol Draft menyelesaikan luberan sambil
//      menciptakan masalah yang lebih buruk.

/// Lebar layar nyata yang harus dilayani, dari yang paling sempit.
///
/// 320 dp = iPhone SE generasi pertama dan sebagian ponsel Android murah yang
/// masih banyak dipakai kasir warung. 1280 dp = tablet besar yang dipangku
/// dalam mode lanskap.
const lebarUji = <int, String>{
  320: 'ponsel sangat sempit (iPhone SE 1)',
  360: 'Android umum',
  375: 'iPhone 8 / SE 2',
  390: 'iPhone 13 — LEBAR YANG DILAPORKAN MELUBER',
  412: 'Pixel',
  428: 'iPhone Pro Max',
  600: 'tablet kecil potret',
  768: 'iPad potret',
  834: 'iPad Air',
  1024: 'iPad lanskap',
  1194: 'iPad Pro 11 lanskap',
  1280: 'tablet besar',
};

Future<void> pasang(
  WidgetTester tester, {
  required int lebar,
  String outlet = 'Febriqgal Coffie Shop',
  int draft = 0,
}) async {
  tester.view.physicalSize = Size(lebar.toDouble(), 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeOutletLabelProvider.overrideWithValue(outlet),
        draftsCountProvider.overrideWithValue(draft),
      ],
      child: MaterialApp(
        home: Scaffold(
          // Latar biru seperti aslinya; chip-nya berteks putih.
          backgroundColor: const Color(0xFF1D4ED8),
          body: Column(
            children: [
              HeaderAksiKasir(
                onScan: () {},
                onCustomOrder: () {},
                onMeja: () {},
                onDraft: () {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('tidak meluber di lebar mana pun', () {
    lebarUji.forEach((lebar, nama) {
      testWidgets('$lebar dp — $nama', (tester) async {
        await pasang(tester, lebar: lebar);
        expect(
          tester.takeException(),
          isNull,
          reason: 'header meluber di $lebar dp ($nama) — tombolnya tertutup '
              'pita kuning-hitam dan tak bisa ditekan',
        );
      });
    });
  });

  group('keempat aksi selalu terjangkau', () {
    lebarUji.forEach((lebar, nama) {
      testWidgets('$lebar dp — $nama', (tester) async {
        final ditekan = <String>[];
        tester.view.physicalSize = Size(lebar.toDouble(), 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activeOutletLabelProvider.overrideWithValue('Febriqgal Coffie Shop'),
              draftsCountProvider.overrideWithValue(0),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    HeaderAksiKasir(
                      onScan: () => ditekan.add('Scan'),
                      onCustomOrder: () => ditekan.add('Custom Order'),
                      onMeja: () => ditekan.add('Meja'),
                      onDraft: () => ditekan.add('Draft'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Dicari lewat Key, bukan lewat teks: teks yang tampil berubah per
        // mode (label penuh / pendek / tak ada sama sekali), jadi pencarian
        // berbasis teks akan hijau hanya di sebagian lebar layar.
        for (final label in ['Scan', 'Custom Order', 'Meja', 'Draft']) {
          final target = find.byKey(ValueKey('aksi-$label'));
          expect(target, findsOneWidget,
              reason: 'aksi "$label" hilang di $lebar dp ($nama)');
          await tester.tap(target);
          await tester.pump();
        }

        expect(ditekan, ['Scan', 'Custom Order', 'Meja', 'Draft'],
            reason: 'ada aksi yang tak merespons ketukan di $lebar dp');
      });
    });
  });

  group('nama outlet sepanjang apa pun tidak merusak susunannya', () {
    const nama = [
      'Kopi',
      'Febriqgal Coffie Shop',
      'Warung Kopi Bang Jamal Cabang Simpang Empat Padang',
      'WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW',
    ];
    for (final outlet in nama) {
      testWidgets('"${outlet.length > 24 ? '${outlet.substring(0, 24)}…' : outlet}" @ 360 dp',
          (tester) async {
        // Nama outlet ditentukan pelanggan dan tak berbatas. Susunan yang
        // dipilih dari titik henti lebar layar saja akan meluber untuk nama
        // panjang di lebar yang sama yang aman untuk nama pendek.
        await pasang(tester, lebar: 360, outlet: outlet);
        expect(tester.takeException(), isNull,
            reason: 'meluber untuk nama outlet ${outlet.length} karakter');
      });
    }
  });

  group('lencana draft', () {
    for (final jumlah in [0, 9, 99, 250]) {
      testWidgets('$jumlah draft @ 360 dp tidak membuatnya meluber',
          (tester) async {
        // Lencana menambah lebar chip Draft dan ikut diperhitungkan saat
        // memilih mode. Kasir sibuk bisa menumpuk puluhan draft, dan justru
        // saat itulah tombolnya paling dibutuhkan.
        await pasang(tester, lebar: 360, draft: jumlah);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('jumlah di atas 99 ditampilkan 99+', (tester) async {
      await pasang(tester, lebar: 1280, draft: 250);
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('nol tidak menampilkan lencana', (tester) async {
      await pasang(tester, lebar: 1280, draft: 0);
      expect(find.text('0'), findsNothing);
    });
  });

  group('setelan ukuran huruf sistem yang besar', () {
    // Kasir yang matanya lelah menaikkan ukuran huruf di setelan ponselnya, dan
    // Flutter menghormatinya. Pengukuran di widget ini memakai TextPainter
    // tanpa faktor skala, jadi ia TAK bisa meramalkan keadaan ini — di sinilah
    // gulir mendatar membuktikan gunanya.
    for (final skala in [1.0, 1.3, 1.8, 2.5]) {
      testWidgets('skala ${skala}x @ 360 dp tidak meluber', (tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activeOutletLabelProvider.overrideWithValue('Febriqgal Coffie Shop'),
              draftsCountProvider.overrideWithValue(12),
            ],
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(skala)),
                child: Scaffold(
                  body: Column(
                    children: [
                      HeaderAksiKasir(
                        onScan: () {},
                        onCustomOrder: () {},
                        onMeja: () {},
                        onDraft: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: 'meluber pada skala huruf ${skala}x');
        for (final label in ['Scan', 'Custom Order', 'Meja', 'Draft']) {
          expect(find.byKey(ValueKey('aksi-$label')), findsOneWidget,
              reason: 'aksi "$label" hilang pada skala huruf ${skala}x');
        }
      });
    }
  });

  testWidgets('label tetap terbaca di tablet', (tester) async {
    // Sisi yang tak boleh ikut hilang saat memperbaiki layar sempit: di layar
    // lega, keempatnya harus tetap berlabel penuh — bukan diseragamkan jadi
    // ikon demi kesederhanaan kode.
    await pasang(tester, lebar: 1024);
    for (final label in ['Scan', 'Custom Order', 'Meja', 'Draft']) {
      expect(find.text(label), findsOneWidget, reason: 'label "$label" hilang di tablet');
    }
  });

  testWidgets('di mode ikon, tiap aksi tetap punya nama untuk pembaca layar',
      (tester) async {
    // Di layar tersempit labelnya tak tergambar. Tanpa Semantics, empat tombol
    // yang paling sering dipakai kasir jadi "tombol" tanpa nama bagi TalkBack
    // dan VoiceOver — tak bisa dipakai sama sekali oleh yang mengandalkannya.
    final pegangan = tester.ensureSemantics();
    await pasang(tester, lebar: 320, outlet: 'Warung Kopi Bang Jamal Simpang Empat');

    for (final label in ['Scan', 'Custom Order', 'Meja', 'Draft']) {
      expect(find.bySemanticsLabel(label), findsWidgets,
          reason: 'aksi "$label" tak punya nama untuk pembaca layar');
    }
    pegangan.dispose();
  });

  testWidgets('area sentuh tiap aksi minimal 36 dp', (tester) async {
    // Chip aslinya ~28 dp. Di layar sempit — tempat chip paling berdesakan —
    // itu terlalu kecil untuk ibu jari, dan salah tekan di layar kasir berarti
    // dialog yang salah terbuka di depan antrean.
    await pasang(tester, lebar: 360);
    for (final label in ['Scan', 'Custom Order', 'Meja', 'Draft']) {
      final ukuran = tester.getSize(find.byKey(ValueKey('aksi-$label')));
      expect(ukuran.height, greaterThanOrEqualTo(36.0),
          reason: 'area sentuh "$label" hanya ${ukuran.height} dp');
    }
  });
}
