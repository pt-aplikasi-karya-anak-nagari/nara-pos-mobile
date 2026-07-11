import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Singleton pembungkus database SQLite lokal untuk fitur offline.
///
/// Saat ini hanya menampung outbox transaksi (`pending_sales`) — payload
/// checkout yang belum terkirim ke backend karena perangkat offline.
/// Disengaja dibuat ringan (satu tabel) supaya mudah dirawat; tabel lain
/// (mis. cache produk) bisa ditambahkan via migrasi `onUpgrade` nanti.
class OfflineDb {
  OfflineDb._();
  static final OfflineDb instance = OfflineDb._();

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'nara_offline.db');
    final db = await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute(_createPendingSales);
        await db.execute(_createCachedProducts);
        await db.execute(_createCachedEntities);
        await db.execute(_createPendingOps);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 → v2: tambah cache katalog produk untuk cold-start offline.
        if (oldVersion < 2) {
          await db.execute(_createCachedProducts);
        }
        // v2 → v3: cache generik (cached_entities) untuk seluruh data
        // baca-saja yang dibutuhkan kasir offline (outlet, kategori,
        // customer, metode bayar, tipe order, meja, shift aktif).
        // COEXISTENCE: pending_sales & cached_products SENGAJA dibiarkan
        // utuh supaya jalur checkout/produk yang sudah terbukti tidak
        // tersentuh & tidak ada data antrian yang hilang.
        if (oldVersion < 3) {
          await db.execute(_createCachedEntities);
        }
        // v3 → v4: outbox operasi generik (pending_ops) untuk tulis offline
        // selain checkout — saat ini buka/tutup shift. pending_sales tetap
        // tak tersentuh.
        if (oldVersion < 4) {
          await db.execute(_createPendingOps);
        }
      },
    );
    _db = db;
    return db;
  }

  static const _createPendingSales = '''
    CREATE TABLE IF NOT EXISTS pending_sales (
      local_id   TEXT PRIMARY KEY,
      outlet_id  TEXT NOT NULL,
      payload    TEXT NOT NULL,
      created_at TEXT NOT NULL,
      attempts   INTEGER NOT NULL DEFAULT 0,
      last_error TEXT
    )
  ''';

  // Satu baris per outlet; payload = JSON array seluruh produk. Disengaja
  // disimpan utuh (bukan per-produk) supaya replace cache atomic & simpel.
  static const _createCachedProducts = '''
    CREATE TABLE IF NOT EXISTS cached_products (
      outlet_id  TEXT PRIMARY KEY,
      payload    TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''';

  // Cache generik untuk seluruh entitas baca-saja. `entity` = diskriminator
  // (mis. 'categories', 'customers', 'payment_methods', 'order_types',
  // 'tables', 'table_groups', 'outlets', 'active_shift'). Payload = JSON utuh
  // (array atau objek tunggal), disimpan & di-replace atomik persis seperti
  // cached_products. Untuk list global non-outlet (mis. daftar outlet) pakai
  // sentinel outlet_id '_global'.
  static const _createCachedEntities = '''
    CREATE TABLE IF NOT EXISTS cached_entities (
      entity     TEXT NOT NULL,
      outlet_id  TEXT NOT NULL,
      payload    TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (entity, outlet_id)
    )
  ''';

  // Outbox operasi tulis generik (selain checkout yang punya pending_sales
  // sendiri). op_type = 'shift_open' | 'shift_close'. client_ref = idempotency
  // key (dedup di backend). depends_on = local_id op induk (close menunggu
  // open). local_shift_id = id optimistik lokal; server_shift_id diisi setelah
  // open ter-ACK (dipakai close & remap cache active_shift). status =
  // 'pending' | 'blocked' | 'done' | 'dead'. occurred_at = waktu bisnis (saat
  // kasir buka/tutup offline) untuk dihormati server.
  static const _createPendingOps = '''
    CREATE TABLE IF NOT EXISTS pending_ops (
      local_id        TEXT PRIMARY KEY,
      op_type         TEXT NOT NULL,
      outlet_id       TEXT NOT NULL,
      client_ref      TEXT NOT NULL,
      payload         TEXT NOT NULL,
      depends_on      TEXT,
      local_shift_id  TEXT,
      server_shift_id TEXT,
      status          TEXT NOT NULL DEFAULT 'pending',
      created_at      TEXT NOT NULL,
      occurred_at     TEXT,
      attempts        INTEGER NOT NULL DEFAULT 0,
      last_error      TEXT
    )
  ''';
}
