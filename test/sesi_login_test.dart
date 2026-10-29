import 'package:flutter_test/flutter_test.dart';

import 'package:nara_pos_mobile/core/sesi_login.dart';

void main() {
  final kini = DateTime(2026, 10, 29, 12);

  test('masa berlaku sama dengan server: 7 hari', () {
    expect(masaBerlakuSesi, const Duration(days: 7));
    expect(
      sisaSesi(kini.subtract(const Duration(days: 3)), kini),
      const Duration(days: 4),
    );
    expect(sisaSesi(null, kini), isNull);
  });

  test('belum perlu diperingatkan bila sisa lebih dari 2 hari', () {
    expect(peringatanSesi(const Duration(days: 3)), isNull);
    expect(peringatanSesi(null), isNull);
  });

  test('hitung mundur dalam hari, jam, lalu menit', () {
    expect(
      peringatanSesi(const Duration(days: 1, hours: 5)),
      contains('1 hari'),
    );
    expect(peringatanSesi(const Duration(hours: 5)), contains('5 jam'));
    expect(peringatanSesi(const Duration(minutes: 20)), contains('20 menit'));
  });

  test('sudah berakhir: transaksi tetap aman, login ulang saat online', () {
    final p = peringatanSesi(const Duration(minutes: -5))!;
    expect(p, contains('sudah berakhir'));
    expect(p, contains('tetap tersimpan'));
  });
}
