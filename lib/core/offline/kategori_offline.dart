import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/outlet/data/outlet_service.dart';
import '../shared_prefs.dart';
import 'entity_cache.dart';
import 'product_folder_store.dart';

/// Kategori di perangkat — pola yang SAMA dengan katalog produk:
///
///  1. **Tersimpan di dua tempat.** SQLite (cepat), dan satu file per kategori
///     di folder cadangan tersembunyi (lihat [ProductFolderStore]) yang tetap
///     ada setelah aplikasi di-uninstall. Setelah install ulang, chip kategori
///     kasir langsung muncul walau tablet belum tersambung internet.
///  2. **Versi per kategori.** Server mengirim sidik isi tiap kategori
///     (`/categories/versions`). Yang diambil hanya kategori yang belum ada di
///     perangkat atau versinya berbeda (`/categories/by-ids`); yang sudah
///     dihapus di server ikut dibuang dari perangkat.
///  3. **Versi katalog.** Perangkat mengirim versi katalog terakhirnya
///     (`?since=N`); bila belum berubah, server menjawab dari satu baris tabel
///     tanpa menyusun daftar — pemeriksaan yang paling sering terjadi jadi
///     hampir gratis.
///
/// Dulu kategori diunduh ulang PENUH (bersama seluruh produk di dalamnya)
/// setiap kali dibuka online, dan hilang saat aplikasi di-uninstall.

/// Rencana sinkron: kategori yang perlu diambil & yang perlu dibuang. MURNI.
class RencanaKategori {
  const RencanaKategori({required this.ambil, required this.buang});
  final List<String> ambil;
  final Set<String> buang;

  bool get kosong => ambil.isEmpty && buang.isEmpty;
}

RencanaKategori rencanaKategori(
  Map<String, String> server,
  Map<String, String> lokal,
) => RencanaKategori(
  ambil: [
    for (final e in server.entries)
      if (lokal[e.key] != e.value) e.key,
  ],
  buang: {
    for (final id in lokal.keys)
      if (!server.containsKey(id)) id,
  },
);

/// Urutan tampil kategori — sama dengan server: sort_order, lalu nama. MURNI.
List<Map<String, dynamic>> urutkanKategori(Iterable<Map<String, dynamic>> d) {
  int urut(Map<String, dynamic> m) => (m['sort_order'] as num?)?.toInt() ?? 0;
  String nama(Map<String, dynamic> m) =>
      (m['name']?.toString() ?? '').toLowerCase();
  return d.toList()..sort((a, b) {
    final x = urut(a).compareTo(urut(b));
    return x != 0 ? x : nama(a).compareTo(nama(b));
  });
}

/// Simpanan kategori di perangkat: SQLite + folder cadangan.
class KategoriLokal {
  KategoriLokal(this._prefs, this._folder);

  final SharedPreferences _prefs;
  final ProductFolderStore _folder;

  static final _cache = EntityCache<Map<String, dynamic>>(
    'kategori',
    toJson: (m) => m,
    fromJson: (m) => m,
  );

  /// Cache lama (sebelum pola ini) — dibaca sekali sebagai jalan terakhir.
  static final _cacheLama = EntityCache<Map<String, dynamic>>(
    'categories',
    toJson: (m) => m,
    fromJson: (m) => m,
  );

  static String _kunciVersi(String outletId) =>
      'kategori.versi_katalog.$outletId';

  static List<String> dirKategori(String outletId) => [
    ProductFolderStore.folderOutlet(outletId),
    'kategori',
  ];

  static String namaFile(String id) =>
      '${ProductFolderStore.namaAman(id)}.json';

  /// Versi katalog server yang terakhir disamakan dengan kategori di sini.
  int versiKatalog(String outletId) =>
      _prefs.getInt(_kunciVersi(outletId)) ?? 0;

  Future<void> tandaiVersiKatalog(String outletId, int versi) =>
      _prefs.setInt(_kunciVersi(outletId), versi);

  /// Semua kategori outlet (mentah, terurut). SQLite dulu; kosong (mis.
  /// setelah install ulang) → folder cadangan, lalu disalin balik ke SQLite.
  Future<List<Map<String, dynamic>>> muat(String outletId) async {
    var data = await _cache.getAll(outletId);
    if (data.isEmpty) {
      data = await muatCadangan(outletId);
      if (data.isNotEmpty) await _cache.replaceAll(outletId, data);
    }
    if (data.isEmpty) data = await _cacheLama.getAll(outletId);
    return urutkanKategori(data);
  }

  /// id → versi kategori yang tersimpan.
  Future<Map<String, String>> versiLokal(String outletId) async => {
    for (final m in await _cache.getAll(outletId))
      if ((m['id']?.toString() ?? '').isNotEmpty)
        m['id'].toString(): m['version']?.toString() ?? '',
  };

  /// Terapkan hasil sinkron: [baru] ditimpa/ditambahkan, [buang] dihapus —
  /// di SQLite dan di folder cadangan (satu file per kategori).
  Future<void> terapkan(
    String outletId, {
    required List<Map<String, dynamic>> baru,
    required Set<String> buang,
  }) async {
    final semua = {
      for (final m in await _cache.getAll(outletId))
        m['id']?.toString() ?? '': m,
    }..remove('');
    for (final id in buang) {
      semua.remove(id);
    }
    for (final m in baru) {
      final id = m['id']?.toString() ?? '';
      if (id.isNotEmpty) semua[id] = m;
    }
    await _cache.replaceAll(outletId, semua.values.toList());
    await tulisCadangan(outletId, baru, buang);
  }

