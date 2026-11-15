import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nara_pos_mobile/core/i18n.dart';

// Kunci terjemahan yang lupa didaftarkan TIDAK menimbulkan error apa pun.
//
//     String tr(String key, AppLocale locale) {
//       final entry = _strings[key];
//       if (entry == null) return key;   // ← kuncinya sendiri yang tampil
//       ...
//
// Jadi `ref.t('common.active')` yang kuncinya belum ada akan mencetak tulisan
// "common.active" di layar pengguna. Tidak crash, tidak ada log, tidak ada
// peringatan analyzer — satu-satunya cara menemukannya adalah membuka
// halamannya dan membacanya.
//
// Saat tes ini ditulis ada TIGA yang sedang tampil mentah di aplikasi:
//
//     common.active        saklar aktif di form karyawan
//     common.required      validator di form produk & kategori
//     product.delete_perm  dialog konfirmasi hapus produk
//
// Ketiganya sudah didaftarkan. Yang dijaga di berkas ini adalah KELASNYA:
// kunci apa pun yang dipakai UI harus punya terjemahan, selamanya.
//
// # KENAPA MENYAPU BERKAS, BUKAN MENDAFTAR KUNCI SATU-SATU
//
// Daftar kunci yang ditulis tangan di tes akan basi pada penambahan pertama —
// dan yang basi justru diam, bukan gagal. Menyapu lib/ berarti kunci yang
// ditambahkan besok ikut terjaga tanpa siapa pun perlu ingat memperbarui tes
// ini.

/// Semua kunci yang benar-benar dipanggil UI, beserta berkas pemakainya.
Map<String, Set<String>> _kunciDipakai() {
  // `ref.t('x')` / `context.t('x')`, `tr('x', locale)`, dan versi
  // berparameternya `.tf('x', {...})` / `trf('x', locale, {...})`.
  final polaT = RegExp(r"\.t\(\s*'([^']+)'\s*\)");
  final polaTr = RegExp(r"\btr\(\s*'([^']+)'");
  final polaTf = RegExp(r"\.tf\(\s*'([^']+)'");
  final polaTrf = RegExp(r"\btrf\(\s*'([^']+)'");

  final hasil = <String, Set<String>>{};
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final isi = f.readAsStringSync();
    for (final pola in [polaT, polaTr, polaTf, polaTrf]) {
      for (final m in pola.allMatches(isi)) {
        hasil.putIfAbsent(m.group(1)!, () => <String>{}).add(f.path);
      }
    }
  }
  return hasil;
}

