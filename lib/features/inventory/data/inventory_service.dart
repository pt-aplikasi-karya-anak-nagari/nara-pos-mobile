import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/outlet_scope.dart';

// Inventori produk di mobile (C1) — cek stok + restock/koreksi dari HP.
// Parity dengan halaman inventory web/backend.

class InventoryItem {
  final String productId;
  final String productName;
  final int stock;
  final String stockUnit;
  final int lowStockThreshold;
  final bool trackStock;
  final bool isLowStock;
  final bool isOutOfStock;
  final int variantCount;

  const InventoryItem({
    required this.productId,
    required this.productName,
    required this.stock,
    required this.stockUnit,
    required this.lowStockThreshold,
    required this.trackStock,
    required this.isLowStock,
    required this.isOutOfStock,
    required this.variantCount,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> j) => InventoryItem(
    productId: j['product_id']?.toString() ?? '',
    productName: j['product_name']?.toString() ?? '',
    stock: (j['stock'] as num?)?.toInt() ?? 0,
    stockUnit: j['stock_unit']?.toString() ?? 'pcs',
    lowStockThreshold: (j['low_stock_threshold'] as num?)?.toInt() ?? 0,
    trackStock: j['track_stock'] as bool? ?? false,
    isLowStock: j['is_low_stock'] as bool? ?? false,
    isOutOfStock: j['is_out_of_stock'] as bool? ?? false,
    variantCount: (j['variant_count'] as num?)?.toInt() ?? 0,
  );
}

class InventoryService extends BaseApiService {
  InventoryService(super.dio);

  Future<List<InventoryItem>> list(String outletId, {bool lowStockOnly = false, String search = ''}) async {
    return get(
      '/outlets/$outletId/inventory',
      queryParameters: {
        if (lowStockOnly) 'low_stock_only': 'true',
        if (search.isNotEmpty) 'search': search,
      },
      converter: (data) {
        final list = data as List<dynamic>? ?? const [];
        return list
            .map((e) => InventoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      },
    );
  }

  /// Restock (delta>0, type=restock) atau koreksi (delta<0, type=adjustment).
  Future<void> adjust(
    String outletId,
    String productId,
    int qtyDelta, {
    String reason = '',
  }) async {
    await post(
      '/outlets/$outletId/inventory/adjust',
      data: {
        'product_id': productId,
        'type': qtyDelta >= 0 ? 'restock' : 'adjustment',
        'qty_delta': qtyDelta,
        'reason': reason,
      },
      converter: (data) => data,
    );
  }
}

final inventoryServiceProvider = Provider<InventoryService>((ref) {
  return InventoryService(ref.watch(dioProvider));
});

final inventoryProvider = FutureProvider<List<InventoryItem>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return [];
  return ref.watch(inventoryServiceProvider).list(outletId);
});
