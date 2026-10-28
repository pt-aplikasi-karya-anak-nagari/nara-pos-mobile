import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/core/offline/folder_offline.dart';
import 'package:nara_pos_mobile/core/offline/product_folder_store.dart';
import 'package:nara_pos_mobile/core/offline/product_offline_sync.dart';
import 'package:nara_pos_mobile/features/outlet/data/outlet_service.dart';
import 'package:nara_pos_mobile/features/products/domain/product.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Folder palsu di memori: path "a/b" → (nama file → isi).
class FolderPalsu implements FolderBackend {
  final Map<String, Map<String, String>> isi = {};
  String? uriDipilih = 'content://tree/narapos';
  bool akses = true;
  int jumlahTulis = 0;
  Object? galatTulis;

  @override
  bool get didukung => true;

  @override
  Future<String?> pilihFolder() async => uriDipilih;

  @override
  Future<bool> punyaAkses(String uri) async => akses;

  @override
  Future<String?> namaFolder(String uri) async => 'NaraPOS';

  @override
  Future<void> tulis(
    String uri,
    List<String> dir,
    String nama,
    String data,
  ) async {
    if (galatTulis != null) throw galatTulis!;
    jumlahTulis++;
    (isi[dir.join('/')] ??= {})[nama] = data;
  }

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

Product produk(String id, {String? nama, double harga = 10000}) =>
    Product(remoteId: id, name: nama ?? 'Produk $id', price: harga);

void main() {
  late FolderPalsu folder;
  late ProductFolderStore store;

  Future<ProductFolderStore> storeBaru() async {
    final prefs = await SharedPreferences.getInstance();
    return ProductFolderStore(prefs, folder);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    folder = FolderPalsu();
    store = await storeBaru();
  });

