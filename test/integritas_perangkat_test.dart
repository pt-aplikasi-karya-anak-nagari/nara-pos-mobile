import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/core/keamanan/integritas_perangkat.dart';

void main() {
  const sertifikat = 'AB:CD:EF:01';

  group('keputusanIntegritas', () {
    test('build debug/profile tidak pernah diblokir', () {
      const h = HasilIntegritas(root: ['su:/system/bin/su'], hook: ['maps:frida'], debugger: true);
      expect(keputusanIntegritas(h, rilis: false), isEmpty);
    });

    test('perangkat bersih lolos', () {
      expect(keputusanIntegritas(HasilIntegritas.aman, rilis: true), isEmpty);
    });

    test('root diblokir, kecuali diizinkan', () {
      const h = HasilIntegritas(root: ['paket:com.topjohnwu.magisk']);
      expect(keputusanIntegritas(h, rilis: true), [AlasanTolak.root]);
      expect(keputusanIntegritas(h, rilis: true, izinkanRoot: true), isEmpty);
    });

    test('hooking & debugger selalu diblokir di rilis', () {
      expect(
        keputusanIntegritas(const HasilIntegritas(hook: ['thread:gum-js-loop']), rilis: true),
        [AlasanTolak.hook],
      );
      expect(
        keputusanIntegritas(const HasilIntegritas(debugger: true), rilis: true, izinkanRoot: true),
        [AlasanTolak.debugger],
      );
    });

    test('emulator & sinyal lemah hanya dicatat', () {
      const h = HasilIntegritas(emulator: ['hardware:ranchu'], lemah: ['build:test-keys']);
      expect(keputusanIntegritas(h, rilis: true), isEmpty);
    });

    test('APK dirakit ulang: sertifikat beda atau ditandai dapat di-debug', () {
      expect(
        keputusanIntegritas(
          const HasilIntegritas(sertifikatSha256: '00112233'),
          rilis: true,
          sertifikatResmi: sertifikat,
        ),
        [AlasanTolak.apkDiubah],
      );
      expect(
        keputusanIntegritas(const HasilIntegritas(dapatDidebug: true), rilis: true),
        [AlasanTolak.apkDiubah],
      );
    });

    test('sertifikat sama (beda format) lolos; tanpa sertifikat resmi dilewati', () {
      expect(
        keputusanIntegritas(
          const HasilIntegritas(sertifikatSha256: 'abcdef01'),
          rilis: true,
          sertifikatResmi: sertifikat,
        ),
        isEmpty,
      );
      expect(
        keputusanIntegritas(const HasilIntegritas(sertifikatSha256: '00'), rilis: true),
        isEmpty,
      );
    });
  });

  test('HasilIntegritas.dariMap membaca hasil kanal native', () {
    final h = HasilIntegritas.dariMap({
      'root': ['su:/sbin/su'],
      'hook': <Object?>[],
      'debugger': true,
      'dapat_didebug': false,
      'sertifikat_sha256': 'AA',
    });
    expect(h.root, ['su:/sbin/su']);
    expect(h.hook, isEmpty);
    expect(h.debugger, isTrue);
    expect(h.sertifikatSha256, 'AA');
  });
}
