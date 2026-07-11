import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../core/outlet_scope.dart';
import '../../core/shared_prefs.dart';
import '../customers/domain/customer.dart';
import '../kasir/domain/cart_item.dart';
import '../kasir/providers.dart';
import '../order_types/domain/order_type.dart';
import '../tables/domain/pos_table.dart';
import 'data/draft_repository.dart';
import 'domain/draft_order.dart';

final draftRepositoryProvider = Provider<DraftRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return DraftRepository(prefs);
});

class DraftsNotifier extends Notifier<List<DraftOrder>> {
  @override
  List<DraftOrder> build() {
    final outletId = ref.watch(activeOutletIdProvider);
    if (outletId == null) return const [];
    final repo = ref.watch(draftRepositoryProvider);
    return repo.listForOutlet(outletId);
  }

  void _refresh() {
    final outletId = ref.read(activeOutletIdProvider);
    if (outletId == null) {
      state = const [];
      return;
    }
    final repo = ref.read(draftRepositoryProvider);
    state = repo.listForOutlet(outletId);
  }

  Future<void> save(DraftOrder draft) async {
    await ref.read(draftRepositoryProvider).save(draft);
    _refresh();
  }

  Future<void> delete(String id) async {
    await ref.read(draftRepositoryProvider).delete(id);
    _refresh();
  }
}

final draftsProvider = NotifierProvider<DraftsNotifier, List<DraftOrder>>(
  DraftsNotifier.new,
);

final draftsCountProvider = Provider<int>(
  (ref) => ref.watch(draftsProvider).length,
);

String _two(int v) => v.toString().padLeft(2, '0');

/// Auto-generate unique draft id berdasarkan timestamp microsecond.
String generateDraftId() => 'draft_${DateTime.now().microsecondsSinceEpoch}';

/// Auto-generate label draft default: "Draft DD/MM HH:mm".
String generateDraftName([DateTime? t]) {
  final dt = t ?? DateTime.now();
  return 'Draft ${_two(dt.day)}/${_two(dt.month)} '
      '${_two(dt.hour)}:${_two(dt.minute)}';
}

/// Simpan keranjang aktif sebagai draft baru, lalu kosongkan keranjang.
/// Mengembalikan `true` jika berhasil disimpan.
Future<bool> saveCurrentCartAsDraft(WidgetRef ref, {String? name}) async {
  final draft = buildDraftFromCurrentCart(
    ref,
    id: generateDraftId(),
    name: name ?? generateDraftName(),
  );
  if (draft == null) return false;
  await ref.read(draftsProvider.notifier).save(draft);
  ref.read(cartProvider.notifier).clear();
  ref.read(activeCustomerProvider.notifier).set(null);
  ref.read(activeTableProvider.notifier).set(null);
  return true;
}

/// Kumpulkan snapshot keranjang aktif menjadi [DraftOrder].
/// Mengembalikan `null` jika tidak ada outlet aktif atau cart kosong.
DraftOrder? buildDraftFromCurrentCart(
  WidgetRef ref, {
  required String id,
  required String name,
  DateTime? createdAt,
}) {
  final outletId = ref.read(activeOutletIdProvider);
  if (outletId == null) return null;

  final cart = ref.read(cartProvider);
  if (cart.isEmpty) return null;

  final customer = ref.read(activeCustomerProvider);
  final table = ref.read(activeTableProvider);
  final orderType = ref.read(activeOrderTypeProvider);
  final total = ref.read(totalProvider);
  final totalItems = ref.read(totalItemsProvider);

  final items = cart.map((c) {
    return DraftCartItem(
      productSnapshot: _productToJson(c),
      qty: c.qty,
      variantId: c.variantId,
      variantName: c.variantName,
      variantPrice: c.variantPrice,
      note: c.note,
      variantDiscountType: c.variantDiscountType,
      variantDiscountValue: c.variantDiscountValue,
      variantDiscountName: c.variantDiscountName,
      manualDiscountType: c.manualDiscountType,
      manualDiscountValue: c.manualDiscountValue,
    );
  }).toList();

  final now = DateTime.now();
  return DraftOrder(
    id: id,
    name: name,
    createdAt: createdAt ?? now,
    updatedAt: now,
    outletId: outletId,
    items: items,
    customerSnapshot: customer?.toJson(),
    tableSnapshot: table != null ? _tableToJson(table) : null,
    orderTypeSnapshot: orderType?.toJson(),
    totalAmount: total,
    totalItems: totalItems,
  );
}

/// Restore draft ke state kasir aktif: cart, customer, table, order type.
void restoreDraftToCart(WidgetRef ref, DraftOrder draft) {
  final orderTypeJson = draft.orderTypeSnapshot;
  if (orderTypeJson != null) {
    ref.read(activeOrderTypeProvider.notifier).set(
          OrderType.fromJson(orderTypeJson),
        );
  }

  final customerJson = draft.customerSnapshot;
  ref.read(activeCustomerProvider.notifier).set(
        customerJson != null ? Customer.fromJson(customerJson) : null,
      );

  final tableJson = draft.tableSnapshot;
  ref.read(activeTableProvider.notifier).set(
        tableJson != null ? _tableFromJson(tableJson) : null,
      );

  final items = draft.items
      .map(
        (di) => CartItem(
          di.product,
          di.qty,
          variantId: di.variantId,
          variantName: di.variantName,
          variantPrice: di.variantPrice,
          note: di.note,
          variantDiscountType: di.variantDiscountType,
          variantDiscountValue: di.variantDiscountValue,
          variantDiscountName: di.variantDiscountName,
          manualDiscountType: di.manualDiscountType,
          manualDiscountValue: di.manualDiscountValue,
        ),
      )
      .toList();
  ref.read(cartProvider.notifier).replaceAll(items);
}

Map<String, dynamic> _productToJson(CartItem c) {
  final p = c.product;
  return {
    'id': p.remoteId,
    'name': p.name,
    'description': p.description,
    'price': p.price,
    'stock': p.stock,
    'category': p.categoryName,
    'category_id': p.categoryId,
    'sku': p.sku,
    'barcode': p.barcode,
    'emoji': p.emoji,
    'image_url': p.imageUrl,
    'is_available': p.isAvailable,
    'track_stock': p.trackStock,
    'is_taxable': p.isTaxable,
    'discount_type': p.discountType,
    'discount_value': p.discountValue,
    'discount_name': p.discountName,
    'outlet_id': p.outletRemoteId,
    'is_favorite': p.isFavorite,
    'variants': p.variants
        .map((v) => {
              'id': v.remoteId,
              'product_id': v.productId,
              'name': v.name,
              'sku': v.sku,
              'price': v.price,
              'stock': v.stock,
            })
        .toList(),
  };
}

Map<String, dynamic> _tableToJson(PosTable t) => {
      'id': t.id,
      'name': t.name,
      'capacity': t.capacity,
      'status_index': t.statusIndex,
      'group_id': t.groupId,
      'outlet_id': t.outletRemoteId,
    };

PosTable _tableFromJson(Map<String, dynamic> json) => PosTable.fromJson(json);
