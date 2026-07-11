import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../products/domain/category.dart';
import '../../core/outlet_scope.dart';
import '../../core/offline/product_cache.dart';
import '../../core/offline/sale_outbox.dart';

import '../products/domain/product.dart';
import '../order_types/domain/order_type.dart';
import '../order_types/data/order_type_repository.dart';
import '../user/data/auth_service.dart';
import '../customers/domain/customer.dart';
import '../tables/domain/pos_table.dart';
import '../outlet/data/outlet_service.dart';
import 'domain/cart_item.dart';

// ─── Cart ─────────────────────────────────────────────────────────────────────
class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() {
    // Reset keranjang jika outlet berubah
    ref.listen(activeOutletIdProvider, (previous, next) {
      if (previous != next) {
        state = const [];
      }
    });

    ref.listen(authProvider, (previous, next) {
      if (previous?.user?.remoteId != next.user?.remoteId) {
        state = const [];
      }
    });

    // Reset keranjang jika ada perubahan data produk (update/tambah/hapus)
    final outletId = ref.watch(activeOutletIdProvider);
    if (outletId != null) {
      ref.listen(outletCategoriesProvider(outletId), (previous, next) {
        if (previous != null && previous.hasValue && next.hasValue) {
          state = const [];
        }
      });
    }

    return const [];
  }

  void add(
    Product p, {
    ProductVariant? variant,
    List<CartModifier> modifiers = const [],
  }) {
    final vId = variant?.remoteId;
    // C4: baris digabung hanya bila varian DAN pilihan modifier sama persis
    // (kunci option id terurut). Topping berbeda = baris berbeda.
    final key = _modifierKeyOf(modifiers);
    final idx = state.indexWhere(
      (c) => c.sameVariantAs(p, vId) && c.modifierKey == key,
    );
    if (idx >= 0) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == idx) state[i].copyWith(qty: state[i].qty + 1) else state[i],
      ];
    } else {
      state = [...state, CartItem.from(p, 1, variant, modifiers)];
    }
  }

  static String _modifierKeyOf(List<CartModifier> mods) {
    if (mods.isEmpty) return '';
    final ids = mods.map((m) => m.optionId).toList()..sort();
    return ids.join(',');
  }

  void setOrderType(OrderType? ot) {
    // No adjustments needed anymore
  }

  void remove(Product p, {ProductVariant? variant}) {
    final vId = variant?.remoteId;
    final idx = state.indexWhere((c) => c.sameVariantAs(p, vId));
    if (idx < 0) return;
    if (state[idx].qty > 1) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == idx) state[i].copyWith(qty: state[i].qty - 1) else state[i],
      ];
    } else {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i != idx) state[i],
      ];
    }
  }

  void removeLine(String? productId, String? variantId) {
    state = [
      for (final c in state)
        if (!(c.product.remoteId == productId && c.variantId == variantId)) c,
    ];
  }

  // C4: naik/turun kuantitas pada BARIS tertentu (by index). Wajib dipakai
  // stepper di panel keranjang karena satu produk bisa punya beberapa baris
  // dengan modifier berbeda — remove/add by product+varian saja bisa mengubah
  // baris yang salah. copyWith mempertahankan modifiers.
  void incrementAt(int index) {
    if (index < 0 || index >= state.length) return;
    state = [
      for (int i = 0; i < state.length; i++)
        if (i == index) state[i].copyWith(qty: state[i].qty + 1) else state[i],
    ];
  }

  void decrementAt(int index) {
    if (index < 0 || index >= state.length) return;
    if (state[index].qty > 1) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == index)
            state[i].copyWith(qty: state[i].qty - 1)
          else
            state[i],
      ];
    } else {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i != index) state[i],
      ];
    }
  }

  // C4: kurangi satu unit dari baris TERAKHIR produk ini (kontrol kasar di grid
  // produk — baris presisi diatur di panel keranjang). Deterministik: config
  // yang paling baru ditambahkan yang dikurangi.
  void decrementLastOf(Product p, {ProductVariant? variant}) {
    final vId = variant?.remoteId;
    final idx = state.lastIndexWhere((c) => c.sameVariantAs(p, vId));
    if (idx < 0) return;
    decrementAt(idx);
  }

  /// Update catatan untuk baris cart pada [index]. Pakai index (bukan key
  /// product/variant) supaya pesanan custom dengan nama sama tetap bisa
  /// dibedakan satu sama lain.
  void setNote(int index, String note) {
    if (index < 0 || index >= state.length) return;
    state = [
      for (int i = 0; i < state.length; i++)
        if (i == index) state[i].copyWith(note: note) else state[i],
    ];
  }

  /// Set diskon manual per baris. Tipe `'none'` (atau value <= 0) menghapus
  /// diskon manual. Tipe valid: `'percent'` (0-100) | `'fixed'` (Rp).
  void setLineDiscount(int index, String type, double value) {
    if (index < 0 || index >= state.length) return;
    final normalizedType = (type == 'percent' || type == 'fixed') && value > 0
        ? type
        : 'none';
    final normalizedValue = normalizedType == 'none' ? 0.0 : value;
    state = [
      for (int i = 0; i < state.length; i++)
        if (i == index)
          state[i].copyWith(
            manualDiscountType: normalizedType,
            manualDiscountValue: normalizedValue,
          )
        else
          state[i],
    ];
  }

  /// Hapus diskon manual pada baris [index].
  void clearLineDiscount(int index) =>
      setLineDiscount(index, 'none', 0);

  void clear() => state = const [];

  /// Ganti seluruh isi keranjang dengan [items]. Dipakai saat restore draft.
  void replaceAll(List<CartItem> items) => state = List.unmodifiable(items);
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);

