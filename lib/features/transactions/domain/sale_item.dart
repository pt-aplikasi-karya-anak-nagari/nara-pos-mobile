
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
  final String note;
  // C4: label add-on/topping ("Boba, Less Sugar") untuk struk & riwayat.
  final String modifiersLabel;

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
    this.note = '',
    this.modifiersLabel = '',
  });

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
      note: json['note']?.toString() ?? '',
      modifiersLabel: modifiersLabelFrom(json['modifiers']),
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
