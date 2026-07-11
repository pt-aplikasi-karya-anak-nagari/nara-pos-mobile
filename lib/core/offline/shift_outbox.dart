import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'offline_db.dart';

/// Tipe operasi yang di-antrikan di pending_ops.
const String opShiftOpen = 'shift_open';
const String opShiftClose = 'shift_close';

/// Satu operasi tulis offline (buka/tutup shift) menunggu sinkron.
class PendingOp {
  final String localId;
  final String opType;
  final String outletId;
  final String clientRef;
  final Map<String, dynamic> payload;
  final String? dependsOn;
  final String? localShiftId;
  final String? serverShiftId;
  final String status; // 'pending' | 'dead'
  final DateTime createdAt;
  final String? occurredAt; // ISO8601 UTC
  final int attempts;
  final String? lastError;

  const PendingOp({
    required this.localId,
    required this.opType,
    required this.outletId,
    required this.clientRef,
    required this.payload,
    this.dependsOn,
    this.localShiftId,
    this.serverShiftId,
    this.status = 'pending',
    required this.createdAt,
    this.occurredAt,
    this.attempts = 0,
    this.lastError,
  });

  factory PendingOp.fromRow(Map<String, Object?> row) {
    final raw = row['payload'] as String? ?? '{}';
    return PendingOp(
      localId: row['local_id'] as String? ?? '',
      opType: row['op_type'] as String? ?? '',
      outletId: row['outlet_id'] as String? ?? '',
      clientRef: row['client_ref'] as String? ?? '',
      payload: jsonDecode(raw) as Map<String, dynamic>,
      dependsOn: row['depends_on'] as String?,
      localShiftId: row['local_shift_id'] as String?,
      serverShiftId: row['server_shift_id'] as String?,
      status: row['status'] as String? ?? 'pending',
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      occurredAt: row['occurred_at'] as String?,
      attempts: (row['attempts'] as int?) ?? 0,
      lastError: row['last_error'] as String?,
    );
  }
}

/// Outbox operasi shift (buka/tutup) berbasis SQLite (tabel pending_ops).
/// Mirror konvensi [SaleOutbox]: maxSyncAttempts + dead-letter, FIFO drain.
class ShiftOutbox {
  static const int maxSyncAttempts = 5;

  Future<String> enqueueOpen({
    required String outletId,
    required String localShiftId,
    required String clientRef,
    required Map<String, dynamic> payload,
    required DateTime occurredAt,
  }) async {
    final db = await OfflineDb.instance.database;
    final localId = 'op_${DateTime.now().microsecondsSinceEpoch}';
    await db.insert('pending_ops', {
      'local_id': localId,
      'op_type': opShiftOpen,
      'outlet_id': outletId,
      'client_ref': clientRef,
      'payload': jsonEncode(payload),
      'depends_on': null,
      'local_shift_id': localShiftId,
      'server_shift_id': null,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'attempts': 0,
    });
    return localId;
  }

  Future<String> enqueueClose({
    required String outletId,
    required String localShiftId,
    required String clientRef,
    required Map<String, dynamic> payload,
    required DateTime occurredAt,
    String? dependsOn, // local_id op open kalau belum sync
    String? serverShiftId, // kalau open sudah sync, target id langsung
  }) async {
    final db = await OfflineDb.instance.database;
    final localId = 'op_${DateTime.now().microsecondsSinceEpoch}';
    await db.insert('pending_ops', {
      'local_id': localId,
      'op_type': opShiftClose,
      'outlet_id': outletId,
      'client_ref': clientRef,
      'payload': jsonEncode(payload),
      'depends_on': dependsOn,
      'local_shift_id': localShiftId,
      'server_shift_id': serverShiftId,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'attempts': 0,
    });
    return localId;
  }

  Future<List<PendingOp>> _activeByType(String opType) async {
    final db = await OfflineDb.instance.database;
    final rows = await db.query(
      'pending_ops',
      where: "op_type = ? AND status = 'pending' AND attempts < ?",
      whereArgs: [opType, maxSyncAttempts],
      orderBy: 'created_at ASC',
    );
    return rows.map(PendingOp.fromRow).toList();
  }

  Future<List<PendingOp>> opensPending() => _activeByType(opShiftOpen);
  Future<List<PendingOp>> closesPending() => _activeByType(opShiftClose);

