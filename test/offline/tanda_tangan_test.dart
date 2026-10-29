import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nara_pos_mobile/core/offline/tanda_tangan.dart';

// Vektor bersama dengan nara-pos-be (internal/offlinecheck/tandatangan_test.go):
// isi kanonik dan tanda tangan perangkat harus persis sama dengan yang
// diverifikasi server.

const _payload = '''{
  "device_id": "3fa9c2e0-1b7d-44aa-9c0d-1e2f3a4b5c6d",
  "client_ref": "cr_1730170000000000_42",
  "offline_ref": "OFF-3FA9C2-00042",
  "occurred_at": "2026-10-29T03:15:00.123Z",
  "cashier_id": "22222222-2222-2222-2222-222222222222",
  "customer_id": "",
  "payment_method": "Tunai",
  "is_paid": true,
  "subtotal_amount": 45000,
  "discount_amount": 2500.4,
  "tax_amount": 4250.6,
  "service_charge": 0,
  "final_amount": 46750,
  "points_used": 0,
  "promo_code": "HEMAT",
  "items": [
    {"product_id": "PRD-1", "quantity": 2, "price": 15000, "base_price": 15000},
    {"product_id": "PRD-2", "variant_id": "VAR-9", "quantity": 1, "price": 15000.49, "base_price": 12000}
  ]
}''';

const _kanonik =
    'v1\n3fa9c2e0-1b7d-44aa-9c0d-1e2f3a4b5c6d\ncr_1730170000000000_42\nOFF-3FA9C2-00042\n'
    '2026-10-29T03:15:00.123Z\n22222222-2222-2222-2222-222222222222\n\nTunai\n1\n45000\n2500\n4251\n0\n46750\n0\nHEMAT\n'
    'PRD-1||2|15000|15000\nPRD-2|VAR-9|1|15000|12000';

const _pub = 'ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ=';
const _sig =
    'wkOnILw4IQgACY9pMIuBZ60sRAbYKutHMKVwPpn9LZXRRa88K4e4gi/VVvvMcGyZxFY4fvo12cLCUEcksGi5Ag==';

void main() {
  final payload = jsonDecode(_payload) as Map<String, dynamic>;
  final kunci = KunciTandaTangan(benih: List<int>.generate(32, (i) => i + 1));

  test('isi kanonik identik dengan server', () {
    expect(kanonikTransaksi(payload), _kanonik);
  });

  test('kunci & tanda tangan identik dengan server', () async {
    expect(await kunci.kunciPublik(), _pub);
    expect(await kunci.tandatangani(payload), _sig);
  });

  test(
    'field tambahan (struk lokal, jam kirim) tak memengaruhi tanda tangan',
    () async {
      final tambahan = {
        ...payload,
        'struk_lokal': {'cashier_name': 'Budi'},
        'jam_kirim': '2026-10-29T05:00:00Z',
      };
      expect(await kunci.tandatangani(tambahan), _sig);
    },
  );

  test('isi yang diubah tak lagi cocok', () async {
    final diubah = {...payload, 'final_amount': 6750};
    final sig = await kunci.tandatangani(diubah);
    final sah = await Ed25519().verify(
      utf8.encode(_kanonik),
      signature: Signature(
        base64Decode(sig),
        publicKey: SimplePublicKey(
          base64Decode(_pub),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    expect(sah, isFalse);
  });
}
