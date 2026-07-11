import 'dart:async';
import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications.dart';
import '../../../core/shared_prefs.dart';
import '../domain/app_notification.dart';

/// Repository / state holder untuk riwayat notifikasi lokal.
///
/// Implementasi pakai SharedPreferences JSON-list (anonymous, no server
/// roundtrip). Backend tetap punya `transactions` sebagai source of truth —
/// entry di sini hanya pointer + ringkasan supaya kasir bisa lihat ulang
/// notif yang sudah lewat.
///
/// Anatomi state:
///   - In-memory list `state` (sorted newest first)
///   - Setiap mutate disinkronkan ke SharedPreferences
///   - Auto-prune saat load: drop entry > [maxAgeDays], cap [maxEntries]
class NotificationHistory extends Notifier<List<AppNotification>> {
  /// Key di SharedPreferences. Pisah dari `mako.orders.history` punya
  /// mako-scan-qr karena scope-nya beda (kasir vs customer).
  static const _storageKey = 'mako.notif.history';
  static const _maxAgeDays = 30;
  static const _maxEntries = 200;

  /// Helper yang bisa dipanggil dari LUAR Riverpod (mis. dari FCM background
  /// isolate yang tidak punya ProviderScope). Tetap idempotent — entry dengan
  /// id yang sama akan dimerge (yang baru menang).
  static Future<void> addStandalone(AppNotification notif) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    final list = _parseList(raw);
    final filtered = list.where((e) => e.id != notif.id).toList();
    final merged = _prune([notif, ...filtered]);
    await prefs.setString(
      _storageKey,
      jsonEncode(merged.map((e) => e.toJson()).toList()),
    );
  }

  @override
  List<AppNotification> build() {
    final prefs = ref.watch(sharedPreferencesProvider);

    // Subscribe ke stream "FCM masuk" supaya state in-memory langsung
    // ter-update saat ada notif baru — tanpa user perlu navigasi keluar-
    // masuk halaman / restart app. Service sudah men-tulis ke disk; di
    // sini cuma push ke state Riverpod supaya UI rebuild.
    final sub = NotificationService.instance.onNotificationReceived.listen(
      _applyIncoming,
    );
    ref.onDispose(sub.cancel);

    final raw = prefs.getString(_storageKey);
    final list = _parseList(raw);
    return _prune(list);
  }

  /// Refresh state dari SharedPreferences. Dipakai saat app resume dari
  /// background — background isolate (`_firebaseMessagingBackgroundHandler`)
  /// menulis langsung ke disk tanpa lewat stream, jadi state in-memory
  /// main isolate ketinggalan sampai re-read.
  void refreshFromDisk() {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(_storageKey);
    state = _prune(_parseList(raw));
  }

  /// Listener stream — update state in-memory saja (disk sudah ditulis
  /// oleh service). Idempotent via dedupe by id.
  void _applyIncoming(AppNotification notif) {
    final next = [notif, ...state.where((e) => e.id != notif.id)];
    state = _prune(next);
  }

  void add(AppNotification notif) {
    // Idempotent — kalau id sudah ada (mis. user re-foreground app saat
    // background handler sudah save), replace bukan duplikat.
    final next = [
      notif,
      ...state.where((e) => e.id != notif.id),
    ];
    _commit(_prune(next));
  }

  void markRead(String id) {
    final next = state.map((e) {
      if (e.id != id) return e;
      return e.copyWith(read: true);
    }).toList();
    _commit(next);
  }

  void markAllRead() {
    final next = state.map((e) => e.copyWith(read: true)).toList();
    _commit(next);
  }

  void remove(String id) {
    final next = state.where((e) => e.id != id).toList();
    _commit(next);
  }

  void clearAll() {
    _commit(const []);
  }

  Future<void> _commit(List<AppNotification> list) async {
    state = list;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(
      _storageKey,
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  // ───────── helpers ─────────

  static List<AppNotification> _parseList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(AppNotification.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static List<AppNotification> _prune(List<AppNotification> input) {
    final cutoff = DateTime.now().subtract(const Duration(days: _maxAgeDays));
    final filtered = input.where((e) => e.receivedAt.isAfter(cutoff)).toList();
    filtered.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    if (filtered.length > _maxEntries) {
      return filtered.take(_maxEntries).toList();
    }
    return filtered;
  }
}

final notificationHistoryProvider =
    NotifierProvider<NotificationHistory, List<AppNotification>>(
  NotificationHistory.new,
);

/// Convenience provider untuk badge unread di AppBar. Dipisah supaya widget
/// badge hanya rebuild kalau count berubah, bukan tiap kali list ber-ubah
/// (mis. user mark-read 1 item → list change tapi count tetap).
final unreadNotificationCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationHistoryProvider);
  return list.where((e) => !e.read).length;
});
