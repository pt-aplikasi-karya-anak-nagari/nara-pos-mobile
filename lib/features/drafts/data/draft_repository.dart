import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/draft_order.dart';

class DraftRepository {
  final SharedPreferences _prefs;
  static const _key = 'draft_orders_v1';

  DraftRepository(this._prefs);

  List<DraftOrder> _loadAll() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <DraftOrder>[];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map(
            (e) => DraftOrder.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (_) {
      return <DraftOrder>[];
    }
  }

  Future<void> _saveAll(List<DraftOrder> drafts) async {
    final list = drafts.map((d) => d.toJson()).toList();
    await _prefs.setString(_key, jsonEncode(list));
  }

  List<DraftOrder> listForOutlet(String outletId) {
    final all = _loadAll();
    final filtered = all.where((d) => d.outletId == outletId).toList();
    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered;
  }

  Future<void> save(DraftOrder draft) async {
    final all = _loadAll();
    final idx = all.indexWhere((d) => d.id == draft.id);
    if (idx >= 0) {
      all[idx] = draft;
    } else {
      all.add(draft);
    }
    await _saveAll(all);
  }

  Future<void> delete(String id) async {
    final all = _loadAll();
    all.removeWhere((d) => d.id == id);
    await _saveAll(all);
  }
}
