import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'offline_db.dart';

/// Satu transaksi yang menunggu dikirim ke backend (dibuat saat offline).
class PendingSale {
  final String localId;
  final String outletId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;

  const PendingSale({
    required this.localId,
    required this.outletId,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
  });

  factory PendingSale.fromRow(Map<String, Object?> row) {
    final raw = row['payload'] as String? ?? '{}';
    return PendingSale(
      localId: row['local_id'] as String? ?? '',
      outletId: row['outlet_id'] as String? ?? '',
      payload: jsonDecode(raw) as Map<String, dynamic>,
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      attempts: (row['attempts'] as int?) ?? 0,
      lastError: row['last_error'] as String?,
    );
  }
}

/// Repository antrian (outbox) transaksi offline berbasis SQLite.
class SaleOutbox {
  /// Batas percobaan sync. Sale yang ditolak server (4xx/5xx — mis. produk
  /// dihapus) takkan pernah sukses; setelah batas ini ia jadi "dead-letter":
  /// tetap tersimpan di DB (bisa dipulihkan), tapi DIKELUARKAN dari antrian
  /// aktif & hitungan banner supaya tidak re-POST selamanya / banner macet.
  static const int maxSyncAttempts = 5;

  Future<String> enqueue(String outletId, Map<String, dynamic> payload) async {
    final db = await OfflineDb.instance.database;
    final localId = 'offline_${DateTime.now().microsecondsSinceEpoch}';
    await db.insert('pending_sales', {
      'local_id': localId,
      'outlet_id': outletId,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    return localId;
  }

  /// Antrian aktif yang masih layak dicoba (attempts < batas). Dead-letter
  /// dikecualikan supaya sync tidak re-POST selamanya.
  Future<List<PendingSale>> pending() async {
    final db = await OfflineDb.instance.database;
    final rows = await db.query(
      'pending_sales',
      where: 'attempts < ?',
      whereArgs: [maxSyncAttempts],
      orderBy: 'created_at ASC',
    );
    return rows.map(PendingSale.fromRow).toList();
  }

  /// Hitungan untuk banner — hanya transaksi yang masih akan dicoba
  /// (dead-letter tidak dihitung, agar banner tidak macet >0 selamanya).
  Future<int> count() async {
    final db = await OfflineDb.instance.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM pending_sales WHERE attempts < ?',
      [maxSyncAttempts],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// Jumlah transaksi gagal-permanen (dead-letter) — untuk indikator terpisah.
  Future<int> deadLetterCount() async {
    final db = await OfflineDb.instance.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM pending_sales WHERE attempts >= ?',
      [maxSyncAttempts],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// Daftar dead-letter (gagal-permanen) untuk UI recovery — owner bisa lihat
  /// detail + error, lalu pilih retry (re-queue) atau buang permanen.
  Future<List<PendingSale>> deadLetters() async {
    final db = await OfflineDb.instance.database;
    final rows = await db.query(
      'pending_sales',
      where: 'attempts >= ?',
      whereArgs: [maxSyncAttempts],
      orderBy: 'created_at ASC',
    );
    return rows.map(PendingSale.fromRow).toList();
  }

  /// Reset 1 dead-letter supaya masuk antrian aktif lagi (attempts=0, error
  /// dibersihkan). Sync berikutnya akan mencoba mengirimnya ulang.
  Future<void> retry(String localId) async {
    final db = await OfflineDb.instance.database;
    await db.update(
      'pending_sales',
      {'attempts': 0, 'last_error': null},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> remove(String localId) async {
    final db = await OfflineDb.instance.database;
    await db.delete(
      'pending_sales',
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> markError(String localId, String error) async {
    final db = await OfflineDb.instance.database;
    await db.rawUpdate(
      'UPDATE pending_sales SET attempts = attempts + 1, last_error = ? '
      'WHERE local_id = ?',
      [error, localId],
    );
  }
}

final saleOutboxProvider = Provider<SaleOutbox>((ref) => SaleOutbox());

/// Jumlah transaksi yang menunggu sinkron. Tidak reaktif otomatis (SQLite),
/// jadi panggil `refresh()` setelah enqueue / drain antrian.
class PendingSyncCountNotifier extends Notifier<int> {
  @override
  int build() {
    _load();
    return 0;
  }

  Future<void> _load() async {
    try {
      state = await ref.read(saleOutboxProvider).count();
    } catch (_) {
      state = 0;
    }
  }

  Future<void> refresh() => _load();
}

final pendingSyncCountProvider =
    NotifierProvider<PendingSyncCountNotifier, int>(
      PendingSyncCountNotifier.new,
    );

/// Jumlah transaksi gagal-permanen (dead-letter). Dipisah dari pending agar
/// banner bisa menampilkan indikator merah terpisah + buka sheet recovery.
/// Tidak reaktif otomatis — panggil refresh() setelah retry/discard/drain.
class DeadLetterCountNotifier extends Notifier<int> {
  @override
  int build() {
    _load();
    return 0;
  }

  Future<void> _load() async {
    try {
      state = await ref.read(saleOutboxProvider).deadLetterCount();
    } catch (_) {
      state = 0;
    }
  }

  Future<void> refresh() => _load();
}

final deadLetterCountProvider =
    NotifierProvider<DeadLetterCountNotifier, int>(
      DeadLetterCountNotifier.new,
    );

/// True bila error berasal dari masalah koneksi (offline / timeout), bukan
/// penolakan server (4xx/5xx). Dipakai untuk memutuskan: queue offline vs
/// lempar error nyata. Mencakup dua bentuk: DioException mentah dan String
/// pesan yang sudah di-handle BaseApiService.
bool isOfflineError(Object e) {
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      default:
        return false;
    }
  }
  final s = e.toString().toLowerCase();
  return s.contains('tidak ada koneksi') ||
      s.contains('koneksi timeout') ||
      s.contains('connection error') ||
      s.contains('failed host lookup') ||
      s.contains('socketexception');
}
