import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nara_pos_mobile/core/network/dio_client.dart';
import 'package:nara_pos_mobile/core/offline/sesi_offline.dart';
import 'package:nara_pos_mobile/features/shifts/data/shift_repository.dart';
import 'package:nara_pos_mobile/features/shifts/domain/shift.dart';
import 'package:nara_pos_mobile/features/user/data/auth_api_service.dart';

// Ganti kasir saat tablet offline: kartu & PIN dicocokkan di perangkat.

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

StaffCandidate _staf(String id, {List<String> kartu = const []}) =>
    StaffCandidate(
      id: id,
      fullName: 'Staf $id',
      role: 'Kasir',
      hasPin: true,
      kartuOffline: kartu,
    );

void main() {
  test('sidik kartu sama persis dengan server (vektor bersama)', () {
    // Vektor yang sama diuji di nara-pos-be (logincard/token_test.go).
    expect(
      sidikKartu('NPCARD1:${'ab' * 32}'),
      'fa29a46ad25ff1807cfb3f1a0a93594ef01684f8778248b8fb25bab96619600c',
    );
    // Spasi/baris baru dari pemindai tak membuat kartu ditolak.
    expect(
      sidikKartu('  NPCARD1:${'ab' * 32}\n'),
      sidikKartu('NPCARD1:${'ab' * 32}'),
    );
  });

  test('PBKDF2-HMAC-SHA256 sesuai vektor RFC 7914', () {
    expect(
      _hex(pbkdf2(utf8.encode('passwd'), utf8.encode('salt'), 1, 32)),
      '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc',
    );
  });

  test('sidik PIN: cocok untuk PIN yang benar saja', () async {
    final s = await SidikPin.buat('482913', iterasi: 10);
    expect(await s.cocok('482913'), isTrue);
    expect(await s.cocok('482914'), isFalse);
    expect(
      s.toJson().toString(),
      isNot(contains('482913')),
      reason: 'PIN tak tersimpan mentah',
    );
  });

  test('PIN salah 5x mengunci, makin lama makin panjang', () {
    final kini = DateTime(2026, 10, 29, 10);
    var k = const KunciPin();
    for (var i = 0; i < 4; i++) {
      k = k.salah(kini);
      expect(k.terkunci(kini), isFalse);
    }
    k = k.salah(kini);
    expect(k.terkunci(kini), isTrue);
    expect(k.sampai, kini.add(const Duration(minutes: 5)));
    expect(k.terkunci(kini.add(const Duration(minutes: 6))), isFalse);
    for (var i = 0; i < 5; i++) {
      k = k.salah(kini);
    }
    expect(k.sampai, kini.add(const Duration(minutes: 10)));
  });

  test(
    'daftar staf baru: sidik PIN dipertahankan, staf yang keluar ikut hilang',
    () async {
      final pin = await SidikPin.buat('1234', iterasi: 5);
      final lama = [
        KasirTersimpan(id: 'a', nama: 'A', role: 'Kasir', pin: pin),
        const KasirTersimpan(id: 'b', nama: 'B', role: 'Kasir'),
      ];
      final baru = gabungDaftarStaf([_staf('a'), _staf('c')], lama);
      expect(baru.map((k) => k.id), ['a', 'c']);
      expect(baru.first.pin, isNotNull);
      expect(baru.last.pin, isNull);
    },
  );

  group('SesiOfflineStore', () {
    late SesiOfflineStore store;
    late DateTime kini;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      kini = DateTime(2026, 10, 29, 10);
      store = SesiOfflineStore(
        await SharedPreferences.getInstance(),
        kini: () => kini,
      );
      await store.simpanDaftar('o1', [
        _staf('a', kartu: [sidikKartu('NPCARD1:${'cd' * 32}')]),
        _staf('b'),
      ]);
    });

    test('kartu dikenali tanpa server; kartu lain ditolak', () async {
      expect((await store.masukKartu('o1', 'NPCARD1:${'cd' * 32}'))?.id, 'a');
      expect(await store.masukKartu('o1', 'NPCARD1:${'ef' * 32}'), isNull);
      expect(
        await store.masukKartu('o2', 'NPCARD1:${'cd' * 32}'),
        isNull,
        reason: 'per outlet',
      );
    });

    test('PIN yang belum pernah dipakai online tak bisa diperiksa', () async {
      expect(await store.masukPin('o1', 'b', '1234'), isA<PinBelumTersimpan>());
    });

    test(
      'PIN yang pernah diterima server bisa dipakai offline, dengan kunci',
      () async {
        await store.simpanPin('o1', 'a', '246810');
        expect(await store.masukPin('o1', 'a', '246810'), isA<PinBenar>());
        for (var i = 0; i < 4; i++) {
          expect(await store.masukPin('o1', 'a', '000000'), isA<PinSalah>());
        }
        expect(await store.masukPin('o1', 'a', '000000'), isA<PinTerkunci>());
        // Terkunci: PIN yang benar pun ditolak sampai waktunya lewat.
        expect(await store.masukPin('o1', 'a', '246810'), isA<PinTerkunci>());
        kini = kini.add(const Duration(minutes: 6));
        expect(await store.masukPin('o1', 'a', '246810'), isA<PinBenar>());
      },
    );
  });

  test('shift kasir lain tak diwarisi kasir yang masuk offline', () {
    Shift s(String kasir) => Shift(
      startTime: DateTime(2026),
      startingCash: 0,
      cashierName: '',
      cashierRemoteId: kasir,
    );
    expect(shiftMilik(s('kasir-A'), 'kasir-A'), isTrue);
    expect(shiftMilik(s('kasir-A'), 'kasir-B'), isFalse);
    expect(
      shiftMilik(s(''), 'kasir-B'),
      isTrue,
      reason: 'cache lama tanpa pemilik',
    );
  });

  test('sesi offline: hanya verifikasi ulang yang boleh ke server', () {
    expect(bolehSaatSesiOffline('/staff-session/resume'), isTrue);
    expect(bolehSaatSesiOffline('/staff-session/verify'), isTrue);
    expect(bolehSaatSesiOffline('/transactions/checkout/o1'), isFalse);
    expect(bolehSaatSesiOffline('/staff-session/start'), isFalse);
  });
}