// Semua nilai uang dibulatkan ke rupiah penuh agar konsisten dengan input
// kasir (selalu bilangan bulat) dan tidak menumpuk pecahan saat di-SUM
// untuk perhitungan ekspektasi kas di shift.
final subtotalProvider = Provider<double>(
  (ref) =>
      ref.watch(cartProvider).fold(0.0, (s, c) => s + c.subtotal).roundToDouble(),
);
// Subtotal HANYA dari baris yang kena pajak (item non-pajak dikecualikan).
// Menjadi basis pajak agar preview kasir cocok persis dengan pajak yang
// dihitung server (server otoritatif & mengecualikan item is_taxable=false).
final taxableSubtotalProvider = Provider<double>(
  (ref) => ref
      .watch(cartProvider)
      .where((c) => c.isTaxable)
      .fold(0.0, (s, c) => s + c.subtotal)
      .roundToDouble(),
);
final originalSubtotalProvider = Provider<double>(
  (ref) => ref
      .watch(cartProvider)
      .fold(0.0, (s, c) => s + (c.basePrice * c.qty))
      .roundToDouble(),
);
final discountTotalProvider = Provider<double>(
  (ref) =>
      ref.watch(cartProvider).fold(0.0, (s, c) => s + c.lineDiscount).roundToDouble(),
);
// Rincian pajak/biaya lewat Outlet.computeTaxBreakdown — SATU sumber kebenaran
// yang menangani mode tax-INCLUSIVE (harga produk sudah termasuk PPN): PPN
// di-back-out dari harga, service charge dihitung dari NET, dan total TIDAK
// menambah pajak di atas. Untuk mode exclusive hasilnya identik dengan
// perhitungan lama (subtotal + SC + PPN). Basis = subtotal cart (setelah diskon
// per item). Sebelumnya provider ini selalu menambah PPN di atas → salah untuk
// outlet tax-inclusive (dobel-charge PPN).
final _taxBreakdownProvider = Provider<
    ({double subtotal, double serviceCharge, double tax, double grandTotal})>((ref) {
  final subtotal = ref.watch(subtotalProvider);
  final taxableSubtotal = ref.watch(taxableSubtotalProvider);
  final outlet = ref.watch(activeOutletProvider);
  if (outlet == null) {
    return (subtotal: subtotal, serviceCharge: 0.0, tax: 0.0, grandTotal: subtotal);
  }
  // Pajak dihitung HANYA dari taxableSubtotal (item non-pajak dikecualikan),
  // service charge tetap dari subtotal penuh — sama seperti server.
  return outlet.computeTaxBreakdown(subtotal, taxableSubtotal: taxableSubtotal);
});

final serviceChargeProvider = Provider<double>(
  (ref) => ref.watch(_taxBreakdownProvider).serviceCharge.roundToDouble(),
);

final taxProvider = Provider<double>(
  (ref) => ref.watch(_taxBreakdownProvider).tax.roundToDouble(),
);

// grandTotal = subtotal + SC (+ PPN kalau exclusive). Diskon order-level (promo/
// poin) dikurangi di payment_sheet dari nilai ini.
final totalProvider = Provider<double>(
  (ref) => ref.watch(_taxBreakdownProvider).grandTotal.roundToDouble(),
);
final totalItemsProvider = Provider<int>(
  (ref) => ref.watch(cartProvider).fold(0, (s, c) => s + c.qty),
);

