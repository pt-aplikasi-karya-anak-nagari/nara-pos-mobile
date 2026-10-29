import 'dart:async';
import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/products/domain/product.dart';
import '../outlet_scope.dart';
import 'offline_db.dart';
import 'product_folder_store.dart';

/// Cache katalog produk per outlet untuk kasir offline.
///
/// Dua lapis, keduanya satu entri per produk:
///   1. SQLite (`cached_product_items`) — cepat, tapi ikut terhapus saat
///      aplikasi di-uninstall.
///   2. Folder pilihan pengguna ([ProductFolderStore]) — tetap ada setelah
///      uninstall. Dibaca bila SQLite kosong, mis. tepat setelah install ulang.
///
/// Setiap produk yang berhasil diambil dari API disimpan ke keduanya,
/// termasuk yang datang per halaman dari halaman kasir. Produk yang sudah
/// hilang dari server hanya dibuang lewat [pangkas] setelah sinkron penuh.
///
/// # FLAG PER PRODUK
///
/// Tiap produk menyimpan `versi` (versi server saat disimpan) dan
/// `tersimpan`:
///   - tersimpan = true  → salinan lokal sama dengan server; produk ini TIDAK
///     diambil lagi dari API.
///   - tersimpan = false → server punya versi lebih baru ([tandaiBasi]);
///     sinkron berikutnya mengambil datanya lalu flag kembali true.
class ProductCache {
  ProductCache({ProductFolderStore? folder}) : _folder = folder {
    _subFolder = folder?.perubahan.listen(_perubahan.add);
  }

  final ProductFolderStore? _folder;
  final _perubahan = StreamController<String>.broadcast();
  StreamSubscription<String>? _subFolder;

  /// Katalog yang sudah di-decode per outlet. Halaman kasir membaca katalog
  /// di setiap halaman grid; tanpa ini setiap halaman men-decode ulang JSON
  /// seluruh produk. Dibuang setiap kali data produk ditulis.
  final Map<String, List<Product>> _memo = {};

  /// Memancarkan outletId setiap daftar produk tersimpan outlet itu berubah
  /// (`*` = semua outlet). Dipakai ikon "tersimpan" di kartu produk.
  Stream<String> get perubahan => _perubahan.stream;

  void dispose() {
    _subFolder?.cancel();
    _perubahan.close();
  }

  /// ID produk outlet [outletId] yang flag-nya "tersimpan" (salinan lokal =
  /// versi server). Bila folder dipilih, produk juga harus sudah punya file
  /// di folder (tahan uninstall).
  Future<Set<String>> idTersimpan(String outletId) async {
    final db = await OfflineDb.instance.database;
    final rows = await db.query(
      'cached_product_items',
      columns: ['product_id'],
      where: 'outlet_id = ? AND tersimpan = 1',
      whereArgs: [outletId],
    );
    final ids = {for (final r in rows) r['product_id'] as String};
    final folder = _folder;
    if (folder != null && await folder.aktif()) {
      return ids.intersection(await folder.idTersimpan(outletId));
    }
    return ids;
  }

  /// Versi lokal tiap produk outlet: id → versi saat terakhir disimpan.
  Future<Map<String, String>> versiLokal(String outletId) async {
    final db = await OfflineDb.instance.database;
    final rows = await db.query(
      'cached_product_items',
      columns: ['product_id', 'versi'],
      where: 'outlet_id = ?',
      whereArgs: [outletId],
    );
    return {
      for (final r in rows)
        r['product_id'] as String: (r['versi'] as String?) ?? '',
    };
  }

  /// Ubah flag produk [ids] menjadi "belum tersimpan": server punya versi
  /// lebih baru. Data lamanya tetap ada untuk dipakai selama offline.
  Future<void> tandaiBasi(String outletId, Iterable<String> ids) async {
    final daftar = ids.toList();
    if (daftar.isEmpty) return;
    final db = await OfflineDb.instance.database;
    final batch = db.batch();
    for (final id in daftar) {
      batch.update(
        'cached_product_items',
        {'tersimpan': 0},
        where: 'outlet_id = ? AND product_id = ?',
        whereArgs: [outletId, id],
      );
    }
    await batch.commit(noResult: true);
    if (!_perubahan.isClosed) _perubahan.add(outletId);
  }

