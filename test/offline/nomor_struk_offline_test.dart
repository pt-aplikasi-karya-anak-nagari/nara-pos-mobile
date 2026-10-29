import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nara_pos_mobile/core/offline/nomor_struk_offline.dart';

// Struk offline dulu selalu bernomor "OFFLINE" — tak bisa dicocokkan ke
// transaksi di server, dan Pemilik tak bisa memeriksa apakah setiap struk yang
// tercetak benar-benar tercatat.

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  NomorStrukOffline nomor(String id) =>
      NomorStrukOffline(prefs, idPerangkat: () => id);

  test('format OFF-<kode perangkat>-<urut 5 digit>', () async {
    final n = nomor('3fa9c2e01b7d44aa9c0d1e2f3a4b5c6d');
    expect(await n.berikutnya(), 'OFF-3FA9C2-00001');
    expect(await n.berikutnya(), 'OFF-3FA9C2-00002');
  });

  test('urutan berlanjut setelah aplikasi dibuka ulang', () async {
    await nomor('3fa9c2aa').berikutnya();
    await nomor('3fa9c2aa').berikutnya();
    // Instans baru = aplikasi dibuka ulang; nomor tidak boleh mundur.
    expect(await nomor('3fa9c2aa').berikutnya(), 'OFF-3FA9C2-00003');
  });

  test('tak pernah ada dua struk bernomor sama', () async {
    final n = nomor('abcdef0123');
    final semua = <String>{};
    for (var i = 0; i < 50; i++) {
      expect(semua.add(await n.berikutnya()), isTrue);
    }
  });

  test('perangkat tanpa ID tetap mendapat nomor yang jelas tandanya', () async {
    expect(await nomor('').berikutnya(), 'OFF-TANPAID-00001');
  });
}
