// C4: akses data modifier/add-on.
//  - KASIR (read): grup untuk sebuah produk saat menambah item.
//  - MANAJEMEN (read-write): CRUD grup per-outlet + attach ke produk.
// Di-cache per-produk / per-outlet lewat FutureProvider.family.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../outlet/data/outlet_service.dart';
import '../domain/modifier_group.dart';

class ModifierRepository {
  final Ref _ref;
  ModifierRepository(this._ref);

  OutletService get _svc => _ref.read(outletServiceProvider);

  // ── Kasir (read) ──────────────────────────────────────────────────

  Future<List<ModifierGroup>> groupsForProduct(
    String outletId,
    String productId,
  ) async {
    final list = await _svc.getProductModifierGroups(outletId, productId);
    return list
        .map(ModifierGroup.fromJson)
        // Hanya grup yang punya opsi (aktif) relevan ditampilkan di kasir.
        .where((g) => g.options.isNotEmpty)
        .toList();
  }

  /// ID grup yang saat ini melekat pada produk (tanpa filter opsi) — dipakai
  /// untuk inisialisasi dialog attach di form produk.
  Future<Set<String>> attachedGroupIds(
    String outletId,
    String productId,
  ) async {
    final list = await _svc.getProductModifierGroups(outletId, productId);
    return list
        .map((j) => j['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  // ── Manajemen (read-write) ────────────────────────────────────────

  Future<List<ModifierGroup>> listGroups(String outletId) async {
    final list = await _svc.listModifierGroups(outletId);
    return list.map(ModifierGroup.fromJson).toList();
  }

  Future<void> createGroup(String outletId, ModifierGroup group) =>
      _svc.createModifierGroup(outletId, group.toJson());

  Future<void> updateGroup(String outletId, String id, ModifierGroup group) =>
      _svc.updateModifierGroup(outletId, id, group.toJson());

  Future<void> deleteGroup(String outletId, String id) =>
      _svc.deleteModifierGroup(outletId, id);

  Future<void> setProductGroups(
    String outletId,
    String productId,
    List<String> groupIds,
  ) =>
      _svc.setProductModifierGroups(outletId, productId, groupIds);
}

final modifierRepositoryProvider = Provider<ModifierRepository>((ref) {
  return ModifierRepository(ref);
});

/// Grup modifier untuk (outletId, productId). Kosong bila produk tak punya
/// modifier atau saat offline/gagal (kasir tetap bisa menambah item langsung).
final productModifierGroupsProvider = FutureProvider.family<
    List<ModifierGroup>, ({String outletId, String productId})>((ref, arg) async {
  if (arg.outletId.isEmpty || arg.productId.isEmpty) return const [];
  return ref
      .read(modifierRepositoryProvider)
      .groupsForProduct(arg.outletId, arg.productId);
});

/// Semua grup modifier milik outlet — halaman manajemen & dialog attach.
final modifierGroupsProvider =
    FutureProvider.family<List<ModifierGroup>, String>((ref, outletId) async {
  if (outletId.isEmpty) return const [];
  return ref.read(modifierRepositoryProvider).listGroups(outletId);
});
