import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nara_pos_mobile/core/offline/offline_sync_service.dart';

void main() {
  late ProviderContainer c;
  ProgresSinkronNotifier n() => c.read(progresSinkronProvider.notifier);
  ProgresSinkron s() => c.read(progresSinkronProvider);

  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('mulai → maju → selesai', () {
    n().mulai(4);
    expect(s().berjalan, isTrue);
    expect(s().total, 4);

    n().sedangMengirim('offline_1');
    expect(s().sedangDikirim, 'offline_1');
    n().maju();
    n().maju(gagal: true);
    expect(s().terkirim, 1);
    expect(s().gagal, 1);
    expect(s().rasio, 0.5);

    n().selesai(terkirim: 1, gagal: 1, terhentiOffline: false);
    expect(s().berjalan, isFalse);
    expect(s().terkirimTerakhir, 1);
    expect(s().gagalTerakhir, 1);
    expect(s().selesaiPada, isNotNull);
  });

  test('maju tanpa mulai diabaikan (antrian kosong)', () {
    n().maju();
    expect(s().terkirim, 0);
    expect(s().berjalan, isFalse);
  });

  test('selesai tanpa hasil tidak menimpa hasil sebelumnya', () {
    n().mulai(2);
    n().maju();
    n().maju();
    n().selesai(terkirim: 2, gagal: 0, terhentiOffline: false);
    final waktu = s().selesaiPada;

    // Percobaan berikutnya langsung terhenti karena offline.
    n().selesai(terkirim: 0, gagal: 0, terhentiOffline: true);
    expect(s().selesaiPada, waktu);
    expect(s().terkirimTerakhir, 2);
    expect(s().terhentiOffline, isTrue);
  });

  test('rasio tak pernah melebihi 1', () {
    n().mulai(1);
    n().maju();
    n().maju();
    expect(s().rasio, 1);
  });
}
