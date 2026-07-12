import '../../../core/format.dart';
class Product {
  String? remoteId;
  String name;
  String description;
  double price;
  int stock;
  // lowStockThreshold: kalau stock <= threshold (dan threshold > 0),
  // produk tampil sebagai "stok menipis" di kasir. Threshold = 0
  // berarti tidak ada alert untuk produk ini.
  int lowStockThreshold;
  // stockUnit untuk display di kasir ("5 pcs", "200 ml", "1.5 kg").
  String stockUnit;
  // Counter total qty terjual all-time. Backend increment di setiap
  // transactions.Create. Dipakai badge "Terjual: N" (opt-in lewat
  // outlet.show_sold_count).
  int sold;
  String? categoryName;
  String? categoryId;
  String? sku;
  String? barcode;
  String emoji;
  String? imageUrl;
  bool isAvailable;
  bool trackStock;
  // Auto-86 (out-of-ingredient): dihitung backend dari stok bahan/resep.
  // availablePortions = maksimum porsi yang masih bisa dibuat. null = tak
  // dibatasi (produk tanpa resep). 0 = habis. Positif = sisa porsi.
  int? availablePortions;
  // isInStock: false → bahan habis, produk tak bisa dijual (di-disable di
  // kasir). Default true saat field absen → fail-open untuk backend lama /
  // produk tanpa resep.
  bool isInStock;
  // isLowStock: dihitung backend memakai ambang porsi menipis per-outlet.
  // true → tampilkan badge amber "sisa N" di kasir (angka diambil dari
  // availablePortions). Default false saat field absen → fail-open (backend
  // lama / produk tanpa resep) → tak ada badge menipis.
  bool isLowStock;
  // manualOutOfStock: kasir menandai produk "86" secara manual (habis di
  // lapangan walau stok/bahan sistem masih ada). Backend meng-OR-kan ini ke
  // isInStock. Default false saat field absen → fail-open (produk normal).
  bool manualOutOfStock;
  // oosReason: alasan produk tak tersedia — "manual" (di-86 kasir),
  // "ingredient" (bahan resep habis), "stock" (stok fisik habis), atau ''
  // (tersedia / field absen). Dipakai kasir untuk membedakan label habis.
  // Default '' saat field absen → fail-open (dianggap normal).
  String oosReason;
  // isTaxable: apakah produk kena pajak (PPN/PB1). Default true supaya
  // produk existing tetap dipajaki seperti biasa. Item non-pajak
  // (is_taxable=false) dikecualikan dari basis pajak di kasir & backend.
  // Level produk saja — varian mengikuti induknya.
  bool isTaxable;
  String discountType;
  double discountValue;
  String discountName;
  String? outletRemoteId;
  List<ProductVariant> variants;

  // Local UI state
  bool isFavorite;

  Product({
    this.remoteId,
    required this.name,
    this.description = '',
    required this.price,
    this.stock = 0,
    this.lowStockThreshold = 0,
    this.stockUnit = 'pcs',
    this.sold = 0,
    this.categoryName,
    this.categoryId,
    this.sku,
    this.barcode,
    this.emoji = '📦',
    this.imageUrl,
    this.isAvailable = true,
    this.trackStock = true,
    this.availablePortions,
    this.isInStock = true,
    this.isLowStock = false,
    this.manualOutOfStock = false,
    this.oosReason = '',
    this.isTaxable = true,
    this.discountType = 'none',
    this.discountValue = 0,
    this.discountName = '',
    this.outletRemoteId,
    this.variants = const [],
    this.isFavorite = false,
  });

  bool get hasDiscount => discountType != 'none' && discountValue > 0;
  bool get isOutOfStock => trackStock && stock <= 0;