final qtyProvider = Provider.family<int, String?>((ref, productId) {
  final cart = ref.watch(cartProvider);
  return cart
      .where((c) => c.product.remoteId == productId)
      .fold(0, (s, c) => s + c.qty);
});

// ─── Favorites (persisted on Product.isFavorite) ──────────────────────────────
final favoriteProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
  return products.where((p) => p.isFavorite).toList();
});

final favoritesCountProvider = Provider<int>(
  (ref) => ref.watch(favoriteProductsProvider).length,
);

final favoritesUpdateTriggerProvider = StateProvider<int>((ref) => 0);

final selectedMainCategoryProvider = StateProvider<String>((ref) => 'Semua');

// ─── Filter ───────────────────────────────────────────────────────────────────
final selectedCategoryIdProvider = StateProvider<String?>((ref) => null);
final productSearchQueryProvider = StateProvider<String>((ref) => '');

// ─── API Replacement Providers ────────────────────────────────────────────────
final productsStreamProvider = FutureProvider<List<Product>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return const [];

  final categoryId = ref.watch(selectedCategoryIdProvider);
  final cache = ref.read(productCacheProvider);

  try {
    final products = await ref
        .watch(outletServiceProvider)
        .getProducts(outletId, categoryId: categoryId);
    // Cache hanya saat fetch "semua kategori" supaya cache selalu lengkap
    // untuk dipakai offline (filter kategori dilakukan lokal saat offline).
    if (categoryId == null) {
      await cache.replaceAll(outletId, products);
    }
    return products;
  } catch (e) {
    // Offline → layani dari cache. Filter kategori secara lokal supaya
    // pemilihan kategori tetap berfungsi tanpa koneksi.
    if (isOfflineError(e)) {
      final cached = await cache.getAll(outletId);
      if (categoryId == null) return cached;
      return cached.where((p) => p.categoryId == categoryId).toList();
    }
    rethrow;
  }
});

final categoriesStreamProvider = Provider<AsyncValue<List<Category>>>((ref) {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return const AsyncValue.data([]);
  return ref.watch(outletCategoriesProvider(outletId));
});

final categoriesByOutletStreamProvider =
    Provider.family<AsyncValue<List<Category>>, String>((ref, outletId) {
      return ref.watch(outletCategoriesProvider(outletId));
    });

final categoryNamesProvider = Provider<List<String>>((ref) {
  final cats = ref.watch(categoriesStreamProvider).value ?? const <Category>[];
  return cats.map((c) => c.name).toList();
});

// ─── Grid Density ─────────────────────────────────────────────────────────────
/// Menyesuaikan jumlah kolom grid produk (-1, 0, +1, dsb dari default).
class GridDensityNotifier extends Notifier<int> {
  @override
  int build() => 1;

  void increase() => state = (state + 1).clamp(-1, 2);
  void decrease() => state = (state - 1).clamp(-1, 2);
  void set(int val) => state = val.clamp(-1, 2);
}

final gridDensityProvider = NotifierProvider<GridDensityNotifier, int>(
  GridDensityNotifier.new,
);

class ActiveOrderTypeNotifier extends Notifier<OrderType?> {
  @override
  OrderType? build() {
    final orderTypesAsync = ref.watch(orderTypesFutureProvider);
    return orderTypesAsync.whenOrNull(
      data: (list) {
        if (list.isEmpty) return null;
        try {
          return list.firstWhere((ot) => ot.isDefault);
        } catch (_) {
          return list.first;
        }
      },
    );
  }

  void set(OrderType? ot) => state = ot;
}

final activeOrderTypeProvider =
    NotifierProvider<ActiveOrderTypeNotifier, OrderType?>(
      ActiveOrderTypeNotifier.new,
    );

class ActiveCustomerNotifier extends Notifier<Customer?> {
  @override
  Customer? build() => null;

  void set(Customer? customer) => state = customer;
}

final activeCustomerProvider =
    NotifierProvider<ActiveCustomerNotifier, Customer?>(
      ActiveCustomerNotifier.new,
    );

class ActiveTableNotifier extends Notifier<PosTable?> {
  @override
  PosTable? build() {
    // Reset meja jika order type berubah ke selain Dine In
    ref.listen(activeOrderTypeProvider, (previous, next) {
      if (next?.name != 'Dine In') {
        state = null;
      }
    });
    return null;
  }

  void set(PosTable? table) => state = table;
}

final activeTableProvider = NotifierProvider<ActiveTableNotifier, PosTable?>(
  ActiveTableNotifier.new,
);