  group('ProductFolderStore', () {
    test('tanpa folder dipilih tidak menulis apa pun', () async {
      expect(await store.simpan('o1', [produk('p1')]), 0);
      expect(folder.jumlahTulis, 0);
    });

    test('satu file per produk, di folder outlet masing-masing', () async {
      await store.pilihFolder();
      await store.simpan('o1', [produk('p1'), produk('p2')]);
      await store.simpan('o2', [produk('p9')]);

      expect(
        folder.isi['outlet-o1/produk']!.keys,
        unorderedEquals(['p1.json', 'p2.json']),
      );
      expect(folder.isi['outlet-o2/produk']!.keys, ['p9.json']);

      final data = jsonDecode(folder.isi['outlet-o1/produk']!['p1.json']!);
      expect(data['outlet_id'], 'o1');
      expect(data['produk']['name'], 'Produk p1');
    });

    test('produk yang tidak berubah tidak ditulis ulang', () async {
      await store.pilihFolder();
      await store.simpan('o1', [produk('p1'), produk('p2')]);
      expect(folder.jumlahTulis, 2);

      await store.simpan('o1', [produk('p1'), produk('p2', harga: 12000)]);
      expect(folder.jumlahTulis, 3, reason: 'hanya p2 yang berubah');
    });

    test(
      'setelah install ulang: pilih folder yang sama, produk terbaca lagi',
      () async {
        await store.pilihFolder();
        await store.simpan('o1', [
          produk('p1', nama: 'Kopi'),
          produk('p2', nama: 'Air'),
        ]);
        await store.simpan('o2', [produk('p9')]);

        // Install ulang: SharedPreferences & memori kosong, folder tetap ada.
        SharedPreferences.setMockInitialValues({});
        final baru = await storeBaru();
        expect(
          await baru.muat('o1'),
          isEmpty,
          reason: 'folder belum dipilih lagi',
        );

        await baru.pilihFolder();
        final hasil = await baru.muat('o1');
        expect(hasil.map((p) => p.name), ['Air', 'Kopi']);
        expect(hasil.map((p) => p.remoteId), isNot(contains('p9')));
      },
    );

    test('file rusak atau milik outlet lain dilewati', () async {
      await store.pilihFolder();
      await store.simpan('o1', [produk('p1')]);
      final dir = folder.isi['outlet-o1/produk']!;
      dir['rusak.json'] = '{bukan json';
      dir['nyasar.json'] = jsonEncode({
        'outlet_id': 'o2',
        'produk': produk('px').toJson(),
      });

      final hasil = await store.muat('o1');
      expect(hasil.map((p) => p.remoteId), ['p1']);
    });

    test('idTersimpan mengikuti file di folder, per outlet', () async {
      expect(
        await store.idTersimpan('o1'),
        isEmpty,
        reason: 'belum ada folder',
      );

      await store.pilihFolder();
      await store.simpan('o1', [produk('p1'), produk('p2')]);
      await store.simpan('o2', [produk('p9')]);
      expect(await store.idTersimpan('o1'), {'p1', 'p2'});

      await store.pangkas('o1', {'p2'});
      expect(await store.idTersimpan('o1'), {'p2'});
      expect(await store.idTersimpan('o2'), {'p9'});
    });

    test('idTersimpan setelah install ulang dibaca dari daftar file', () async {
      await store.pilihFolder();
      await store.simpan('o1', [produk('p1'), produk('p2')]);

      SharedPreferences.setMockInitialValues({});
      final baru = await storeBaru();
      await baru.pilihFolder();
      expect(await baru.idTersimpan('o1'), {'p1', 'p2'});
    });

    test(
      'perubahan dipancarkan saat produk ditulis atau folder diganti',
      () async {
        final event = <String>[];
        final sub = store.perubahan.listen(event.add);
        await store.pilihFolder();
        await store.simpan('o1', [produk('p1')]);
        await store.simpan('o1', [produk('p1')]); // tidak berubah → diam
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(event, ['*', 'o1']);
      },
    );

    test('pangkas membuang produk yang sudah tidak ada di server', () async {
      await store.pilihFolder();
      await store.simpan('o1', [produk('p1'), produk('p2'), produk('p3')]);
      expect(await store.pangkas('o1', {'p1', 'p3'}), 1);
      expect(await store.jumlah('o1'), 2);

      // p2 kembali → ditulis lagi, bukan dianggap "tidak berubah".
      await store.simpan('o1', [produk('p2')]);
      expect(await store.jumlah('o1'), 3);
    });

    test('izin folder hilang: dianggap belum dipilih', () async {
      await store.pilihFolder();
      folder.akses = false;
      expect(await store.aktif(), isFalse);
      expect(await store.simpan('o1', [produk('p1')]), 0);
    });

    test('galat menulis dicatat, tidak dilempar', () async {
      await store.pilihFolder();
      folder.galatTulis = PlatformException(
        code: 'NO_ACCESS',
        message: 'Akses hilang',
      );
      expect(await store.simpan('o1', [produk('p1')]), 0);
      expect(store.galatTerakhir, 'Akses hilang');
    });

    test('id dengan karakter path tidak bisa keluar dari folder outlet', () {
      expect(ProductFolderStore.namaFile('../x/y'), '___x_y.json');
      expect(ProductFolderStore.dirProduk('a/b'), ['outlet-a_b', 'produk']);
    });
  });

  group('VersiKatalogServer.dari', () {
    test('bentuk baru: tidak berubah', () {
      final v = VersiKatalogServer.dari({
        'catalog_version': 42,
        'unchanged': true,
        'items': <Object>[],
      });
      expect(v.versiKatalog, 42);
      expect(v.tidakBerubah, isTrue);
      expect(v.items, isEmpty);
    });

    test('bentuk baru: berubah, berisi versi produk', () {
      final v = VersiKatalogServer.dari({
        'catalog_version': 43,
        'unchanged': false,
        'items': [
          {'id': 'p1', 'version': 'a'},
          {'id': 'p2', 'version': 'b'},
        ],
      });
      expect(v.tidakBerubah, isFalse);
      expect(v.items, {'p1': 'a', 'p2': 'b'});
    });

    test('server lama: daftar polos → versi katalog 0', () {
      final v = VersiKatalogServer.dari([
        {'id': 'p1', 'version': 'a'},
      ]);
      expect(v.versiKatalog, 0);
      expect(v.tidakBerubah, isFalse);
      expect(v.items, {'p1': 'a'});
    });
  });

