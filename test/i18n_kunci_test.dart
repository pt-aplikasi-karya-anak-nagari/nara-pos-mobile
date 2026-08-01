import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
  // `ref.t('x')`, `ref.read(...).t('x')`, dan `tr('x', locale)`.
  final polaT = RegExp(r"\.t\(\s*'([^']+)'\s*\)");
  final polaTr = RegExp(r"\btr\(\s*'([^']+)'");

  final hasil = <String, Set<String>>{};
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final isi = f.readAsStringSync();
    for (final pola in [polaT, polaTr]) {
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
      r"'([a-z0-9_.]+)':\s*\{([^}]*)\}",
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
}
