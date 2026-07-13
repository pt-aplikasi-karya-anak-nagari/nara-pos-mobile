import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/outlet_scope.dart';

/// Bahan baku (ingredient) — view + restock dari HP (B1 di mobile).
class Ingredient {
  final String id;
  final String name;
  final String unit;
  final double stock;
  final double costPerUnit;
  final double lowStockThreshold;

  const Ingredient({
    required this.id,
    required this.name,
    required this.unit,
    required this.stock,
    required this.costPerUnit,
    required this.lowStockThreshold,
  });

  bool get isLowStock => lowStockThreshold > 0 && stock <= lowStockThreshold;

  factory Ingredient.fromJson(Map<String, dynamic> j) => Ingredient(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    unit: j['unit']?.toString() ?? '',
    stock: (j['stock'] as num?)?.toDouble() ?? 0,
    costPerUnit: (j['cost_per_unit'] as num?)?.toDouble() ?? 0,
    lowStockThreshold: (j['low_stock_threshold'] as num?)?.toDouble() ?? 0,
  );
}

/// Resep (read-only di mobile) — tampilkan HPP & komposisi.
class RecipeItem {
  final String ingredientName;
  final String ingredientUnit;
  final double qty;
  final double lineCost;
  const RecipeItem({
    required this.ingredientName,
    required this.ingredientUnit,
    required this.qty,
    required this.lineCost,
  });

  factory RecipeItem.fromJson(Map<String, dynamic> j) => RecipeItem(
    ingredientName: j['ingredient_name']?.toString() ?? '',
    ingredientUnit: j['ingredient_unit']?.toString() ?? '',
    qty: (j['qty'] as num?)?.toDouble() ?? 0,
    lineCost: (j['line_cost'] as num?)?.toDouble() ?? 0,
  );
}