  /// Katalog outlet pernah tersimpan utuh. Sejak itu halaman kasir membaca
  /// produk dari perangkat, bukan dari API.
  Future<bool> katalogLengkap(String outletId) async {
    final db = await OfflineDb.instance.database;
    final rows = await db.query(
      'catalog_state',
      columns: ['lengkap_pada'],
      where: 'outlet_id = ?',
      whereArgs: [outletId],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['lengkap_pada'] != null;
  }

  /// Katalog lokal kini sama dengan server pada [versiKatalog] (0 = server
  /// tak memberi versi katalog).
  Future<void> tandaiKatalogLengkap(
    String outletId, {
    int versiKatalog = 0,
  }) async {
    final db = await OfflineDb.instance.database;
    final kini = DateTime.now().toIso8601String();
    await db.insert('catalog_state', {
      'outlet_id': outletId,
      'lengkap_pada': kini,
      'dicek_pada': kini,
      'versi_katalog': versiKatalog,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Versi katalog server yang terakhir disamakan dengan katalog lokal. 0 bila
  /// katalog belum pernah tersimpan lengkap — server lalu selalu mengirim
  /// daftar versi lengkap.
  Future<int> versiKatalog(String outletId) async {
    final db = await OfflineDb.instance.database;
    final rows = await db.query(
      'catalog_state',
      columns: ['lengkap_pada', 'versi_katalog'],
      where: 'outlet_id = ?',
      whereArgs: [outletId],
      limit: 1,
    );
    if (rows.isEmpty || rows.first['lengkap_pada'] == null) return 0;
    return (rows.first['versi_katalog'] as int?) ?? 0;
  }

  /// Simpan/perbarui [products] tanpa membuang produk lain yang sudah ada.
  Future<void> simpanBanyak(String outletId, List<Product> products) async {
    if (outletId.isEmpty || products.isEmpty) return;
    final db = await OfflineDb.instance.database;
    final kini = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final p in products) {
      final id = p.remoteId;
      if (id == null || id.isEmpty) continue;
      batch.insert('cached_product_items', {
        'outlet_id': outletId,
        'product_id': id,
        'payload': jsonEncode(p.toJson()),
        'updated_at': kini,
        // Data baru dari server → flag kembali "tersimpan".
        'versi': p.version,
        'tersimpan': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    _memo.remove(outletId);
    if (!_perubahan.isClosed) _perubahan.add(outletId);

    // Salinan ke folder ditulis di latar: halaman kasir tidak perlu menunggu
    // file demi file selesai ditulis.
    final folder = _folder;
    if (folder != null) unawaited(folder.simpan(outletId, products));
  }

  /// Kurangi stok produk di katalog perangkat setelah penjualan OFFLINE.
  ///
  /// Tanpa ini, stok yang tampil di kasir tak bergerak selama offline: produk
  /// yang tinggal 3 bisa terjual 10 kali, dan selisihnya baru ketahuan setelah
  /// sinkron. Hanya produk yang "kelola stok"; varian dikurangi pada variannya
  /// sendiri. Stok bisa jadi negatif — sama seperti di server untuk transaksi
  /// offline — supaya selisihnya tetap terlihat.
  ///
  /// Versi produk SENGAJA tidak diubah: begitu server menerima penjualannya,
  /// versi produk di server berubah dan sinkron katalog mengambil stok yang
  /// sebenarnya.
  Future<void> kurangiStokLokal(
    String outletId,
    List<({String productId, String? variantId, int qty})> baris,
  ) async {
    if (outletId.isEmpty || baris.isEmpty) return;
    final db = await OfflineDb.instance.database;
    final perProduk = <String, List<({String? variantId, int qty})>>{};
    for (final b in baris) {
      if (b.productId.isEmpty || b.qty <= 0) continue;
      (perProduk[b.productId] ??= []).add((variantId: b.variantId, qty: b.qty));
    }
    if (perProduk.isEmpty) return;

    var berubah = false;
    await db.transaction((tx) async {
      for (final e in perProduk.entries) {
        final rows = await tx.query(
          'cached_product_items',
          columns: ['payload'],
          where: 'outlet_id = ? AND product_id = ?',
          whereArgs: [outletId, e.key],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final json =
            jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>;
        if (json['track_stock'] == false) continue;
        for (final b in e.value) {
          final varian = json['variants'];
          if (b.variantId != null && varian is List) {
            for (final v in varian) {
              if (v is Map && v['id']?.toString() == b.variantId) {
                v['stock'] = ((v['stock'] as num?) ?? 0).toInt() - b.qty;
              }
            }
          } else {
            json['stock'] = ((json['stock'] as num?) ?? 0).toInt() - b.qty;
          }
        }
        await tx.update(
          'cached_product_items',
          {'payload': jsonEncode(json)},
          where: 'outlet_id = ? AND product_id = ?',
          whereArgs: [outletId, e.key],
        );
        berubah = true;
      }
    });
    if (!berubah) return;
    _memo.remove(outletId);
    if (!_perubahan.isClosed) _perubahan.add(outletId);
  }

  /// Tulis SELURUH produk lokal outlet ke folder — dipakai tepat setelah
  /// folder dipilih. Sinkron biasa hanya menulis produk yang berubah, jadi
  /// tanpa ini folder baru hanya berisi produk yang kebetulan berubah.
  Future<int> salinKeFolder(String outletId) async {
    final folder = _folder;
    if (folder == null) return 0;
    return folder.simpan(outletId, await getAll(outletId));
  }

  Future<List<Product>> getAll(String outletId) async {
    final memo = _memo[outletId];
    if (memo != null) return List.of(memo);
    final hasil = await _muat(outletId);
    _memo[outletId] = hasil;
    return List.of(hasil);
  }

  Future<List<Product>> _muat(String outletId) async {
    final db = await OfflineDb.instance.database;
    final rows = await db.query(
      'cached_product_items',
      columns: ['payload'],
      where: 'outlet_id = ?',
      whereArgs: [outletId],
    );
    if (rows.isNotEmpty) {
      final hasil = <Product>[];
      for (final r in rows) {
        try {
          hasil.add(
            Product.fromJson(
              jsonDecode(r['payload'] as String) as Map<String, dynamic>,
            ),
          );
        } catch (_) {
          // Baris rusak dilewati; produk lain tetap tampil.
        }
      }
      hasil.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return hasil;
    }

    // SQLite kosong — biasanya tepat setelah install ulang. Pulihkan dari
    // folder, lalu isi SQLite supaya pembacaan berikutnya cepat.
    final folder = _folder;
    if (folder != null) {
      final dariFolder = await folder.muat(outletId);
      if (dariFolder.isNotEmpty) {
        await _isiSqlite(db, outletId, dariFolder);
        return dariFolder;
      }
    }

    return _legacy(db, outletId);
  }

  /// Buang produk yang tidak ada di [idTetap], di SQLite dan di folder.
  /// Hanya boleh dipanggil dengan daftar LENGKAP hasil sinkron penuh.
  Future<void> pangkas(String outletId, Set<String> idTetap) async {
    final db = await OfflineDb.instance.database;
    final rows = await db.query(
      'cached_product_items',
      columns: ['product_id'],
      where: 'outlet_id = ?',
      whereArgs: [outletId],
    );
    final batch = db.batch();
    for (final r in rows) {
      final id = r['product_id'] as String;
      if (idTetap.contains(id)) continue;
      batch.delete(
        'cached_product_items',
        where: 'outlet_id = ? AND product_id = ?',
        whereArgs: [outletId, id],
      );
    }
    // Katalog lama satu-baris sudah tergantikan sepenuhnya.
    batch.delete(
      'cached_products',
      where: 'outlet_id = ?',
      whereArgs: [outletId],
    );
    await batch.commit(noResult: true);
    _memo.remove(outletId);
    if (!_perubahan.isClosed) _perubahan.add(outletId);
    await _folder?.pangkas(outletId, idTetap);
  }

  /// Kapan katalog produk terakhir diperbarui dari server. Dipakai untuk
  /// indikator kesegaran data saat offline. Null bila belum ada.
  Future<DateTime?> updatedAt(String outletId) async {
    final db = await OfflineDb.instance.database;
    final rows = await db.rawQuery(
      'SELECT MAX(updated_at) AS t FROM cached_product_items WHERE outlet_id = ?',
      [outletId],
    );
    final t = rows.isEmpty ? null : rows.first['t'] as String?;
    if (t != null) return DateTime.tryParse(t);

    final lama = await db.query(
      'cached_products',
      columns: ['updated_at'],
      where: 'outlet_id = ?',
      whereArgs: [outletId],
      limit: 1,
    );
    if (lama.isEmpty) return null;
    return DateTime.tryParse(lama.first['updated_at'] as String? ?? '');
  }

  Future<void> _isiSqlite(
    Database db,
    String outletId,
    List<Product> products,
  ) async {
    final kini = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final p in products) {
      batch.insert('cached_product_items', {
        'outlet_id': outletId,
        'product_id': p.remoteId,
        'payload': jsonEncode(p.toJson()),
        'updated_at': kini,
        // Dari folder (mis. setelah install ulang): versinya ikut tersimpan di
        // file. Sinkron berikutnya membandingkannya dengan server.
        'versi': p.version,
        'tersimpan': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Cache lama (sebelum v5): seluruh katalog dalam satu baris.
  Future<List<Product>> _legacy(Database db, String outletId) async {
    final rows = await db.query(
      'cached_products',
      where: 'outlet_id = ?',
      whereArgs: [outletId],
      limit: 1,
    );
    if (rows.isEmpty) return const [];
    final raw = rows.first['payload'] as String? ?? '[]';
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// Umur cache data offline untuk outlet aktif (timestamp terakhir sinkron
/// katalog produk). Dipakai banner offline untuk tampilkan "data X lalu".
final offlineDataSyncedAtProvider = FutureProvider<DateTime?>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null || outletId.isEmpty) return null;
  return ref.watch(productCacheProvider).updatedAt(outletId);
});

final productCacheProvider = Provider<ProductCache>((ref) {
  final cache = ProductCache(folder: ref.watch(productFolderStoreProvider));
  ref.onDispose(cache.dispose);
  return cache;
});

/// Produk lokal outlet aktif, per ID. Kartu kasir menampilkan data dari sini
/// bila ada, sehingga perubahan dari sinkron (stok, harga, dll.) langsung
/// tampil di kartu tanpa memuat ulang grid — dan posisi scroll kasir tetap.
final produkLokalProvider =
    NotifierProvider<ProdukLokalNotifier, Map<String, Product>>(
      ProdukLokalNotifier.new,
    );

class ProdukLokalNotifier extends Notifier<Map<String, Product>> {
  int _versi = 0;

  @override
  Map<String, Product> build() {
    final outletId = ref.watch(activeOutletIdProvider);
    final cache = ref.watch(productCacheProvider);
    if (outletId == null || outletId.isEmpty) return const {};

    final sub = cache.perubahan
        .where((o) => o == outletId || o == '*')
        .listen((_) => _muat(cache, outletId));
    ref.onDispose(sub.cancel);
    _muat(cache, outletId);
    return const {};
  }

  Future<void> _muat(ProductCache cache, String outletId) async {
    final versi = ++_versi;
    try {
      final semua = await cache.getAll(outletId);
      if (!ref.mounted || versi != _versi) return;
      state = {
        for (final p in semua)
          if (p.remoteId != null) p.remoteId!: p,
      };
    } catch (_) {
      // Tanpa overlay, kartu memakai data yang dibawa grid.
    }
  }
}

/// ID produk outlet aktif yang sudah tersimpan untuk offline. Kartu produk
/// kasir menampilkan ikon folder bila ID-nya ada di sini.
final produkTersimpanProvider =
    NotifierProvider<ProdukTersimpanNotifier, Set<String>>(
      ProdukTersimpanNotifier.new,
    );

class ProdukTersimpanNotifier extends Notifier<Set<String>> {
  int _versi = 0;

  @override
  Set<String> build() {
    final outletId = ref.watch(activeOutletIdProvider);
    final cache = ref.watch(productCacheProvider);
    if (outletId == null || outletId.isEmpty) return const {};

    final sub = cache.perubahan
        .where((o) => o == outletId || o == '*')
        .listen((_) => _muat(cache, outletId));
    ref.onDispose(sub.cancel);
    _muat(cache, outletId);
    return const {};
  }

  Future<void> _muat(ProductCache cache, String outletId) async {
    final versi = ++_versi;
    try {
      final ids = await cache.idTersimpan(outletId);
      // Abaikan hasil yang tersusul permintaan lebih baru.
      if (!ref.mounted || versi != _versi) return;
      state = ids;
    } catch (_) {
      // Ikon hanya penanda; gagal memuat tidak boleh mengganggu kasir.
    }
  }
}
