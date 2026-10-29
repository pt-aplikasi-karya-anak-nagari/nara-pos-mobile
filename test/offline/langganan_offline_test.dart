import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nara_pos_mobile/core/offline/jam_offline.dart';
import 'package:nara_pos_mobile/features/subscription/domain/subscription.dart';

// Langganan saat offline: server tak bisa menolak, jadi aplikasi yang menilai
// — dari status tersimpan & jam yang tak bisa dimundurkan.

OutletSubscription _sub({String? grace}) => OutletSubscription.fromJson({
  'id': 'SUB-1',
  'outlet_id': 'o1',
  'plan_code': 'pro',
  'status': 'active',
  'expires_at': '2026-10-31T00:00:00Z',
  'grace_until': ?grace,
  'feature_keys': ['modifiers', 'loyalty'],
});

void main() {
  test('boleh berjualan offline sampai akhir masa tenggang', () {
    final s = _sub(grace: '2026-11-03T00:00:00Z');
    expect(bolehJualOffline(s, DateTime.utc(2026, 11, 1)), isTrue);
    expect(bolehJualOffline(s, DateTime.utc(2026, 11, 2, 23)), isTrue);
    expect(bolehJualOffline(s, DateTime.utc(2026, 11, 3, 1)), isFalse);
  });

  test('server lama tanpa grace_until: tenggang bawaan 3 hari', () {
    final s = _sub();
    expect(batasJualOffline(s), DateTime.utc(2026, 11, 3).toLocal());
  });

  test('fitur paket ikut tersimpan', () {
    expect(_sub().featureKeys, ['modifiers', 'loyalty']);
  });

  test('batas offline platform: pemilik tak bisa melonggarkan', () {
    expect(batasOfflineEfektif(0), 168, reason: '"tanpa batas" lama');
    expect(batasOfflineEfektif(500), 168);
    expect(batasOfflineEfektif(48), 48);
  });

  group('jam acuan', () {
    late SharedPreferences prefs;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test(
      'jam tablet dimundurkan tak menghidupkan langganan yang habis',
      () async {
        var kini = DateTime(2026, 11, 5, 10);
        final jam = JamOffline(prefs, sekarang: () => kini);
        await jam.catatJamServer(DateTime(2026, 11, 5, 10));
        // Kasir memundurkan jam tablet ke sebelum langganan berakhir.
        kini = DateTime(2026, 10, 30);
        expect(jam.waktuAcuan(), DateTime(2026, 11, 5, 10));
        expect(
          bolehJualOffline(
            _sub(grace: '2026-11-03T00:00:00Z'),
            jam.waktuAcuan(),
          ),
          isFalse,
        );
      },
    );

    test('jam server hanya maju', () async {
      final jam = JamOffline(prefs, sekarang: () => DateTime(2026, 11, 1));
      await jam.catatJamServer(DateTime(2026, 11, 5));
      await jam.catatJamServer(DateTime(2026, 11, 2));
      expect(jam.jamServerTerakhir, DateTime(2026, 11, 5));
    });

    test('tanpa catatan apa pun: jam tablet', () {
      final jam = JamOffline(prefs, sekarang: () => DateTime(2026, 11, 1));
      expect(jam.waktuAcuan(), DateTime(2026, 11, 1));
    });
  });
}
