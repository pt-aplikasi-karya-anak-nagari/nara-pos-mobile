import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/core/format.dart';

void main() {
  test('jatuh tempo dikirim dalam format server YYYY-MM-DD', () {
    expect(tanggalJatuhTempo(DateTime(2026, 11, 5)), '2026-11-05');
    expect(tanggalJatuhTempo(DateTime(2027, 1, 31, 23, 59)), '2027-01-31');
  });

  test('jatuh tempo ditampilkan dengan nama bulan Indonesia', () {
    expect(formatTanggalJatuhTempo(DateTime(2026, 8, 17)), '17 Agu 2026');
  });
}