void main() {
  test('setiap kunci yang dipakai UI punya terjemahan', () {
    final dipakai = _kunciDipakai();

    // Penjaga terhadap sapuan yang diam-diam tak menemukan apa-apa: kalau
    // regexp-nya rusak atau direktori kerjanya bergeser, `dipakai` jadi kosong
    // dan tes ini lulus tanpa memeriksa apa pun.
    expect(
      dipakai.length,
      greaterThan(100),
      reason: 'sapuan hanya menemukan ${dipakai.length} kunci — regexp atau '
          'direktori kerjanya kemungkinan bermasalah',
    );

    final hilang = <String, Set<String>>{};
    for (final entry in dipakai.entries) {
      // Kunci yang tak terdaftar dikembalikan apa adanya oleh tr().
      if (tr(entry.key, AppLocale.id) == entry.key) {
        hilang[entry.key] = entry.value;
      }
    }

    expect(
      hilang.keys,
      isEmpty,
      reason: 'kunci berikut akan TAMPIL MENTAH di layar:\n'
          '${hilang.entries.map((e) => '  ${e.key}\n${e.value.map((f) => '      $f').join('\n')}').join('\n')}',
    );
  });

  test('setiap entri mendaftarkan "en", bukan mengandalkan cadangan', () {
    // Cadangan `entry[locale.name] ?? entry['id']` membuat entri yang hanya
    // punya versi Indonesia tetap "berfungsi" dalam bahasa Inggris — dengan
    // diam-diam menampilkan teks Indonesia.
    //
    // Yang diperiksa adalah ADANYA kunci 'en', bukan teksnya berbeda dari
    // 'id'. Versi pertama tes ini membandingkan teks, dan langsung salah
    // menuduh tujuh entri yang sah: "SKU", "Barcode", "PDF", "CSV", "Reset" —
    // kata yang memang sama di kedua bahasa. Perbedaan teks bukan bukti
    // adanya terjemahan, dan kesamaan teks bukan bukti ketiadaannya.
    final isi = File('lib/core/i18n.dart').readAsStringSync();
    final entri = RegExp(
      // Badan entri boleh memuat parameter "{nama}" di dalam teksnya.
      r"'([a-z0-9_.]+)':\s*\{((?:[^{}]|\{[a-z_]+\})*)\}",
      multiLine: true,
    );

    final tanpaEn = <String>[];
    for (final m in entri.allMatches(isi)) {
      final badan = m.group(2)!;
      if (!badan.contains("'id'")) continue; // bukan entri terjemahan
      if (!badan.contains("'en'")) tanpaEn.add(m.group(1)!);
    }

    // Penjaga sapuan kosong, sama seperti di tes pertama.
    final total = entri
        .allMatches(isi)
        .where((m) => m.group(2)!.contains("'id'"))
        .length;
    expect(total, greaterThan(200), reason: 'sapuan entri hanya menemukan $total');

    expect(tanpaEn, isEmpty, reason: 'entri tanpa terjemahan Inggris: $tanpaEn');
  });

  group('tr()', () {
    test('kunci tak dikenal dikembalikan apa adanya — disengaja', () {
      // Perilaku ini sendiri dikunci: ia yang membuat kunci hilang TERLIHAT
      // di layar alih-alih menampilkan string kosong. Layar kosong jauh lebih
      // sulit dilacak daripada tulisan "common.active" yang aneh.
      expect(tr('kunci.yang.tak.pernah.ada', AppLocale.id),
          'kunci.yang.tak.pernah.ada');
    });

    test('memberi teks berbeda per bahasa', () {
      expect(tr('common.cancel', AppLocale.id), 'Batal');
      expect(tr('common.cancel', AppLocale.en), 'Cancel');
    });

    test('ketiga kunci yang dulu hilang kini ada', () {
      // Tes di atas sudah menutup kelasnya; ketiganya dieja di sini supaya
      // kalau salah satu terhapus kelak, pesan gagalnya menyebut yang mana.
      for (final k in ['common.active', 'common.required', 'product.delete_perm']) {
        expect(tr(k, AppLocale.id), isNot(k), reason: k);
        expect(tr(k, AppLocale.en), isNot(k), reason: k);
      }
    });
  });

  group('trf() — teks berparameter', () {
    test('mengganti {nama} dengan nilainya', () {
      expect(trf('cart.pay', AppLocale.id, {'total': 'Rp10.000'}),
          'Bayar Rp10.000');
      expect(trf('cart.pay', AppLocale.en, {'total': 'Rp10.000'}),
          'Pay Rp10.000');
      // null tidak boleh tercetak sebagai tulisan "null".
      expect(trf('cart.pay', AppLocale.id, {'total': null}), 'Bayar ');
    });

    test('"id" dan "en" memakai parameter yang sama', () {
      // Parameter yang hanya ada di satu bahasa tampil mentah ("{amount}") di
      // bahasa lainnya — dan seperti kunci hilang, itu tidak menimbulkan error.
      final isi = File('lib/core/i18n.dart').readAsStringSync();
      final kunci = RegExp(r"^  '([a-zA-Z0-9_.]+)':", multiLine: true);
      final param = RegExp(r'\{([a-z_]+)\}');
      Set<String> paramDari(String teks) =>
          param.allMatches(teks).map((m) => m.group(1)!).toSet();

      final beda = <String>[];
      var berparameter = 0;
      for (final m in kunci.allMatches(isi)) {
        final k = m.group(1)!;
        final id = paramDari(tr(k, AppLocale.id));
        final en = paramDari(tr(k, AppLocale.en));
        if (id.isNotEmpty) berparameter++;
        if (id.length != en.length || !id.containsAll(en)) {
          beda.add('$k: id=$id en=$en');
        }
      }
      expect(berparameter, greaterThan(10),
          reason: 'sapuan tak menemukan teks berparameter');
      expect(beda, isEmpty,
          reason: 'parameter berbeda antar bahasa:\n${beda.join('\n')}');
    });
  });

  group('context.t()', () {
    // Memompa satu Builder, opsional di bawah ProviderScope yang bahasanya
    // dipaksa, dan opsional di bawah Localizations berbahasa lain.
    Future<String> teks(
      WidgetTester tester, {
      AppLocale? bahasaProvider,
      Locale? localePerangkat,
    }) async {
      late String hasil;
      Widget pohon = Builder(
        builder: (context) {
          hasil = context.t('common.cancel');
          return const SizedBox();
        },
      );
      if (localePerangkat != null) {
        pohon = Localizations(
          locale: localePerangkat,
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: pohon,
        );
      }
      if (bahasaProvider != null) {
        pohon = ProviderScope(
          // Kunci per bahasa: pumpWidget kedua dalam satu tes harus membuat
          // ProviderScope BARU, bukan memakai ulang wadah yang lama.
          key: ValueKey(bahasaProvider),
          overrides: [
            localeProvider.overrideWith(() => _BahasaTetap(bahasaProvider)),
          ],
          child: pohon,
        );
      }
      await tester.pumpWidget(pohon);
      return hasil;
    }

    testWidgets('mengikuti localeProvider, sama seperti ref.t', (tester) async {
      expect(await teks(tester, bahasaProvider: AppLocale.en), 'Cancel');
      expect(await teks(tester, bahasaProvider: AppLocale.id), 'Batal');
    });

    testWidgets('bahasa perangkat TIDAK menimpa pilihan pengguna',
        (tester) async {
      // MaterialApp tanpa `locale` memakai bahasa perangkat. Kalau context.t
      // membacanya, layar yang sama bisa menampilkan dua bahasa: sebagian
      // lewat ref.t (provider), sebagian lewat context.t (perangkat).
      expect(
        await teks(
          tester,
          bahasaProvider: AppLocale.id,
          localePerangkat: const Locale('en'),
        ),
        'Batal',
      );
    });

    testWidgets('tanpa ProviderScope jatuh ke bahasa Indonesia',
        (tester) async {
      // Tes yang memompa satu widget tanpa ProviderScope tidak boleh crash.
      expect(await teks(tester), 'Batal');
      expect(await teks(tester, localePerangkat: const Locale('en')), 'Batal');
    });
  });
}

class _BahasaTetap extends LocaleNotifier {
  _BahasaTetap(this._bahasa);
  final AppLocale _bahasa;

  @override
  AppLocale build() => _bahasa;
}