  Product copyWith({
    String? remoteId,
    String? name,
    String? description,
    double? price,
    int? stock,
    int? lowStockThreshold,
    String? stockUnit,
    int? sold,
    String? categoryName,
    String? categoryId,
    String? sku,
    String? barcode,
    String? emoji,
    String? imageUrl,
    bool? isAvailable,
    bool? trackStock,
    int? availablePortions,
    bool? isInStock,
    bool? isLowStock,
    bool? manualOutOfStock,
    String? oosReason,
    bool? isTaxable,
    String? discountType,
    double? discountValue,
    String? discountName,
    String? outletRemoteId,
    List<ProductVariant>? variants,
    bool? isFavorite,
  }) {
    return Product(
      remoteId: remoteId ?? this.remoteId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      stockUnit: stockUnit ?? this.stockUnit,
      sold: sold ?? this.sold,
      categoryName: categoryName ?? this.categoryName,
      categoryId: categoryId ?? this.categoryId,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      emoji: emoji ?? this.emoji,
      imageUrl: imageUrl ?? this.imageUrl,
      isAvailable: isAvailable ?? this.isAvailable,
      trackStock: trackStock ?? this.trackStock,
      availablePortions: availablePortions ?? this.availablePortions,
      isInStock: isInStock ?? this.isInStock,
      isLowStock: isLowStock ?? this.isLowStock,
      manualOutOfStock: manualOutOfStock ?? this.manualOutOfStock,
      oosReason: oosReason ?? this.oosReason,
      isTaxable: isTaxable ?? this.isTaxable,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      discountName: discountName ?? this.discountName,
      outletRemoteId: outletRemoteId ?? this.outletRemoteId,
      variants: variants ?? this.variants,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  factory Product.custom({required String name, required double price}) {
    return Product(
      name: name,
      price: price,
      emoji: '🛒',
      description: 'Produk Custom',
    );
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      remoteId: json['id']?.toString(),
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: (json['price'] as num? ?? 0).toDouble(),
      stock: json['stock'] as int? ?? 0,
      lowStockThreshold: json['low_stock_threshold'] as int? ?? 0,
      stockUnit: json['stock_unit'] as String? ?? 'pcs',
      sold: json['sold'] as int? ?? 0,
      categoryName: json['category'] as String?,
      categoryId: json['category_id']?.toString(),
      sku: json['sku'] as String?,
      barcode: json['barcode'] as String?,
      emoji: json['emoji'] as String? ?? '📦',
      imageUrl: json['image_url'] as String?,
      isAvailable: json['is_available'] as bool? ?? true,
      trackStock: json['track_stock'] as bool? ?? true,
      // Auto-86: null saat field absen → produk lama / tanpa resep, tak
      // dibatasi porsi. Terima int/num agar aman terhadap serialisasi.
      availablePortions: (json['available_portions'] as num?)?.toInt(),
      // Fail-open: field absen → dianggap tersedia (backend lama / no recipe).
      isInStock: json['is_in_stock'] as bool? ?? true,
      // Auto-86 menipis: backend hitung pakai ambang porsi per-outlet.
      // Fail-open: field absen → false → tak ada badge menipis.
      isLowStock: json['is_low_stock'] as bool? ?? false,
      // Auto-86 manual: kasir menandai habis. Fail-open: absen → false.
      manualOutOfStock: json['manual_out_of_stock'] as bool? ?? false,
      // Alasan habis. omitempty di backend → absen saat produk tersedia.
      // Fail-open: absen → '' → dianggap normal.
      oosReason: json['oos_reason'] as String? ?? '',
      // Default true saat field absen → produk lama (payload/cache tanpa
      // is_taxable) tetap dianggap kena pajak.
      isTaxable: json['is_taxable'] as bool? ?? true,
      discountType: json['discount_type'] as String? ?? 'none',
      discountValue: (json['discount_value'] as num? ?? 0).toDouble(),
      discountName: json['discount_name'] as String? ?? '',
      outletRemoteId: json['outlet_id']?.toString(),
      isFavorite: json['is_favorite'] as bool? ?? false,
      variants: (json['variants'] as List? ?? [])
          .map((v) => ProductVariant.fromJson(v))
          .toList(),
    );
  }

  /// Serialisasi balik ke bentuk yang dibaca [Product.fromJson] — dipakai
  /// untuk cache produk offline (SQLite). Round-trip key-nya sengaja
  /// dibuat persis sama dengan fromJson.
  Map<String, dynamic> toJson() => {
        'id': remoteId,
        'name': name,
        'description': description,
        'price': price,
        'stock': stock,
        'low_stock_threshold': lowStockThreshold,
        'stock_unit': stockUnit,
        'sold': sold,
        'category': categoryName,
        'category_id': categoryId,
        'sku': sku,
        'barcode': barcode,
        'emoji': emoji,
        'image_url': imageUrl,
        'is_available': isAvailable,
        'track_stock': trackStock,
        'available_portions': availablePortions,
        'is_in_stock': isInStock,
        'is_low_stock': isLowStock,
        'manual_out_of_stock': manualOutOfStock,
        'oos_reason': oosReason,
        'is_taxable': isTaxable,
        'discount_type': discountType,
        'discount_value': discountValue,
        'discount_name': discountName,
        'outlet_id': outletRemoteId,
        'is_favorite': isFavorite,
        'variants': variants.map((v) => v.toJson()).toList(),
      };

  double get discountedPrice {
    if (discountType == 'fixed') {
      return (price - discountValue).clamp(0, double.infinity);
    }
    if (discountType == 'percent') {
      return (price * (1 - discountValue / 100)).clamp(0, double.infinity);
    }
    return price;
  }

  String get discountLabel {
    if (discountType == 'fixed') return formatRupiah(discountValue);
    if (discountType == 'percent') return '${discountValue.toInt()}%';
    return '';
  }
}

class ProductVariant {
  String? remoteId;
  String productId;
  String name;
  String? sku;
  double price;
  int stock;
  String discountType;
  double discountValue;
  String discountName;

  ProductVariant({
    this.remoteId,
    required this.productId,
    required this.name,
    this.sku,
    required this.price,
    this.stock = 0,
    this.discountType = 'none',
    this.discountValue = 0,
    this.discountName = '',
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      remoteId: json['id']?.toString(),
      productId: json['product_id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      sku: json['sku'] as String?,
      price: (json['price'] as num? ?? 0).toDouble(),
      stock: json['stock'] as int? ?? 0,
      discountType: json['discount_type'] as String? ?? 'none',
      discountValue: (json['discount_value'] as num? ?? 0).toDouble(),
      discountName: json['discount_name'] as String? ?? '',
    );
  }

  bool get hasDiscount => discountType != 'none' && discountValue > 0;

  Map<String, dynamic> toJson() => {
        'id': remoteId,
        'product_id': productId,
        'name': name,
        'sku': sku,
        'price': price,
        'stock': stock,
        'discount_type': discountType,
        'discount_value': discountValue,
        'discount_name': discountName,
      };

  double get discountedPrice {
    if (discountType == 'fixed') {
      return (price - discountValue).clamp(0, double.infinity);
    }
    if (discountType == 'percent') {
      return (price * (1 - discountValue / 100)).clamp(0, double.infinity);
    }
    return price;
  }

  String get discountLabel {
    if (discountType == 'fixed') return formatRupiah(discountValue);
    if (discountType == 'percent') return '${discountValue.toInt()}%';
    return '';
  }
}
