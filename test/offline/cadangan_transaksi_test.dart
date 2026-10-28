import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nara_pos_mobile/core/offline/folder_offline.dart';
import 'package:nara_pos_mobile/core/offline/product_folder_store.dart';
import 'package:nara_pos_mobile/core/offline/transaksi_folder.dart';

// Cadangan transaksi offline di folder pilihan: harus selamat walau aplikasi
// dihapus sebelum transaksinya sampai ke server.

class _Folder implements FolderBackend {
  final Map<String, Map<String, String>> isi = {};

  @override
  bool get didukung => true;
  @override
  Future<bool> punyaAkses(String uri) async => true;
  @override
  Future<void> tulis(
    String uri,
    List<String> dir,
    String nama,
    String data,
  ) async => (isi[dir.join('/')] ??= {})[nama] = data;
  @override
  Future<Map<String, String>> bacaSemua(String uri, List<String> dir) async =>
      Map.of(isi[dir.join('/')] ?? const {});
  @override
  Future<List<String>> daftarNama(String uri, List<String> dir) async =>
      (isi[dir.join('/')] ?? const {}).keys.toList();
  @override
  Future<bool> hapus(String uri, List<String> dir, String nama) async =>
      isi[dir.join('/')]?.remove(nama) != null;
}

/// Antrian palsu di memori — pengganti tabel pending_sales & pending_ops.
class _Antrian implements SumberAntrian {
  final Map<String, Map<String, Object?>> penjualan = {};
  final Map<String, Map<String, Object?>> shift = {};

  @override
  Future<List<Map<String, Object?>>> semuaPenjualan() async =>
      penjualan.values.toList();
  @override
  Future<List<Map<String, Object?>>> semuaOpShift() async =>
      shift.values.toList();
  @override
  Future<int> sisipkanPenjualan(List<Map<String, Object?>> baris) async =>
      _sisip(penjualan, baris);
  @override
  Future<int> sisipkanOpShift(List<Map<String, Object?>> baris) async =>
      _sisip(shift, baris);

  int _sisip(
    Map<String, Map<String, Object?>> t,
    List<Map<String, Object?>> b,
  ) {
    var n = 0;
    for (final r in b) {
      final id = r['local_id'] as String;
      if (t.containsKey(id)) continue;
      t[id] = r;
      n++;
    }
    return n;
  }
}

Map<String, Object?> _jual(
  String id, {
  String outlet = 'o1',
  num total = 13200,
  String? pin,
}) => {
  'local_id': id,
  'outlet_id': outlet,
  'payload': jsonEncode({
    'client_ref': 'cr_$id',
    'final_amount': total,
    'override_pin': ?pin,
  }),
  'created_at': '2026-10-29T06:02:00',
  'attempts': 0,
  'last_error': null,
};

Map<String, Object?> _bukaShift(String id, {String outlet = 'o1'}) => {
  'local_id': id,
  'op_type': 'shift_open',
  'outlet_id': outlet,
  'client_ref': 'open_$id',
  'payload': jsonEncode({'start_balance': 100000}),
  'local_shift_id': 'ls_1',
  'status': 'pending',
  'created_at': '2026-10-29T05:00:00',
  'attempts': 0,
};

