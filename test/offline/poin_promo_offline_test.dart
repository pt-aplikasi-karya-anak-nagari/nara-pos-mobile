import 'package:flutter_test/flutter_test.dart';

import 'package:nara_pos_mobile/features/discounts/data/promo_repository.dart';

// Kode promo saat offline: dinilai dari promo yang tersimpan di perangkat,
// dengan aturan yang sama dengan server.

Map<String, dynamic> _promo({
  String code = 'HEMAT',
  bool aktif = true,
  String? mulai,
  String? akhir,
  int? batas,
  int dipakai = 0,
  List<int> hari = const [],
  int? jamMulai,
  int? jamAkhir,
}) => {
  'code': code,
  'name': 'Promo Hemat',
  'scope': 'cart',
  'discount_type': 'fixed',
  'discount_value': 5000,
  'min_purchase_amount': 20000,
  'is_active': aktif,
  'starts_at': mulai,
  'ends_at': akhir,
  'usage_limit': batas,
  'usage_count': dipakai,
  'schedule_days_of_week': hari,
  'schedule_hour_start': jamMulai,
  'schedule_hour_end': jamAkhir,
};

void main() {
  // Kamis 29 Okt 2026, 14:00 waktu perangkat.
  final kini = DateTime(2026, 10, 29, 14);

  test('kode yang sah dikenali (huruf besar/kecil sama saja)', () {
    final p = validasiPromoOffline([_promo()], ' hemat ', kini);
    expect(p.code, 'HEMAT');
    expect(p.discountValue, 5000);
    expect(p.minPurchaseAmount, 20000);
  });

  test('kode tak dikenal / nonaktif / di luar tanggal ditolak', () {
    expect(
      () => validasiPromoOffline([_promo()], 'LAIN', kini),
      throwsA(isA<String>()),
    );
    expect(
      () => validasiPromoOffline([_promo(aktif: false)], 'HEMAT', kini),
      throwsA(isA<String>()),
    );
    expect(
      () => validasiPromoOffline(
        [_promo(akhir: '2026-10-28T00:00:00Z')],
        'HEMAT',
        kini,
      ),
      throwsA(isA<String>()),
    );
    expect(
      () => validasiPromoOffline(
        [_promo(mulai: '2026-11-01T00:00:00Z')],
        'HEMAT',
        kini,
      ),
      throwsA(isA<String>()),
    );
  });

  test('kuota habis ditolak', () {
    expect(
      () =>
          validasiPromoOffline([_promo(batas: 10, dipakai: 10)], 'HEMAT', kini),
      throwsA(isA<String>()),
    );
    expect(
      validasiPromoOffline([_promo(batas: 10, dipakai: 9)], 'HEMAT', kini).code,
      'HEMAT',
    );
  });

  test('hari & jam: penomoran hari server (Minggu = 0)', () {
    // Kamis = 4 di server.
    expect(
      validasiPromoOffline(
        [
          _promo(hari: [4]),
        ],
        'HEMAT',
        kini,
      ).code,
      'HEMAT',
    );
    expect(
      () => validasiPromoOffline(
        [
          _promo(hari: [0, 6]),
        ],
        'HEMAT',
        kini,
      ),
      throwsA(isA<String>()),
    );
    expect(
      validasiPromoOffline(
        [_promo(jamMulai: 13, jamAkhir: 15)],
        'HEMAT',
        kini,
      ).code,
      'HEMAT',
    );
    expect(
      () => validasiPromoOffline(
        [_promo(jamMulai: 17, jamAkhir: 20)],
        'HEMAT',
        kini,
      ),
      throwsA(isA<String>()),
    );
    // Melewati tengah malam: 22–02.
    expect(
      validasiPromoOffline(
        [_promo(jamMulai: 22, jamAkhir: 2)],
        'HEMAT',
        DateTime(2026, 10, 29, 23),
      ).code,
      'HEMAT',
    );
    expect(
      () => validasiPromoOffline(
        [_promo(jamMulai: 22, jamAkhir: 2)],
        'HEMAT',
        kini,
      ),
      throwsA(isA<String>()),
    );
  });
}
