import '../../../core/outlet_scope.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/offline/entity_cache.dart';
import '../domain/pos_table.dart';
import '../domain/table_group.dart';
import 'table_api_service.dart';
import 'table_group_api_service.dart';

/// Cache offline meja & area per outlet. Checkout-blocking untuk Dine In:
/// pemilihan meja butuh daftar meja/area. Meja = id server (read-only), aman
/// di-cache tanpa hazard create-before-use.
final _tableCache = EntityCache<PosTable>(
  'tables',
  toJson: (t) => t.toCacheJson(),
  fromJson: PosTable.fromJson,
);
final _tableGroupCache = EntityCache<TableGroup>(
  'table_groups',
  toJson: (g) => g.toCacheJson(),
  fromJson: TableGroup.fromJson,
);

class TableRepository {
  final PosTableApiService tableApi;
  final TableGroupApiService groupApi;

  TableRepository(this.tableApi, this.groupApi);

  Future<List<PosTable>> getTables(String outletId) async {
    return readThroughCache(
      cache: _tableCache,
      outletId: outletId,
      fetch: () async {
        try {
          final res = await tableApi.getPosTables(outletId);
          return res
              .map((e) => PosTable.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (e) {
          if (e.toString().contains('relation') &&
              e.toString().contains('exist')) {
            return <PosTable>[];
          }
          rethrow;
        }
      },
    );
  }

  Future<List<TableGroup>> getGroups(String outletId) async {
    return readThroughCache(
      cache: _tableGroupCache,
      outletId: outletId,
      fetch: () async {
        try {
          final res = await groupApi.getTableGroups(outletId);
          return res
              .map((e) => TableGroup.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (e) {
          if (e.toString().contains('relation') &&
              e.toString().contains('exist')) {
            return <TableGroup>[];
          }
          rethrow;
        }
      },
    );
  }

  Future<void> saveTable(PosTable table) async {
    if (table.id.isNotEmpty) {
      await tableApi.updatePosTable(table.id, table.toJson());
    } else {
      final outletId = table.outletRemoteId ?? '';
      await tableApi.createPosTable(outletId, table.toJson());
    }
  }

  Future<void> removeTable(String id) async {
    await tableApi.deletePosTable(id);
  }

  Future<void> saveGroup(TableGroup group) async {
    if (group.id.isNotEmpty) {
      await groupApi.updateTableGroup(group.id, group.toJson());
    } else {
      final outletId = group.outletRemoteId ?? '';
      await groupApi.createTableGroup(outletId, group.toJson());
    }
  }

  Future<void> removeGroup(String id) async {
    await groupApi.deleteTableGroup(id);
  }

  /// Set status meja (Tersedia/Terisi/Reserved). Pakai endpoint dedicated
  /// supaya tidak perlu kirim ulang seluruh field meja (yang akan di-validate
  /// ulang oleh backend) — hanya kolom status_index yang berubah.
  Future<void> updateTableStatus(String id, int statusIndex) async {
    await tableApi.updateStatus(id, statusIndex);
  }
}

final tableRepositoryProvider = Provider<TableRepository>((ref) {
  return TableRepository(
    ref.watch(posTableApiServiceProvider),
    ref.watch(tableGroupApiServiceProvider)
  );
});

final tablesFutureProvider = FutureProvider<List<PosTable>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return [];
  return ref.watch(tableRepositoryProvider).getTables(outletId);
});

final tableGroupsFutureProvider = FutureProvider<List<TableGroup>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return [];
  final repo = ref.watch(tableRepositoryProvider);
  // Fetch groups & meja paralel lalu gabungkan: backend `getGroups` tidak
  // memuat field `tables` di tiap area, jadi kalau Flutter cuma pakai
  // groups saja, `group.tables` akan selalu kosong (meja tidak muncul di
  // area card walau datanya ada di DB).
  final results = await Future.wait([
    repo.getGroups(outletId),
    repo.getTables(outletId),
  ]);
  final groups = results[0] as List<TableGroup>;
  final tables = results[1] as List<PosTable>;
  for (final g in groups) {
    g.tables = tables.where((t) => t.groupId == g.id).toList();
  }
  return groups;
});
