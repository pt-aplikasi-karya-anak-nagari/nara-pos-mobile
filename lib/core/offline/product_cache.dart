import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/products/domain/product.dart';
import '../outlet_scope.dart';
import 'offline_db.dart';

/// Cache katalog produk per outlet di SQLite. Ditulis ulang setiap kali
/// daftar produk lengkap berhasil di-fetch online, lalu dibaca saat offline
/// (mis. app dibuka cold-start tanpa koneksi) supaya kasir tetap bisa
/// memilih produk dan checkout (transaksi masuk outbox).
class ProductCache {
  Future<void> replaceAll(String outletId, List<Product> products) async {
    final db = await OfflineDb.instance.database;
    final payload = jsonEncode(products.map((p) => p.toJson()).toList());
    await db.insert(
      'cached_products',
      {
        'outlet_id': outletId,
        'payload': payload,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Product>> getAll(String outletId) async {
    final db = await OfflineDb.instance.database;
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

  /// Kapan katalog produk terakhir di-cache (= terakhir berhasil fetch online).
  /// Dipakai untuk indikator kesegaran data saat offline. Null bila belum ada.
  Future<DateTime?> updatedAt(String outletId) async {
    final db = await OfflineDb.instance.database;
    final rows = await db.query(
      'cached_products',
      columns: ['updated_at'],
      where: 'outlet_id = ?',
      whereArgs: [outletId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['updated_at'] as String? ?? '');
  }
}

/// Umur cache data offline untuk outlet aktif (timestamp terakhir sinkron
/// katalog produk). Dipakai banner offline untuk tampilkan "data X lalu".
final offlineDataSyncedAtProvider = FutureProvider<DateTime?>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null || outletId.isEmpty) return null;
  return ref.watch(productCacheProvider).updatedAt(outletId);
});

final productCacheProvider = Provider<ProductCache>((ref) => ProductCache());
