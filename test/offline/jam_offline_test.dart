import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nara_pos_mobile/core/offline/jam_offline.dart';
import 'package:nara_pos_mobile/features/settings/data/app_settings.dart';

// Batas lama offline & jam tablet yang dimundurkan: kasir yang dinonaktifkan
// selagi tablet offline tak boleh terus berjualan, dan memundurkan jam tak
// boleh memperpanjang batasnya.

void main() {
  late SharedPreferences prefs;
  late DateTime sekarang;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    sekarang = DateTime(2026, 10, 29, 12);
  });

  JamOffline jam() => JamOffline(prefs, sekarang: () => sekarang);

  test('belum pernah tersambung: tak ada yang dinilai', () {
    expect(jam().lamaOffline(), isNull);
    expect(melewatiBatasOffline(jam().lamaOffline(), 48), isFalse);
  });

  test('lama offline dihitung dari kontak terakhir dengan server', () async {
    await jam().catatOnline();
    sekarang = sekarang.add(const Duration(hours: 50));
    final lama = jam().lamaOffline();
    expect(lama, const Duration(hours: 50));
    expect(melewatiBatasOffline(lama, 48), isTrue);
    expect(melewatiBatasOffline(lama, 72), isFalse);
    expect(melewatiBatasOffline(lama, 0), isFalse, reason: '0 = tanpa batas');
  });

  test('memundurkan jam tak memperpendek lama offline', () async {
    await jam().catatOnline();
    sekarang = sekarang.add(const Duration(hours: 40));
    expect(await jam().amati(), isFalse);
    // Kasir memundurkan jam 1 hari supaya batas 48 jam tak tercapai.
    sekarang = sekarang.add(const Duration(hours: 10));
    sekarang = sekarang.subtract(const Duration(hours: 24));
    expect(await jam().amati(), isTrue, reason: 'jam mundur terdeteksi');
    // Acuan tetap jam terbesar yang pernah terlihat (40 jam), bukan jam
    // tablet yang sudah dimundurkan.
    expect(jam().lamaOffline(), const Duration(hours: 40));
  });

  test('pergeseran jam kecil (sinkron otomatis) bukan jam mundur', () async {
    await jam().amati();
    sekarang = sekarang.subtract(const Duration(minutes: 1));
    expect(await jam().amati(), isFalse);
  });

  test('tersambung lagi: hitungan & penanda mulai dari awal', () async {
    await jam().catatOnline();
    sekarang = sekarang.add(const Duration(hours: 60));
    expect(melewatiBatasOffline(jam().lamaOffline(), 48), isTrue);
    await jam().catatOnline();
    expect(jam().lamaOffline(), Duration.zero);
  });

  test('respons server beruntun tak menulis penyimpanan tiap kali', () async {
    await jam().catatOnline();
    final pertama = jam().terakhirOnline;
    sekarang = sekarang.add(const Duration(seconds: 5));
    await jam().catatOnline();
    expect(jam().terakhirOnline, pertama);
    sekarang = sekarang.add(JamOffline.jedaCatat);
    await jam().catatOnline();
    expect(jam().terakhirOnline, sekarang);
  });

  test('pesan untuk kasir menyebut lama & batasnya', () {
    expect(
      pesanBatasOffline(const Duration(hours: 50), 48),
      contains('2 hari'),
    );
    expect(
      pesanBatasOffline(const Duration(hours: 30), 24),
      contains('30 jam'),
    );
  });

  test('pengaturan outlet: batas offline dari server, 0 bila tak ada', () {
    expect(
      OutletAppSettings.fromJson({'max_offline_hours': 48}).maxOfflineHours,
      48,
    );
    expect(OutletAppSettings.fromJson({}).maxOfflineHours, 0);
    final st = OutletAppSettings.fromJson(
      const OutletAppSettings(maxOfflineHours: 24).toJson(),
    );
    expect(st.maxOfflineHours, 24, reason: 'bertahan di cache perangkat');
  });
}