  /// local_id op open untuk satu localShiftId (dipakai close sebagai depends_on).
  Future<String?> openLocalIdFor(String localShiftId) async {
    final db = await OfflineDb.instance.database;
    final rows = await db.query(
      'pending_ops',
      columns: ['local_id'],
      where: 'op_type = ? AND local_shift_id = ?',
      whereArgs: [opShiftOpen, localShiftId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['local_id'] as String?;
  }

  /// Setelah open ter-ACK: catat server_shift_id ke SEMUA op untuk shift ini
  /// (terutama close yang menunggu). Ini satu-satunya id-remap yang diperlukan.
  Future<void> setServerShiftId(String localShiftId, String serverId) async {
    final db = await OfflineDb.instance.database;
    await db.update(
      'pending_ops',
      {'server_shift_id': serverId},
      where: 'local_shift_id = ?',
      whereArgs: [localShiftId],
    );
  }

  /// Cascade dead-letter: saat open ditolak permanen, tandai open + close
  /// turunannya 'dead' supaya tidak menggantung selamanya.
  Future<void> markDeadCascade(String localShiftId, String reason) async {
    final db = await OfflineDb.instance.database;
    await db.update(
      'pending_ops',
      {'status': 'dead', 'last_error': reason},
      where: "local_shift_id = ? AND status != 'done'",
      whereArgs: [localShiftId],
    );
  }

  Future<void> remove(String localId) async {
    final db = await OfflineDb.instance.database;
    await db.delete('pending_ops', where: 'local_id = ?', whereArgs: [localId]);
  }

  Future<void> markError(String localId, String error) async {
    final db = await OfflineDb.instance.database;
    await db.rawUpdate(
      'UPDATE pending_ops SET attempts = attempts + 1, last_error = ? '
      'WHERE local_id = ?',
      [error, localId],
    );
  }

  Future<void> retry(String localId) async {
    final db = await OfflineDb.instance.database;
    await db.update(
      'pending_ops',
      {'attempts': 0, 'last_error': null, 'status': 'pending'},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// Hitungan antrian aktif (untuk banner). Dead-letter dikecualikan.
  Future<int> count() async {
    final db = await OfflineDb.instance.database;
    final r = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM pending_ops WHERE status = 'pending' AND attempts < ?",
      [maxSyncAttempts],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<int> deadLetterCount() async {
    final db = await OfflineDb.instance.database;
    final r = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM pending_ops WHERE status = 'dead' OR attempts >= ?",
      [maxSyncAttempts],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<List<PendingOp>> deadLetters() async {
    final db = await OfflineDb.instance.database;
    final rows = await db.query(
      'pending_ops',
      where: "status = 'dead' OR attempts >= ?",
      whereArgs: [maxSyncAttempts],
      orderBy: 'created_at ASC',
    );
    return rows.map(PendingOp.fromRow).toList();
  }
}

final shiftOutboxProvider = Provider<ShiftOutbox>((ref) => ShiftOutbox());

/// Jumlah operasi shift menunggu sinkron (buka/tutup). Tidak reaktif —
/// panggil refresh() setelah enqueue / drain.
class PendingShiftSyncCountNotifier extends Notifier<int> {
  @override
  int build() {
    _load();
    return 0;
  }

  Future<void> _load() async {
    try {
      state = await ref.read(shiftOutboxProvider).count();
    } catch (_) {
      state = 0;
    }
  }

  Future<void> refresh() => _load();
}

final pendingShiftSyncCountProvider =
    NotifierProvider<PendingShiftSyncCountNotifier, int>(
      PendingShiftSyncCountNotifier.new,
    );

/// Jumlah operasi shift gagal-permanen (dead-letter).
class ShiftDeadLetterCountNotifier extends Notifier<int> {
  @override
  int build() {
    _load();
    return 0;
  }

  Future<void> _load() async {
    try {
      state = await ref.read(shiftOutboxProvider).deadLetterCount();
    } catch (_) {
      state = 0;
    }
  }

  Future<void> refresh() => _load();
}

final shiftDeadLetterCountProvider =
    NotifierProvider<ShiftDeadLetterCountNotifier, int>(
      ShiftDeadLetterCountNotifier.new,
    );
