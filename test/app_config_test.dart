import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/core/config/app_config.dart';

// masalahAlamatRilis ada di lib/core/config/app_config.dart (dipakai juga
// AppConfig.assertValid). scripts/build_prod menjalankan berkas ini dengan
// --dart-define-from-file=env/prod.json, jadi yang diperiksa adalah alamat
// yang benar-benar masuk ke APK rilis.

void main() {
  group('AppConfig rilis', () {
    test('secret rilis tidak ditulis di repo (disuntik --dart-define)', () {
      // Tanpa --dart-define, rilis harus kosong -> app menolak start.
      expect(AppConfig.apiSecretRilis, isEmpty);
      expect(AppConfig.apiSecret, AppConfig.apiSecretDev);
    });

    test('apiHostRilis https & bukan host lokal', () {
      expect(masalahAlamatRilis(AppConfig.apiHostRilis), isNull);
    });

    test('makoScanQrBaseUrlRilis https & bukan host lokal (atau kosong)', () {
      if (AppConfig.makoScanQrBaseUrlRilis.isEmpty) return;
      expect(masalahAlamatRilis(AppConfig.makoScanQrBaseUrlRilis), isNull);
    });

    test('tanpa trailing slash', () {
      expect(AppConfig.apiHostRilis.endsWith('/'), isFalse);
      expect(AppConfig.apiHostDev.endsWith('/'), isFalse);
    });
  });

  group('masalahAlamatRilis', () {
    test('menolak alamat dev yang umum', () {
      for (final url in [
        'http://api.nara.id',
        'https://localhost:3001',
        'https://127.0.0.1:3001',
        'https://10.186.235.87:3001',
        'https://192.168.1.25:3001',
        'https://172.25.63.73:3001',
        '',
      ]) {
        expect(masalahAlamatRilis(url), isNotNull, reason: url);
      }
    });

    test('menerima domain publik https', () {
      expect(masalahAlamatRilis('https://api.nara.id'), isNull);
      expect(masalahAlamatRilis('https://172.15.0.1'), isNull);
    });
  });

  group('berkas env', () {
    const kunci = ['NARA_API_HOST', 'NARA_WEB_URL', 'NARA_MENU_QR_URL'];
    Map<String, dynamic> baca(String path) =>
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

    test('env/prod.json lengkap, https, bukan host lokal', () {
      final env = baca('env/prod.json');
      expect(env.keys, containsAll(kunci));
      for (final k in kunci) {
        expect(masalahAlamatRilis(env[k] as String), isNull, reason: k);
        expect((env[k] as String).endsWith('/'), isFalse, reason: k);
      }
      // Rahasia tidak boleh ikut di berkas yang di-commit.
      expect(env.keys.where((k) => k.contains('SECRET')), isEmpty);
    });

    test('env/dev.example.json memuat kunci yang sama', () {
      final env = baca('env/dev.example.json');
      expect(env.keys, containsAll(kunci));
      expect(env.keys.where((k) => k.contains('SECRET')), isEmpty);
    });
  });
}
