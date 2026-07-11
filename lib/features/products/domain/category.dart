import 'product.dart';

class Category {
  String? remoteId;
  String? outletRemoteId;
  String name;
  String description;
  int order;
  List<Product> products;

  Category({
    this.remoteId,
    this.outletRemoteId,
    required this.name,
    this.description = '',
    this.order = 0,
    this.products = const [],
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      remoteId: json['id']?.toString(),
      outletRemoteId: json['outlet_id']?.toString(),
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      products: (json['products'] as List? ?? [])
          .map((p) => Product.fromJson(p))
          .toList(),
    );
  }

  /// Serialisasi setia-fromJson untuk cache offline (EntityCache). `products`
  /// sengaja dihilangkan — chip kategori kasir hanya butuh nama; daftar produk
  /// dilayani terpisah oleh productsStreamProvider (cache produk sendiri).
  Map<String, dynamic> toCacheJson() {
    return {
      'id': remoteId,
      'outlet_id': outletRemoteId,
      'name': name,
      'description': description,
    };
  }
}
