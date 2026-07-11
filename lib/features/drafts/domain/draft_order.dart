import '../../products/domain/product.dart';

class DraftCartItem {
  final Map<String, dynamic> productSnapshot;
  final int qty;
  final String? variantId;
  final String variantName;
  final double variantPrice;
  final String note;

  /// Snapshot diskon varian saat item masuk keranjang. Tanpa ini, order
  /// parkir dengan diskon varian akan ter-restore ke harga penuh.
  final String variantDiscountType;
  final double variantDiscountValue;
  final String variantDiscountName;

  /// Diskon manual per baris yang diberikan kasir. Juga harus diawetkan
  /// supaya total snapshot draft tetap cocok saat di-restore.
  final String manualDiscountType;
  final double manualDiscountValue;

  const DraftCartItem({
    required this.productSnapshot,
    required this.qty,
    this.variantId,
    this.variantName = '',
    this.variantPrice = 0,
    this.note = '',
    this.variantDiscountType = 'none',
    this.variantDiscountValue = 0,
    this.variantDiscountName = '',
    this.manualDiscountType = 'none',
    this.manualDiscountValue = 0,
  });

  Product get product => Product.fromJson(productSnapshot);

  Map<String, dynamic> toJson() => {
        'product': productSnapshot,
        'qty': qty,
        'variant_id': variantId,
        'variant_name': variantName,
        'variant_price': variantPrice,
        'note': note,
        'variant_discount_type': variantDiscountType,
        'variant_discount_value': variantDiscountValue,
        'variant_discount_name': variantDiscountName,
        'manual_discount_type': manualDiscountType,
        'manual_discount_value': manualDiscountValue,
      };

  factory DraftCartItem.fromJson(Map<String, dynamic> json) => DraftCartItem(
        productSnapshot: Map<String, dynamic>.from(json['product'] as Map),
        qty: (json['qty'] as num? ?? 0).toInt(),
        variantId: json['variant_id'] as String?,
        variantName: json['variant_name'] as String? ?? '',
        variantPrice: (json['variant_price'] as num? ?? 0).toDouble(),
        note: json['note'] as String? ?? '',
        variantDiscountType:
            json['variant_discount_type'] as String? ?? 'none',
        variantDiscountValue:
            (json['variant_discount_value'] as num? ?? 0).toDouble(),
        variantDiscountName: json['variant_discount_name'] as String? ?? '',
        manualDiscountType: json['manual_discount_type'] as String? ?? 'none',
        manualDiscountValue:
            (json['manual_discount_value'] as num? ?? 0).toDouble(),
      );
}

class DraftOrder {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String outletId;
  final List<DraftCartItem> items;
  final Map<String, dynamic>? customerSnapshot;
  final Map<String, dynamic>? tableSnapshot;
  final Map<String, dynamic>? orderTypeSnapshot;
  final double totalAmount;
  final int totalItems;

  const DraftOrder({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.outletId,
    required this.items,
    this.customerSnapshot,
    this.tableSnapshot,
    this.orderTypeSnapshot,
    required this.totalAmount,
    required this.totalItems,
  });

  String? get customerName => customerSnapshot?['name'] as String?;
  String? get tableName => tableSnapshot?['name'] as String?;
  String? get orderTypeName => orderTypeSnapshot?['name'] as String?;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'outlet_id': outletId,
        'items': items.map((e) => e.toJson()).toList(),
        'customer': customerSnapshot,
        'table': tableSnapshot,
        'order_type': orderTypeSnapshot,
        'total_amount': totalAmount,
        'total_items': totalItems,
      };

  factory DraftOrder.fromJson(Map<String, dynamic> json) => DraftOrder(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        outletId: json['outlet_id'] as String,
        items: (json['items'] as List? ?? const [])
            .map((e) =>
                DraftCartItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        customerSnapshot: json['customer'] != null
            ? Map<String, dynamic>.from(json['customer'] as Map)
            : null,
        tableSnapshot: json['table'] != null
            ? Map<String, dynamic>.from(json['table'] as Map)
            : null,
        orderTypeSnapshot: json['order_type'] != null
            ? Map<String, dynamic>.from(json['order_type'] as Map)
            : null,
        totalAmount: (json['total_amount'] as num? ?? 0).toDouble(),
        totalItems: (json['total_items'] as num? ?? 0).toInt(),
      );
}
