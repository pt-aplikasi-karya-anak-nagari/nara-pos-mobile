import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nara_pos_mobile/core/offline/folder_offline.dart';
import 'package:nara_pos_mobile/core/offline/kategori_offline.dart';
import 'package:nara_pos_mobile/core/offline/product_folder_store.dart';
import 'package:nara_pos_mobile/features/outlet/data/outlet_service.dart';
import 'package:nara_pos_mobile/features/products/domain/category.dart';

// Kategori di perangkat memakai pola katalog produk: versi katalog, versi
// per kategori, ambil hanya yang berubah, buang yang dihapus.

class _FolderMati implements FolderBackend {
  @override
  bool get didukung => false;
  @override
  Future<bool> punyaAkses(String uri) async => false;
  @override
  Future<void> tulis(
    String uri,
    List<String> dir,
    String nama,
    String isi,
  ) async {}
  @override
  Future<Map<String, String>> bacaSemua(String uri, List<String> dir) async =>
      {};
  @override
  Future<List<String>> daftarNama(String uri, List<String> dir) async => [];
  @override
  Future<bool> hapus(String uri, List<String> dir, String nama) async => false;
}

/// Simpanan kategori di memori — SQLite tak tersedia di lingkungan tes.
class _LokalMemori extends KategoriLokal {
  _LokalMemori(SharedPreferences prefs)
    : super(prefs, ProductFolderStore(_FolderMati()));

  final Map<String, Map<String, dynamic>> isi = {};
  int ditulisUlang = 0;

  @override
  Future<List<Map<String, dynamic>>> muat(String outletId) async =>
      urutkanKategori(isi.values);

  @override
  Future<Map<String, String>> versiLokal(String outletId) async => {
    for (final e in isi.entries) e.key: e.value['version']?.toString() ?? '',
  };

  @override
  Future<void> terapkan(
    String outletId, {
    required List<Map<String, dynamic>> baru,
    required Set<String> buang,
  }) async {
    ditulisUlang += baru.length;
    buang.forEach(isi.remove);
    for (final m in baru) {
      isi[m['id'].toString()] = m;
    }
  }

  @override
  Future<void> gantiSemua(
    String outletId,
    List<Map<String, dynamic>> semua,
  ) async {
    isi
      ..clear()
      ..addEntries(semua.map((m) => MapEntry(m['id'].toString(), m)));
  }
}

class _ServerPalsu extends OutletService {
  _ServerPalsu() : super(Dio());

  int versiKatalog = 5;
  bool punyaEndpointVersi = true;
  final Map<String, Map<String, dynamic>> kategori = {};
  final List<List<String>> dimintaPerId = [];
  final List<int> sejakDiminta = [];

