import 'product.dart';

class Category {
  String? remoteId;
  String? outletRemoteId;
  String name;
  String description;
  int order;
  List<Product> products;

  /// Sidik isi kategori dari server (cache perangkat: diambil ulang hanya
  /// bila versinya berubah). Kosong dari server lama.
  String version;

  Category({
    this.remoteId,
    this.outletRemoteId,
    required this.name,
    this.description = '',
    this.order = 0,
    this.products = const [],
    this.version = '',
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      remoteId: json['id']?.toString(),
      outletRemoteId: json['outlet_id']?.toString(),
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      order: (json['sort_order'] as num?)?.toInt() ?? 0,
      version: json['version']?.toString() ?? '',
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
      'sort_order': order,
      'version': version,
    };
  }
}
