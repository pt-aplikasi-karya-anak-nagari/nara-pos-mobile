import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/core/config/app_config.dart';

/// Alamat untuk build rilis harus https dan bukan host lokal — supaya APK
/// yang sampai ke pelanggan tidak menunjuk ke laptop developer.
String? masalahAlamatRilis(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return 'bukan URL yang valid';
  if (uri.scheme != 'https') return 'harus https://, bukan ${uri.scheme}://';
  final h = uri.host;
  final lokal = h == 'localhost' ||
      h.endsWith('.local') ||
      h.endsWith('.localhost') ||
      RegExp(r'^(127|10)\.').hasMatch(h) ||
      RegExp(r'^192\.168\.').hasMatch(h) ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(h) ||
      RegExp(r'^169\.254\.').hasMatch(h);
  if (lokal) return 'host lokal/LAN ($h) tidak boleh dipakai di rilis';
  return null;
}

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
}