  group('ProductOfflineSync — flag per produk', () {
    // Server palsu: versi tiap produk + versi katalog outlet. Tes yang mengubah
    // produk di server memanggil ubahServer() supaya versi katalog ikut naik,
    // persis seperti trigger di database.
    late Map<String, String> versiServer;
    late int versiKatalogServer;
    late bool serverKenalVersiKatalog;
    late bool punyaEndpointVersi;
    int? gagalAmbilKe;

    // Perangkat palsu.
    late Map<String, String> lokal; // id → versi lokal
    late Map<String, bool> flag; // id → tersimpan
    late bool lengkap;
    late int versiKatalogLokal;

    late List<String> log;

    void ubahServer(void Function() ubah) {
      ubah();
      versiKatalogServer++;
    }

    Product produkServer(String id) =>
        Product(remoteId: id, name: id, price: 1, version: versiServer[id]!);

    ProductOfflineSync buat({DateTime Function()? jam}) {
      var panggilanAmbil = 0;
      return ProductOfflineSync(
        ambilVersi: (o, sejak) async {
          log.add('versi sejak $sejak');
          if (!punyaEndpointVersi) return null;
          if (!serverKenalVersiKatalog) {
            return VersiKatalogServer.dari([
              for (final e in versiServer.entries)
                {'id': e.key, 'version': e.value},
            ]);
          }
          final sama = sejak > 0 && sejak == versiKatalogServer;
          return VersiKatalogServer(
            versiKatalog: versiKatalogServer,
            tidakBerubah: sama,
            items: sama ? const {} : Map.of(versiServer),
          );
        },
        versiKatalogLokal: (o) async => lengkap ? versiKatalogLokal : 0,
        ambilPerId: (o, ids) async {
          panggilanAmbil++;
          log.add('ambil ${ids.length}');
          if (panggilanAmbil == gagalAmbilKe) throw Exception('putus');
          return [for (final id in ids) produkServer(id)];
        },
        ambilHalaman: (o, page, limit) async {
          log.add('halaman $page');
          final semua = versiServer.keys.toList();
          final mulai = (page - 1) * limit;
          if (mulai >= semua.length) return [];
          return [
            for (final id in semua.skip(mulai).take(limit)) produkServer(id),
          ];
        },
        versiLokal: (o) async {
          log.add('banding');
          return Map.of(lokal);
        },
        tandaiBasi: (o, ids) async {
          for (final id in ids) {
            flag[id] = false;
          }
        },
        simpan: (o, list) async {
          for (final p in list) {
            lokal[p.remoteId!] = p.version;
            flag[p.remoteId!] = true;
          }
        },
        pangkas: (o, tetap) async {
          lokal.removeWhere((id, _) => !tetap.contains(id));
          flag.removeWhere((id, _) => !tetap.contains(id));
        },
        tandaiLengkap: (o, v) async {
          lengkap = true;
          versiKatalogLokal = v;
        },
        jam: jam,
      );
    }

    setUp(() {
      versiServer = {for (var i = 0; i < 250; i++) 'p$i': 'v1'};
      versiKatalogServer = 7;
      serverKenalVersiKatalog = true;
      punyaEndpointVersi = true;
      gagalAmbilKe = null;
      lokal = {};
      flag = {};
      lengkap = false;
      versiKatalogLokal = 0;
      log = [];
    });

    test(
      'pertama kali: semua produk diambil per 100, versi katalog disimpan',
      () async {
        final hasil = await buat().sinkron('o1');

        expect(log, [
          'versi sejak 0',
          'banding',
          'ambil 100',
          'ambil 100',
          'ambil 50',
        ]);
        expect(hasil.jumlah, 250);
        expect(hasil.bertambah, 250);
        expect(hasil.lengkap, isTrue);
        expect(flag.values.every((f) => f), isTrue);
        expect(versiKatalogLokal, 7);
      },
    );

    test(
      'katalog tidak berubah: satu permintaan kecil, tanpa membandingkan atau mengambil',
      () async {
        await buat().sinkron('o1');
        log.clear();

        final hasil = await buat().sinkron('o1');
        expect(log, ['versi sejak 7']);
        expect(hasil.lengkap, isTrue);
        expect(hasil.adaPerubahan, isFalse);
      },
    );

    test(
      'produk berubah: flag jadi belum tersimpan, hanya produk itu diambil, lalu tersimpan lagi',
      () async {
        await buat().sinkron('o1');
        ubahServer(() {
          versiServer['p7'] = 'v2';
          versiServer['p8'] = 'v2';
        });
        log.clear();

        final flagSaatAmbil = <String, bool>{};
        final sync = buat();
        final asli = sync.ambilPerId;
        final pantau = ProductOfflineSync(
          ambilVersi: sync.ambilVersi,
          versiKatalogLokal: sync.versiKatalogLokal,
          ambilPerId: (o, ids) {
            for (final id in ids) {
              flagSaatAmbil[id] = flag[id]!;
            }
            return asli(o, ids);
          },
          ambilHalaman: sync.ambilHalaman,
          versiLokal: sync.versiLokal,
          tandaiBasi: sync.tandaiBasi,
          simpan: sync.simpan,
          pangkas: sync.pangkas,
          tandaiLengkap: sync.tandaiLengkap,
        );

        final hasil = await pantau.sinkron('o1');
        expect(log, ['versi sejak 7', 'banding', 'ambil 2']);
        expect(flagSaatAmbil, {'p7': false, 'p8': false});
        expect(flag['p7'], isTrue);
        expect(lokal['p7'], 'v2');
        expect(versiKatalogLokal, 8);
        expect(hasil.basi, 2);
        expect(
          hasil.daftarBerubah,
          isFalse,
          reason: 'isi berubah, daftar tetap',
        );
      },
    );

    test(
      'putus saat mengambil: versi katalog tidak disimpan, diulang di pemeriksaan berikutnya',
      () async {
        await buat().sinkron('o1');
        ubahServer(() => versiServer['p1'] = 'v2');
        gagalAmbilKe = 1;

        final gagal = await buat().sinkron('o1');
        expect(gagal.galat, isNotNull);
        expect(gagal.lengkap, isFalse);
        expect(flag['p1'], isFalse);
        expect(
          versiKatalogLokal,
          7,
          reason: 'versi lama tetap → server menyusun ulang',
        );

        gagalAmbilKe = null;
        log.clear();
        final ulang = await buat().sinkron('o1');
        expect(log, ['versi sejak 7', 'banding', 'ambil 1']);
        expect(flag['p1'], isTrue);
        expect(ulang.lengkap, isTrue);
        expect(versiKatalogLokal, 8);
      },
    );

    test('produk baru & produk dihapus di server', () async {
      await buat().sinkron('o1');
      ubahServer(() {
        versiServer.remove('p0');
        versiServer['baru'] = 'v1';
      });
      log.clear();

      final hasil = await buat().sinkron('o1');
      expect(log, ['versi sejak 7', 'banding', 'ambil 1']);
      expect(lokal.containsKey('p0'), isFalse);
      expect(lokal['baru'], 'v1');
      expect(hasil.dihapus, 1);
      expect(hasil.bertambah, 1);
      expect(hasil.daftarBerubah, isTrue);
    });

    test(
      'server tanpa versi katalog: selalu membandingkan, tapi tetap hanya mengambil yang berubah',
      () async {
        serverKenalVersiKatalog = false;
        await buat().sinkron('o1');
        expect(versiKatalogLokal, 0);
        log.clear();

        await buat().sinkron('o1');
        expect(log, ['versi sejak 0', 'banding']);
      },
    );

    test('server lama tanpa endpoint versi: ambil semua per halaman', () async {
      punyaEndpointVersi = false;
      final hasil = await buat().sinkron('o1');
      expect(log, ['versi sejak 0', 'halaman 1', 'halaman 2', 'halaman 3']);
      expect(hasil.lengkap, isTrue);
      expect(lokal.length, 250);
    });

    test('pemeriksaan berdekatan dilewati kecuali dipaksa', () async {
      var kini = DateTime(2026, 10, 29, 10);
      final sync = buat(jam: () => kini);
      expect((await sync.sinkron('o1')).lengkap, isTrue);

      kini = kini.add(const Duration(seconds: 10));
      expect((await sync.sinkron('o1')).dilewati, isTrue);
      expect((await sync.sinkron('o1', paksa: true)).lengkap, isTrue);

      kini = kini.add(const Duration(seconds: 31));
      expect((await sync.sinkron('o1')).lengkap, isTrue);
    });
  });
}
