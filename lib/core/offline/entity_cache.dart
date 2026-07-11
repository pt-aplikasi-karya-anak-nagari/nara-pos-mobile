import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'offline_db.dart';
import 'sale_outbox.dart' show isOfflineError;

/// Sentinel outlet untuk list yang tidak terikat satu outlet (mis. daftar
/// outlet milik user). Pakai key ini sebagai `outletId`.
const String kGlobalCacheScope = '_global';

/// Cache baca-saja generik untuk satu jenis entitas, disimpan di tabel
/// `cached_entities` (SQLite). Generalisasi langsung dari [ProductCache]:
/// payload disimpan utuh sebagai JSON dan di-replace atomik
/// (ConflictAlgorithm.replace), lalu dibaca kembali saat offline.
///
/// PENTING: [toJson] di sini adalah *codec cache* yang HARUS round-trip
/// dengan [fromJson] (mengembalikan seluruh field yang dibaca fromJson).
/// JANGAN pakai `Model.toJson` bawaan kalau itu payload create/update yang
/// lossy — gunakan `Model.toCacheJson()` yang setia ke fromJson.
class EntityCache<T> {
  /// Diskriminator baris di `cached_entities` (mis. 'customers').
  final String entityKey;
  final Map<String, dynamic> Function(T) toJson;
  final T Function(Map<String, dynamic>) fromJson;

  const EntityCache(
    this.entityKey, {
    required this.toJson,
    required this.fromJson,
  });

  Future<void> replaceAll(String outletId, List<T> items) async {
    final db = await OfflineDb.instance.database;
    await db.insert(
      'cached_entities',
      {
        'entity': entityKey,
        'outlet_id': outletId,
        'payload': jsonEncode(items.map(toJson).toList()),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<T>> getAll(String outletId) async {
    final db = await OfflineDb.instance.database;
    final rows = await db.query(
      'cached_entities',
      where: 'entity = ? AND outlet_id = ?',
      whereArgs: [entityKey, outletId],
      limit: 1,
    );
    if (rows.isEmpty) return const [];
    final raw = rows.first['payload'] as String? ?? '[]';
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Umur baris cache (untuk indikator "data X jam lalu"); null bila belum
  /// pernah di-cache.
  Future<DateTime?> updatedAt(String outletId) async {
    final db = await OfflineDb.instance.database;
    final rows = await db.query(
      'cached_entities',
      columns: ['updated_at'],
      where: 'entity = ? AND outlet_id = ?',
      whereArgs: [entityKey, outletId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['updated_at'] as String? ?? '');
  }
}

/// Pola "cache-aware read": coba online → tulis-balik cache saat sukses →
/// layani cache saat error koneksi → lempar ulang error server nyata.
/// Diangkat verbatim dari `productsStreamProvider` (kasir/providers.dart).
Future<List<T>> readThroughCache<T>({
  required EntityCache<T> cache,
  required String outletId,
  required Future<List<T>> Function() fetch,
}) async {
  try {
    final fresh = await fetch();
    await cache.replaceAll(outletId, fresh);
    return fresh;
  } catch (e) {
    if (isOfflineError(e)) return cache.getAll(outletId);
    rethrow;
  }
}

/// Varian untuk resource objek tunggal (mis. shift aktif): disimpan sebagai
/// list berisi satu elemen lewat code path yang sama. Nilai `null` (mis.
/// tidak ada shift aktif) di-cache sebagai list kosong; saat offline
/// mengembalikan elemen pertama yang tersimpan atau null.
Future<T?> readThroughCacheOne<T>({
  required EntityCache<T> cache,
  required String outletId,
  required Future<T?> Function() fetch,
}) async {
  try {
    final fresh = await fetch();
    await cache.replaceAll(outletId, fresh == null ? const [] : [fresh]);
    return fresh;
  } catch (e) {
    if (isOfflineError(e)) {
      final cached = await cache.getAll(outletId);
      return cached.isEmpty ? null : cached.first;
    }
    rethrow;
  }
}