  @override
  Future<VersiKatalogServer?> getCategoryVersions(
    String outletId, {
    int sejak = 0,
  }) async {
    sejakDiminta.add(sejak);
    if (!punyaEndpointVersi) return null;
    if (sejak == versiKatalog) {
      return VersiKatalogServer(
        versiKatalog: versiKatalog,
        tidakBerubah: true,
        items: const {},
      );
    }
    return VersiKatalogServer(
      versiKatalog: versiKatalog,
      tidakBerubah: false,
      items: {
        for (final e in kategori.entries) e.key: e.value['version'].toString(),
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getCategoriesByIds(
    String outletId,
    List<String> ids,
  ) async {
    dimintaPerId.add(ids);
    return [for (final id in ids) ?kategori[id]];
  }

  @override
  Future<List<Category>> getCategories(String outletId) async => [
    for (final m in kategori.values) Category.fromJson(m),
  ];
}

Map<String, dynamic> _kat(
  String id,
  String nama,
  String versi, {
  int urut = 0,
}) => {
  'id': id,
  'outlet_id': 'o1',
  'name': nama,
  'sort_order': urut,
  'version': versi,
};

void main() {
  late _LokalMemori lokal;
  late _ServerPalsu server;
  late KategoriOfflineSync sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    lokal = _LokalMemori(await SharedPreferences.getInstance());
    server = _ServerPalsu()
      ..kategori.addAll({
        'K1': _kat('K1', 'Makanan', 'a1', urut: 1),
        'K2': _kat('K2', 'Minuman', 'b1', urut: 0),
      });
    sync = KategoriOfflineSync(lokal: lokal, api: () => server);
  });

  test('pertama kali: semua diambil, versi katalog disimpan', () async {
    final h = await sync.sinkron('o1');
    expect(h.diambil, 2);
    expect(lokal.isi.keys, unorderedEquals(['K1', 'K2']));
    expect(lokal.versiKatalog('o1'), 5);
  });

  test('katalog tak berubah: tak ada yang diambil', () async {
    await sync.sinkron('o1');
    server.dimintaPerId.clear();
    final h = await sync.sinkron('o1');
    expect(h.tidakBerubah, isTrue);
    expect(server.sejakDiminta.last, 5, reason: 'mengirim versi katalog lokal');
    expect(server.dimintaPerId, isEmpty);
  });

  test('hanya kategori yang berubah diambil; yang dihapus dibuang', () async {
    await sync.sinkron('o1');
    server
      ..versiKatalog = 6
      ..kategori['K1'] = _kat('K1', 'Makanan Berat', 'a2', urut: 1)
      ..kategori['K3'] = _kat('K3', 'Snack', 'c1', urut: 2)
      ..kategori.remove('K2');
    server.dimintaPerId.clear();

    final h = await sync.sinkron('o1');
    expect(
      server.dimintaPerId.single,
      unorderedEquals(['K1', 'K3']),
      reason: 'K2 dihapus, K1 & K3 berubah/baru — tak ada yang lain diambil',
    );
    expect(h.dibuang, 1);
    expect(lokal.isi.keys, unorderedEquals(['K1', 'K3']));
    expect(lokal.isi['K1']!['name'], 'Makanan Berat');
    expect(lokal.versiKatalog('o1'), 6);
  });

  test(
    'versi katalog berubah karena produk: kategori tak diunduh ulang',
    () async {
      await sync.sinkron('o1');
      server.versiKatalog = 9; // stok produk berubah, kategori tetap
      server.dimintaPerId.clear();
      final h = await sync.sinkron('o1');
      expect(server.dimintaPerId, isEmpty);
      expect(h.adaPerubahan, isFalse);
      expect(lokal.versiKatalog('o1'), 9);
    },
  );

  test('server lama tanpa endpoint versi: ambil penuh', () async {
    server.punyaEndpointVersi = false;
    await sync.sinkron('o1');
    expect(lokal.isi.keys, unorderedEquals(['K1', 'K2']));
  });

  test('urutan tampil sama dengan server: sort_order lalu nama', () {
    final urut = urutkanKategori([
      _kat('A', 'Zebra', 'x', urut: 1),
      _kat('B', 'apel', 'x', urut: 1),
      _kat('C', 'Minuman', 'x', urut: 0),
    ]);
    expect(urut.map((m) => m['id']), ['C', 'B', 'A']);
  });

  test('rencana sinkron', () {
    final r = rencanaKategori(
      {'K1': 'v2', 'K3': 'v1'},
      {'K1': 'v1', 'K2': 'v1'},
    );
    expect(r.ambil, unorderedEquals(['K1', 'K3']));
    expect(r.buang, {'K2'});
    expect(rencanaKategori({'K1': 'v1'}, {'K1': 'v1'}).kosong, isTrue);
  });

  test('kategori dari cache mentah lengkap dengan urutan & versi', () {
    final c = Category.fromJson(_kat('K1', 'Makanan', 'a1', urut: 3));
    expect((c.order, c.version), (3, 'a1'));
    expect(Category.fromJson(c.toCacheJson()).version, 'a1');
  });

  test(
    'cadangan folder: satu file per kategori, terbaca lagi setelah install ulang',
    () async {
      final folder = _FolderMemori();
      final cadangan = KategoriLokal(
        await SharedPreferences.getInstance(),
        ProductFolderStore(folder),
      );
      await cadangan.tulisCadangan('o1', [
        _kat('K1', 'Makanan', 'a1'),
        _kat('K2', 'Minuman', 'b1'),
      ], const {});
      expect(folder.file.keys, unorderedEquals(['K1.json', 'K2.json']));
      expect(folder.dirTerakhir, KategoriLokal.dirKategori('o1'));

      // Kategori dihapus di server → filenya ikut dibuang.
      await cadangan.tulisCadangan('o1', const [], {'K2'});
      expect(folder.file.keys, ['K1.json']);

      // Install ulang: SQLite kosong, folder cadangan masih ada.
      final dibaca = await cadangan.muatCadangan('o1');
      expect(dibaca.single['name'], 'Makanan');
      expect(dibaca.single['version'], 'a1');
      // File milik outlet lain tak ikut.
      expect(await cadangan.muatCadangan('o2'), isEmpty);
    },
  );
}

class _FolderMemori implements FolderBackend {
  final Map<String, String> file = {};
  List<String>? dirTerakhir;
  @override
  bool get didukung => true;
  @override
  Future<bool> punyaAkses(String uri) async => true;
  @override
  Future<void> tulis(
    String uri,
    List<String> dir,
    String nama,
    String isi,
  ) async {
    dirTerakhir = dir;
    file[nama] = isi;
  }

  @override
  Future<Map<String, String>> bacaSemua(String uri, List<String> dir) async =>
      Map.of(file);
  @override
  Future<List<String>> daftarNama(String uri, List<String> dir) async =>
      file.keys.toList();
  @override
  Future<bool> hapus(String uri, List<String> dir, String nama) async =>
      file.remove(nama) != null;
}
