import 'package:flutter_test/flutter_test.dart';

import 'package:nara_pos_mobile/core/offline/sinkron_latar.dart';

// Sinkron latar belakang: hanya saat aplikasi tak di layar dan ada sesi sah.

void main() {
  final kini = DateTime(2026, 10, 29, 12);
  int ms(DateTime t) => t.millisecondsSinceEpoch;

  test('aplikasi tertutup & ada sesi → jalan', () {
    expect(
      perluSinkronLatar(
        latarDepanPadaMs: null,
        adaToken: true,
        sesiOffline: false,
        kini: kini,
      ),
      isTrue,
    );
  });

  test('aplikasi sedang di layar → dilewati, aplikasi menyinkron sendiri', () {
    expect(
      perluSinkronLatar(
        latarDepanPadaMs: ms(kini.subtract(const Duration(minutes: 20))),
        adaToken: true,
        sesiOffline: false,
        kini: kini,
      ),
      isFalse,
    );
  });

  test('penanda layar basi (aplikasi dimatikan paksa) → jalan', () {
    expect(
      perluSinkronLatar(
        latarDepanPadaMs: ms(kini.subtract(const Duration(hours: 7))),
        adaToken: true,
        sesiOffline: false,
        kini: kini,
      ),
      isTrue,
    );
  });

  test('tanpa token, atau sesi offline belum diverifikasi → dilewati', () {
    expect(
      perluSinkronLatar(
        latarDepanPadaMs: null,
        adaToken: false,
        sesiOffline: false,
        kini: kini,
      ),
      isFalse,
    );
    expect(
      perluSinkronLatar(
        latarDepanPadaMs: null,
        adaToken: true,
        sesiOffline: true,
        kini: kini,
      ),
      isFalse,
    );
  });
}