void main() {
  late _Folder folder;
  late _Antrian antrian;
  late CerminTransaksiOffline cermin;

  Future<CerminTransaksiOffline> cerminBaru(_Antrian a) async =>
      CerminTransaksiOffline(ProductFolderStore(folder), a);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    folder = _Folder();
    antrian = _Antrian();
    cermin = await cerminBaru(antrian);
  });

  test('transaksi offline langsung tersalin ke folder outletnya', () async {
    antrian.penjualan['offline_1'] = _jual('offline_1');
    antrian.shift['op_1'] = _bukaShift('op_1');
    await cermin.jadwalkan();

    expect(folder.isi['outlet-o1/transaksi-offline']!.keys, ['offline_1.json']);
    expect(folder.isi['outlet-o1/shift-offline']!.keys, ['op_1.json']);
    final data = jsonDecode(
      folder.isi['outlet-o1/transaksi-offline']!['offline_1.json']!,
    );
    expect(jsonDecode(data['baris']['payload'])['final_amount'], 13200);
  });

  test('PIN manajer tidak ikut ditulis ke folder', () async {
    antrian.penjualan['offline_1'] = _jual('offline_1', pin: '123456');
    await cermin.jadwalkan();

    final isi = folder.isi['outlet-o1/transaksi-offline']!['offline_1.json']!;
    expect(isi.contains('123456'), isFalse);
    expect(isi.contains('override_pin'), isFalse);
  });

  test(
    'setelah install ulang: antrian kosong TIDAK menghapus cadangan',
    () async {
      antrian.penjualan['offline_1'] = _jual('offline_1');
      await cermin.jadwalkan();

      // Install ulang: antrian & memori kosong, folder tetap.
      final antrianBaru = _Antrian();
      final cerminBaru2 = await cerminBaru(antrianBaru);
      await cerminBaru2.jadwalkan(); // mis. transaksi baru masuk sebelum pulih
      expect(folder.isi['outlet-o1/transaksi-offline']!.keys, [
        'offline_1.json',
      ], reason: 'satu-satunya salinan transaksi yang belum terkirim');

      final hasil = await cerminBaru2.pulihkan('o1');
      expect(hasil.penjualan, 1);
      expect(antrianBaru.penjualan.keys, ['offline_1']);
    },
  );

  test('terkirim ke server → filenya dihapus (setelah pulih)', () async {
    antrian.penjualan['offline_1'] = _jual('offline_1');
    antrian.penjualan['offline_2'] = _jual('offline_2');
    await cermin.pulihkan('o1');
    expect(folder.isi['outlet-o1/transaksi-offline']!.length, 2);

    antrian.penjualan.remove('offline_1'); // diterima server
    await cermin.jadwalkan();
    expect(folder.isi['outlet-o1/transaksi-offline']!.keys, ['offline_2.json']);
  });

  test('pemulihan tidak menimpa antrian yang sudah ada', () async {
    antrian.penjualan['offline_1'] = _jual('offline_1', total: 5000);
    await cermin.jadwalkan();

    final a2 = _Antrian()
      ..penjualan['offline_1'] = _jual('offline_1', total: 9999);
    final c2 = await cerminBaru(a2);
    final hasil = await c2.pulihkan('o1');
    expect(hasil.penjualan, 0);
    expect(
      jsonDecode(
        a2.penjualan['offline_1']!['payload'] as String,
      )['final_amount'],
      9999,
    );
  });

  test('hanya outlet yang login yang dipulihkan', () async {
    antrian.penjualan['a'] = _jual('a', outlet: 'o1');
    antrian.penjualan['b'] = _jual('b', outlet: 'o2');
    await cermin.jadwalkan();

    final a2 = _Antrian();
    final c2 = await cerminBaru(a2);
    await c2.pulihkan('o1');
    expect(a2.penjualan.keys, ['a']);

    // File outlet lain tak tersentuh walau tak ada di antrian.
    await c2.jadwalkan();
    expect(folder.isi['outlet-o2/transaksi-offline']!.keys, ['b.json']);
  });

  test('buka shift offline ikut dipulihkan bersama penjualannya', () async {
    antrian.shift['op_1'] = _bukaShift('op_1');
    antrian.penjualan['offline_1'] = _jual('offline_1');
    await cermin.jadwalkan();

    final a2 = _Antrian();
    final hasil = await (await cerminBaru(a2)).pulihkan('o1');
    expect(hasil.shift, 1);
    expect(hasil.penjualan, 1);
    expect(a2.shift['op_1']!['client_ref'], 'open_op_1');
  });

  test('file rusak dilewati, yang lain tetap dipulihkan', () async {
    antrian.penjualan['offline_1'] = _jual('offline_1');
    await cermin.jadwalkan();
    folder.isi['outlet-o1/transaksi-offline']!['rusak.json'] = '{bukan json';

    final a2 = _Antrian();
    final hasil = await (await cerminBaru(a2)).pulihkan('o1');
    expect(hasil.penjualan, 1);
  });
}
