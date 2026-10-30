import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/kasir/domain/batas_diskon.dart';

// Kasus yang sama dengan TestDiskonOrderKasir di server.
void main() {
  test('promo resmi & tukar poin bukan diskon kasir', () {
    expect(diskonOrderKasir(30000, diskonResmi: 30000), 0);
    expect(diskonOrderKasir(50000, diskonResmi: 30000), 20000);
    expect(diskonOrderKasir(5000, diskonResmi: 30000), 0);
    expect(diskonOrderKasir(40000), 40000);
  });

  test('promo 30% tak lagi melampaui batas 20% saat offline', () {
    // Keranjang Rp200.000 tanpa diskon baris → persen dari diskon order saja.
    const kotor = 200000.0;
    final persen = diskonOrderKasir(60000, diskonResmi: 60000) / kotor * 100;
    expect(melebihiBatasDiskon(persen, 20), isFalse);
    final ditambahKasir = diskonOrderKasir(120000, diskonResmi: 60000) / kotor * 100;
    expect(melebihiBatasDiskon(ditambahKasir, 20), isTrue);
  });
}
