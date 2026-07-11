import '../../../core/outlet_scope.dart';
import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/offline/entity_cache.dart';
import '../domain/order_type.dart';
import 'order_type_api_service.dart';

/// Cache offline tipe order per outlet. Checkout-blocking: canPay butuh
/// activeOrderType != null (turunan dari list ini).
final _orderTypeCache = EntityCache<OrderType>(
  'order_types',
  toJson: (t) => t.toCacheJson(),
  fromJson: OrderType.fromJson,
);

class OrderTypeRepository {
  final OrderTypeApiService apiService;
  final Ref _ref;

  OrderTypeRepository(this.apiService, this._ref);

  Future<List<OrderType>> getAll(String outletId) async {
    return readThroughCache(
      cache: _orderTypeCache,
      outletId: outletId,
      fetch: () async {
        try {
          final res = await apiService.getOrderTypes(outletId);
          return res
              .map((e) => OrderType.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (e) {
          if (e.toString().contains('relation') &&
              e.toString().contains('exist')) {
            return <OrderType>[];
          }
          rethrow;
        }
      },
    );
  }

  /// Order type default dari list yang sudah dimuat (cache provider).
  /// Fallback ke item pertama bila tak ada yang ditandai default.
  OrderType? getDefault() {
    final list = _ref.read(orderTypesFutureProvider).value ?? const [];
    return list.firstWhereOrNull((t) => t.isDefault) ??
        (list.isNotEmpty ? list.first : null);
  }

  /// Cari order type by nama (case-insensitive) dari cache — dipakai guard
  /// nama duplikat & set "Dine In" dari dialog meja.
  OrderType? getByName(String name) {
    final list = _ref.read(orderTypesFutureProvider).value ?? const [];
    final lower = name.trim().toLowerCase();
    return list.firstWhereOrNull((t) => t.name.trim().toLowerCase() == lower);
  }

  Future<void> save(OrderType type, {String? outletId}) async {
    if (type.id.isNotEmpty) {
      await apiService.updateOrderType(type.id, type.toJson());
    } else {
      final oid = outletId ?? type.outletRemoteId ?? '';
      await apiService.createOrderType(oid, type.toJson());
    }
  }

  Future<void> delete(String id) async {
    await apiService.deleteOrderType(id);
  }
}

final orderTypeRepositoryProvider = Provider<OrderTypeRepository>((ref) {
  return OrderTypeRepository(ref.watch(orderTypeApiServiceProvider), ref);
});

final orderTypesFutureProvider = FutureProvider<List<OrderType>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return [];
  return ref.watch(orderTypeRepositoryProvider).getAll(outletId);
});
