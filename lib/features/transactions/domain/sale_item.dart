import '../../products/domain/product.dart' show IsiPaket;
import 'sale.dart';

class SaleItem {
  String id;

  String productRemoteId;

  String productName;
  String productEmoji;
  String productSku;
  String variant;
  double price;
  double originalPrice;
  final double discountAmount;
  final String discountLabel;
  final String discountName;
  final int qty;

  /// Jumlah qty item ini yang SUDAH diretur (akumulasi refund parsial).
  /// Backend field: `refunded_qty`. 0 = belum ada retur untuk item ini.
  final int refundedQty;
  final String note;
  // C4: label add-on/topping ("Boba, Less Sugar") untuk struk & riwayat.
  final String modifiersLabel;

  /// Add-on/topping beserta harga per unit — untuk rincian harga di struk &
  /// riwayat. Kosong untuk baris tanpa add-on (atau data lama).
  final List<AddOnStruk> modifiers;

  /// Isi paket per SATU paket (kosong untuk produk biasa).
  final List<IsiPaket> bundleItems;

  /// "2× Nasi, 4× Ayam" — isi untuk SELURUH qty baris ini.
  String get bundleLabel => IsiPaket.label(bundleItems, kali: qty);

  Sale? sale;

  SaleItem({
    this.id = '',
    this.productRemoteId = '',
    required this.productName,
    required this.productEmoji,
    this.productSku = '',
    this.variant = '',
    required this.price,
    this.originalPrice = 0,
    this.discountAmount = 0,
    this.discountLabel = '',
    this.discountName = '',
    required this.qty,
    this.refundedQty = 0,
    this.note = '',
    this.modifiersLabel = '',
    this.modifiers = const [],
    this.bundleItems = const [],
  });

  /// Σ harga add-on per unit.
  double get totalAddOn => modifiers.fold(0.0, (s, m) => s + m.price);

  /// Harga satu unit SEBELUM add-on & diskon: harga ukuran/varian yang
  /// dipilih, atau harga produk. originalPrice memuat add-on (sama dengan
  /// server), jadi add-on dikurangkan; data tanpa originalPrice memakai price.
  double get hargaDasar {
    final asal = originalPrice > 0 ? originalPrice : price;
    final d = asal - totalAddOn;
    return d < 0 ? 0 : d;
  }

  /// Rincian harga per unit: ukuran/varian (atau "Harga") lalu tiap add-on.
  /// Kosong bila baris tanpa varian & add-on — tak perlu dirinci.
  List<({String label, double harga, bool tambahan})> get rincianHarga {
    if (variant.trim().isEmpty && modifiers.isEmpty) return const [];
    return [
      (
        label: variant.trim().isEmpty ? 'Harga' : variant.trim(),
        harga: hargaDasar,
        tambahan: false,
      ),
      for (final m in modifiers)
        (label: m.name, harga: m.price, tambahan: true),
    ];
  }

  /// Sisa qty yang masih bisa diretur (quantity - refunded_qty). Clamp ke 0
  /// supaya tidak pernah negatif walau data backend tak konsisten.
  int get remainingQty {
    final r = qty - refundedQty;
    return r < 0 ? 0 : r;
  }

  /// Gabungkan array modifier JSON backend → label nama ("Boba, Less Sugar").
  static String modifiersLabelFrom(dynamic raw) {
    if (raw is! List) return '';
    return raw
        .whereType<Map>()
        .map((m) => m['name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .join(', ');
  }

  double get subtotal => price * qty;
  set subtotal(double value) {}

  /// Maps from Go backend entity TransactionItem JSON
  factory SaleItem.fromJson(Map<String, dynamic> json) {
    double parseNum(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '0') ?? 0;
    }

    final discountType = json['discount_type']?.toString() ?? 'none';
    final discountValue = parseNum(json['discount_value']);
    String label = '';
    if (discountType == 'percent' && discountValue > 0) {
      label = '${discountValue.toInt()}%';
    } else if (discountType == 'fixed' && discountValue > 0) {
      label = 'Rp ${discountValue.toInt()}';
    }

    return SaleItem(
      productRemoteId: json['product_id']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? '',
      productEmoji: '',
      variant: json['variant_name']?.toString() ?? '',
      price: parseNum(json['price_at_time']),
      originalPrice: parseNum(json['original_price']),
      discountAmount: parseNum(json['discount_amount']),
      discountLabel: label,
      discountName: json['discount_name']?.toString() ?? '',
      qty: json['quantity'] is int
          ? json['quantity']
          : int.tryParse(json['quantity']?.toString() ?? '0') ?? 0,
      refundedQty: json['refunded_qty'] is int
          ? json['refunded_qty']
          : int.tryParse(json['refunded_qty']?.toString() ?? '0') ?? 0,
      note: json['note']?.toString() ?? '',
      modifiersLabel: modifiersLabelFrom(json['modifiers']),
      modifiers: AddOnStruk.dariJson(json['modifiers']),
      bundleItems: IsiPaket.dariJson(json['bundle_items']),
    )..id = json['id']?.toString() ?? '';
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productRemoteId,
      'quantity': qty,
      if (note.isNotEmpty) 'note': note,
    };
  }
}

/// Satu add-on/topping pada baris penjualan: nama & harga per unit.
class AddOnStruk {
  final String name;
  final double price;
  const AddOnStruk({required this.name, required this.price});

  Map<String, dynamic> toJson() => {'name': name, 'price': price};

  /// Dari JSON modifier server (`[{name, price, …}]`). Aman untuk null.
  static List<AddOnStruk> dariJson(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (m) => AddOnStruk(
            name: m['name']?.toString() ?? '',
            price: (m['price'] as num?)?.toDouble() ?? 0,
          ),
        )
        .where((m) => m.name.isNotEmpty)
        .toList();
  }
}
