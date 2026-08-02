import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Bunyi notifikasi: laci kas, dipaksa untuk semua notifikasi aplikasi.
//
// # KENAPA DIJAGA DARI BERKAS, BUKAN DARI PERILAKU
//
// Semua cara gagal di sini SENYAP. Tidak ada galat, tidak ada log, tidak ada
// yang terlihat di layar — notifikasinya tetap muncul, hanya bunyinya nada
// bawaan OS. Satu-satunya cara tahu adalah memasang aplikasi di perangkat asli
// lalu mendengarkan, dan itu tak pernah terjadi di CI.
//
// Empat cara gagalnya:
//
//   nama resource salah ketik   Android jatuh ke nada default.
//   berkas tak di res/raw       sama; channel bahkan bisa lahir rusak.
//   iOS diberi .mp3             iOS HANYA menerima caf/aiff/wav. mp3
//                               diabaikan tanpa sepatah kata pun.
//   caf tak di Copy Bundle      berkasnya ada di repo tapi tidak ikut ke
//   Resources                   dalam aplikasi — iOS tak menemukannya.
//
// # KENAPA NOMOR CHANNEL IKUT DIJAGA
//
// Android MENGUNCI sound sebuah channel saat channel itu pertama kali dibuat.
// Mengganti berkas suara tanpa menaikkan id channel tidak mengubah apa pun di
// perangkat yang sudah memasang aplikasi — bunyinya tetap yang lama,
// selamanya.

String _sumberNotifikasi() =>
    File('lib/core/notifications.dart').readAsStringSync();

String _nilaiKonstanta(String sumber, String nama) {
  final m = RegExp("$nama\\s*=\\s*'([^']*)'").firstMatch(sumber);
  if (m == null) {
    fail('konstanta $nama tak ditemukan di notifications.dart');
  }
  return m.group(1)!;
}

void main() {
  late String sumber;
  setUpAll(() => sumber = _sumberNotifikasi());

  test('resource Android yang dideklarasikan BENAR-BENAR ada di res/raw', () {
    final nama = _nilaiKonstanta(sumber, '_customSoundResource');
    expect(nama, isNotEmpty);

    final raw = Directory('android/app/src/main/res/raw');
    expect(
      raw.existsSync(),
      isTrue,
      reason:
          'android/app/src/main/res/raw tidak ada — tak ada satu pun '
          'berkas suara yang ikut ter-bundle',
    );
    final cocok = raw
        .listSync()
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.split('.').first == nama)
        .toList();
    expect(
      cocok,
      isNotEmpty,
      reason:
          'res/raw tak punya berkas bernama "$nama" — Android akan jatuh ke '
          'nada default tanpa satu pun galat, dan itu hanya ketahuan dengan '
          'memasang aplikasi lalu mendengarkan',
    );
  });

  test('nama resource Android memenuhi aturan penamaan res/raw', () {
    // Android menolak nama dengan huruf besar atau tanda hubung saat
    // meng-compile resource — kegagalannya di build, tapi mudah terlewat
    // karena nama berkas aslinya memang "coin-drawer.mp3".
    final nama = _nilaiKonstanta(sumber, '_customSoundResource');
    expect(
      RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(nama),
      isTrue,
      reason:
          '"$nama" bukan nama resource yang sah (huruf kecil, angka, dan '
          'garis bawah saja)',
    );
  });

  group('iOS', () {
    test('berkas suara ada dan formatnya BUKAN mp3', () {
      final nama = _nilaiKonstanta(sumber, '_customSoundIosFile');
      expect(
        nama.toLowerCase().endsWith('.mp3'),
        isFalse,
        reason:
            'iOS HANYA menerima caf/aiff/wav untuk suara notifikasi. mp3 '
            'diabaikan diam-diam dan jatuh ke nada default — tak ada galat, '
            'tak ada peringatan',
      );
      expect(
        File('ios/Runner/$nama').existsSync(),
        isTrue,
        reason: 'ios/Runner/$nama tidak ada',
      );
    });

    test('berkasnya terdaftar di Copy Bundle Resources', () {
      // Ada di repo TIDAK berarti ikut ke dalam aplikasi. Tanpa entri di
      // pbxproj, berkasnya tertinggal dan iOS tak pernah menemukannya.
      final nama = _nilaiKonstanta(sumber, '_customSoundIosFile');
      final pbx = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      expect(
        pbx.contains('$nama in Resources'),
        isTrue,
        reason:
            '$nama tidak ada di Copy Bundle Resources — berkasnya ada di '
            'repo tapi tidak ikut ke dalam aplikasi',
      );
    });
  });

  test('channel dinaikkan versinya saat suara diganti', () {
    // v3 adalah channel dari masa nada default. Perangkat yang sudah
    // memasang aplikasi memegang channel itu beserta sound-nya yang terkunci;
    // memakai ulang id-nya berarti suara baru tak pernah terdengar di sana.
    final id = _nilaiKonstanta(sumber, '_fcmChannelId');
    expect(
      id,
      isNot('mako_fcm_v3'),
      reason:
          'channel masih v3 — perangkat lama tetap berbunyi nada default '
          'selamanya, karena Android mengunci sound saat channel dibuat',
    );
  });
}