  /// Ganti seluruh isi (sinkron penuh, server lama tanpa endpoint versi).
  Future<void> gantiSemua(
    String outletId,
    List<Map<String, dynamic>> semua,
  ) async {
    final lama = (await _cache.getAll(
      outletId,
    )).map((m) => m['id']?.toString() ?? '').toSet();
    final ids = semua.map((m) => m['id']?.toString() ?? '').toSet();
    await _cache.replaceAll(outletId, semua);
    await tulisCadangan(outletId, semua, lama.difference(ids));
  }

  Future<List<Map<String, dynamic>>> muatCadangan(String outletId) async {
    try {
      final uri = await _folder.uriAktif();
      if (uri == null) return const [];
      final files = await _folder.backend.bacaSemua(uri, dirKategori(outletId));
      return [for (final isi in files.values) ?_dariFile(isi, outletId)];
    } catch (_) {
      return const [];
    }
  }

  static Map<String, dynamic>? _dariFile(String isi, String outletId) {
    try {
      final data = jsonDecode(isi);
      if (data is! Map || data['outlet_id'] != outletId) return null;
      final k = data['kategori'];
      return k is Map ? Map<String, dynamic>.from(k) : null;
    } catch (_) {
      return null; // satu file rusak tak boleh menyembunyikan yang lain
    }
  }

  Future<void> tulisCadangan(
    String outletId,
    List<Map<String, dynamic>> baru,
    Set<String> buang,
  ) async {
    try {
      final uri = await _folder.uriAktif();
      if (uri == null) return;
      final dir = dirKategori(outletId);
      for (final m in baru) {
        final id = m['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        await _folder.backend.tulis(
          uri,
          dir,
          namaFile(id),
          jsonEncode({
            'versi': 1,
            'outlet_id': outletId,
            'disimpan_pada': DateTime.now().toIso8601String(),
            'kategori': m,
          }),
        );
      }
      for (final id in buang) {
        if (id.isNotEmpty) await _folder.backend.hapus(uri, dir, namaFile(id));
      }
    } catch (_) {
      // Cadangan gagal ditulis tak boleh menggagalkan tampilan kasir.
    }
  }
}

/// Hasil satu sinkron kategori.
class HasilSinkronKategori {
  const HasilSinkronKategori({
    this.diambil = 0,
    this.dibuang = 0,
    this.tidakBerubah = false,
  });
  final int diambil;
  final int dibuang;
  final bool tidakBerubah;

  bool get adaPerubahan => diambil > 0 || dibuang > 0;
}

class KategoriOfflineSync {
  KategoriOfflineSync({required this.lokal, required this.api});

  final KategoriLokal lokal;
  final OutletService Function() api;

  static const maksIdPerPanggilan = 200;

  /// Samakan kategori perangkat dengan server. Melempar galat jaringan —
  /// pemanggil lalu memakai yang tersimpan.
  Future<HasilSinkronKategori> sinkron(String outletId) async {
    final server = await api().getCategoryVersions(
      outletId,
      sejak: lokal.versiKatalog(outletId),
    );
    if (server == null) {
      // Server lama tanpa endpoint versi: ambil penuh seperti dulu.
      final semua = await api().getCategories(outletId);
      await lokal.gantiSemua(outletId, [
        for (final c in semua) c.toCacheJson(),
      ]);
      return HasilSinkronKategori(diambil: semua.length);
    }
    if (server.tidakBerubah) {
      return const HasilSinkronKategori(tidakBerubah: true);
    }
    final rencana = rencanaKategori(
      server.items,
      await lokal.versiLokal(outletId),
    );
    final baru = <Map<String, dynamic>>[];
    for (var i = 0; i < rencana.ambil.length; i += maksIdPerPanggilan) {
      baru.addAll(
        await api().getCategoriesByIds(
          outletId,
          rencana.ambil.sublist(
            i,
            (i + maksIdPerPanggilan).clamp(0, rencana.ambil.length),
          ),
        ),
      );
    }
    if (!rencana.kosong) {
      await lokal.terapkan(outletId, baru: baru, buang: rencana.buang);
    }
    // Versi katalog dicatat HANYA setelah semuanya tersimpan: bila terputus
    // di tengah, pemeriksaan berikutnya menyusun ulang.
    await lokal.tandaiVersiKatalog(outletId, server.versiKatalog);
    return HasilSinkronKategori(
      diambil: baru.length,
      dibuang: rencana.buang.length,
    );
  }
}

final kategoriLokalProvider = Provider<KategoriLokal>(
  (ref) => KategoriLokal(
    ref.watch(sharedPreferencesProvider),
    ref.watch(productFolderStoreProvider),
  ),
);

final kategoriOfflineSyncProvider = Provider<KategoriOfflineSync>(
  (ref) => KategoriOfflineSync(
    lokal: ref.watch(kategoriLokalProvider),
    api: () => ref.read(outletServiceProvider),
  ),
);
