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