class Recipe {
  final String id;
  final String productName;
  final double hpp;
  final double yieldQty;
  final List<RecipeItem> items;
  const Recipe({
    required this.id,
    required this.productName,
    required this.hpp,
    required this.yieldQty,
    required this.items,
  });

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
    id: j['id']?.toString() ?? '',
    productName: j['product_name']?.toString() ?? '',
    hpp: (j['hpp'] as num?)?.toDouble() ?? 0,
    yieldQty: (j['yield_qty'] as num?)?.toDouble() ?? 1,
    items: (j['items'] as List<dynamic>? ?? const [])
        .map((e) => RecipeItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

/// Satu baris transfer stok: bahan sumber (di outlet asal) dipetakan ke bahan
/// tujuan (di outlet tujuan) + qty dalam satuan pakai.
class StockTransferItem {
  final String id;
  final String fromIngredientId;
  final String toIngredientId;
  final String fromIngredientName;
  final String toIngredientName;
  final double qty;

  const StockTransferItem({
    required this.id,
    required this.fromIngredientId,
    required this.toIngredientId,
    required this.fromIngredientName,
    required this.toIngredientName,
    required this.qty,
  });

  factory StockTransferItem.fromJson(Map<String, dynamic> j) => StockTransferItem(
    id: j['id']?.toString() ?? '',
    fromIngredientId: j['from_ingredient_id']?.toString() ?? '',
    toIngredientId: j['to_ingredient_id']?.toString() ?? '',
    fromIngredientName: j['from_ingredient_name']?.toString() ?? '',
    toIngredientName: j['to_ingredient_name']?.toString() ?? '',
    qty: (j['qty'] as num?)?.toDouble() ?? 0,
  );
}

/// Transfer stok bahan baku antar-outlet (B2). Header dari `list`, lengkap
/// dengan `items` dari `detail`.
class StockTransfer {
  final String id;
  final String fromOutletId;
  final String toOutletId;
  final String fromOutletName;
  final String toOutletName;
  final String status;
  final String note;
  final DateTime? createdAt;
  final List<StockTransferItem> items;

  const StockTransfer({
    required this.id,
    required this.fromOutletId,
    required this.toOutletId,
    required this.fromOutletName,
    required this.toOutletName,
    required this.status,
    required this.note,
    required this.createdAt,
    required this.items,
  });

  factory StockTransfer.fromJson(Map<String, dynamic> j) => StockTransfer(
    id: j['id']?.toString() ?? '',
    fromOutletId: j['from_outlet_id']?.toString() ?? '',
    toOutletId: j['to_outlet_id']?.toString() ?? '',
    fromOutletName: j['from_outlet_name']?.toString() ?? '',
    toOutletName: j['to_outlet_name']?.toString() ?? '',
    status: j['status']?.toString() ?? '',
    note: j['note']?.toString() ?? '',
    createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
    items: (j['items'] as List<dynamic>? ?? const [])
        .map((e) => StockTransferItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

class BahanBakuService extends BaseApiService {
  BahanBakuService(super.dio);

  Future<List<Ingredient>> listIngredients(String outletId) async {
    return get(
      '/outlets/$outletId/ingredients',
      converter: (data) {
        final list = data as List<dynamic>? ?? const [];
        return list
            .map((e) => Ingredient.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      },
    );
  }

  Future<void> adjustStock(String ingredientId, double delta, {String note = ''}) async {
    await post(
      '/ingredients/$ingredientId/adjust',
      data: {'delta': delta, 'note': note},
      converter: (data) => data,
    );
  }

  /// Stock opname banyak bahan sekaligus (B1). Server menghitung delta =
  /// actual − current per bahan dan MELEWATI baris yang tidak berubah, lalu
  /// mengembalikan jumlah bahan yang benar-benar disesuaikan (`changed_count`).
  Future<int> bulkOpname(
    String outletId,
    List<({String ingredientId, double actualQty})> items, {
    String? note,
  }) async {
    return post<int>(
      '/outlets/$outletId/ingredients/opname',
      data: {
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        'items': items
            .map((e) => {
                  'ingredient_id': e.ingredientId,
                  'actual_qty': e.actualQty,
                })
            .toList(),
      },
      converter: (data) =>
          (data is Map ? (data['changed_count'] as num?)?.toInt() : null) ?? 0,
    );
  }

  /// Buat transfer stok dari [fromOutletId] (outlet asal) ke [toOutletId].
  /// Melempar pesan ramah saat stok bahan asal tidak cukup (HTTP 409).
  Future<StockTransfer> createStockTransfer(
    String fromOutletId, {
    required String toOutletId,
    String? note,
    required List<({String fromIngredientId, String toIngredientId, double qty})> items,
  }) async {
    try {
      final res = await dio.post<Map<String, dynamic>>(
        '/outlets/$fromOutletId/stock-transfers',
        data: {
          'to_outlet_id': toOutletId,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          'items': items
              .map((e) => {
                    'from_ingredient_id': e.fromIngredientId,
                    'to_ingredient_id': e.toIngredientId,
                    'qty': e.qty,
                  })
              .toList(),
        },
      );
      final data = res.data?['data'];
      return StockTransfer.fromJson(
        data is Map<String, dynamic> ? data : const {},
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw 'Stok bahan sumber tidak cukup untuk ditransfer.';
      }
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      throw msg ?? 'Gagal membuat transfer stok';
    }
  }

  Future<List<StockTransfer>> listStockTransfers(String outletId) async {
    return get(
      '/outlets/$outletId/stock-transfers',
      converter: (data) {
        final list = data as List<dynamic>? ?? const [];
        return list
            .map((e) =>
                StockTransfer.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      },
    );
  }

  Future<StockTransfer> getStockTransfer(String id) async {
    return get(
      '/stock-transfers/$id',
      converter: (data) =>
          StockTransfer.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  Future<List<Recipe>> listRecipes(String outletId) async {
    return get(
      '/outlets/$outletId/recipes',
      converter: (data) {
        final list = data as List<dynamic>? ?? const [];
        return list
            .map((e) => Recipe.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      },
    );
  }
}

final bahanBakuServiceProvider = Provider<BahanBakuService>((ref) {
  return BahanBakuService(ref.watch(dioProvider));
});

final ingredientsProvider = FutureProvider<List<Ingredient>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return [];
  return ref.watch(bahanBakuServiceProvider).listIngredients(outletId);
});

final recipesProvider = FutureProvider<List<Recipe>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return [];
  return ref.watch(bahanBakuServiceProvider).listRecipes(outletId);
});

/// Daftar bahan baku untuk outlet tertentu (dipakai transfer stok memuat bahan
/// outlet tujuan, di luar outlet aktif).
final outletIngredientsProvider =
    FutureProvider.family<List<Ingredient>, String>((ref, outletId) async {
      return ref.watch(bahanBakuServiceProvider).listIngredients(outletId);
    });

/// Riwayat transfer stok yang melibatkan outlet aktif (asal atau tujuan).
final stockTransfersProvider = FutureProvider<List<StockTransfer>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return [];
  return ref.watch(bahanBakuServiceProvider).listStockTransfers(outletId);
});
