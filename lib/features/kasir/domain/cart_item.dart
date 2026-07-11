import '../../../core/format.dart';
import '../../products/domain/product.dart';

/// C4: satu opsi add-on/topping yang dipilih untuk baris keranjang.
class CartModifier {
  final String groupId;
  final String groupName;
  final String optionId;
  final String name;
  final double price;

  const CartModifier({
    required this.groupId,
    required this.groupName,
    required this.optionId,
    required this.name,
    required this.price,
  });

  Map<String, dynamic> toCheckoutJson() => {
        'group_id': groupId,
        'group_name': groupName,
        'option_id': optionId,
        'name': name,
        'price': price,
      };
}

class CartItem {
  final Product product;
  final int qty;
  final String? variantId;
  final String variantName;
  final double variantPrice;
  final String note;

  /// Snapshot diskon varian saat dipilih di kasir. Disimpan supaya kalau
  /// admin mengubah diskon varian setelah item masuk ke cart, baris yang
  /// sudah ada tidak ikut berubah harganya.
  final String variantDiscountType;
  final double variantDiscountValue;
  final String variantDiscountName;

  /// Diskon manual yang diberikan kasir per baris keranjang.
  /// Override diskon master produk bila keduanya ada.
  /// Tipe: 'none' | 'percent' | 'fixed'
  final String manualDiscountType;
  final double manualDiscountValue;

  /// C4: add-on/topping yang dipilih. Harga tiap opsi ditambahkan ke harga per
  /// unit (effectivePrice). Item dengan pilihan modifier berbeda = baris beda.
  final List<CartModifier> modifiers;

  const CartItem(
    this.product,
    this.qty, {
    this.variantId,
    this.variantName = '',
    this.variantPrice = 0,
    this.variantDiscountType = 'none',
    this.variantDiscountValue = 0,
    this.variantDiscountName = '',
    this.note = '',
    this.manualDiscountType = 'none',
    this.manualDiscountValue = 0,
    this.modifiers = const [],
  });

  factory CartItem.from(
    Product p,
    int qty, [
    ProductVariant? variant,
    List<CartModifier> modifiers = const [],
  ]) {
    return CartItem(
      p,
      qty,
      variantId: variant?.remoteId,
      variantName: variant?.name ?? '',
      variantPrice: variant?.price ?? p.price,
      variantDiscountType: variant?.discountType ?? 'none',
      variantDiscountValue: variant?.discountValue ?? 0,
      variantDiscountName: variant?.discountName ?? '',
      modifiers: modifiers,
    );
  }

  /// C4: total harga add-on per unit.
  double get modifiersTotal =>
      modifiers.fold(0.0, (s, m) => s + m.price);

  /// C4: kunci stabil pilihan modifier (option id terurut) untuk membedakan
  /// baris keranjang — item sama tapi topping beda = baris beda.
  String get modifierKey {
    if (modifiers.isEmpty) return '';
    final ids = modifiers.map((m) => m.optionId).toList()..sort();
    return ids.join(',');
  }

  // If variant exists, it has its own absolute price. If not, use product price.
  double get basePrice => variantId != null ? variantPrice : product.price;

  bool get hasManualDiscount =>
      manualDiscountType != 'none' && manualDiscountValue > 0;

  bool get _hasVariantDiscount =>
      variantId != null &&
      variantDiscountType != 'none' &&
      variantDiscountValue > 0;

  /// True bila item sudah punya diskon otomatis bawaan: dari produk (untuk
  /// pilihan Regular) atau dari varian (untuk pilihan varian eksplisit).
  /// Dipakai panel pesanan untuk men-disable tombol "Beri Diskon" supaya
  /// kasir tidak menumpuk diskon manual di atas diskon yang sudah diset
  /// admin.
  bool get hasAutoDiscount {
    if (variantId != null) return _hasVariantDiscount;
    return product.hasDiscount;
  }

  double _applyManual(double price) {
    if (manualDiscountType == 'percent') {
      final v = (price * (1 - manualDiscountValue / 100));
      return v < 0 ? 0 : v;
    }
    if (manualDiscountType == 'fixed') {
      final v = price - manualDiscountValue;
      return v < 0 ? 0 : v;
    }
    return price;
  }

  double _applyVariantDiscount(double price) {
    if (variantDiscountType == 'percent') {
      final v = price * (1 - variantDiscountValue / 100);
      return v < 0 ? 0 : v;
    }
    if (variantDiscountType == 'fixed') {
      final v = price - variantDiscountValue;
      return v < 0 ? 0 : v;
    }
    return price;
  }

  /// Harga base per unit setelah diskon (TANPA add-on). Prioritas:
  ///   1. Diskon manual (override semua) — hak veto kasir.
  ///   2. Untuk pilihan varian eksplisit: diskon varian-nya.
  ///   3. Untuk pilihan Regular (variantId == null): diskon produk.
  double get _effectiveBase {
    if (hasManualDiscount) return _applyManual(basePrice);
    if (_hasVariantDiscount) return _applyVariantDiscount(basePrice);
    if (variantId != null) return basePrice;
    return product.discountedPrice;
  }

  /// Harga efektif per unit yang dibayar = base (setelah diskon) + add-on.
  double get effectivePrice => _effectiveBase + modifiersTotal;

  double get subtotal => effectivePrice * qty;

  /// Diskon per baris — HANYA dari diskon (add-on tidak mengurangi/menambah
  /// nilai diskon), supaya laporan diskon tetap benar.
  double get lineDiscount => (basePrice - _effectiveBase) * qty;

  /// Label diskon untuk badge UI ("10%" atau "Rp 5.000").
  String get discountLabel {
    if (hasManualDiscount) {
      if (manualDiscountType == 'percent') {
        return '${manualDiscountValue.toInt()}%';
      }
      return formatRupiah(manualDiscountValue);
    }
    if (_hasVariantDiscount) {
      if (variantDiscountType == 'percent') {
        return '${variantDiscountValue.toInt()}%';
      }
      return formatRupiah(variantDiscountValue);
    }
    return product.discountLabel;
  }

  /// Tipe diskon efektif yang dikirim ke backend untuk snapshot.
  String get effectiveDiscountType {
    if (hasManualDiscount) return manualDiscountType;
    if (_hasVariantDiscount) return variantDiscountType;
    if (variantId == null && product.hasDiscount) return product.discountType;
    return 'none';
  }

  double get effectiveDiscountValue {
    if (hasManualDiscount) return manualDiscountValue;
    if (_hasVariantDiscount) return variantDiscountValue;
    if (variantId == null && product.hasDiscount) return product.discountValue;
    return 0;
  }

  String get effectiveDiscountName {
    if (hasManualDiscount) return 'Diskon Manual';
    if (_hasVariantDiscount) {
      return variantDiscountName.isEmpty
          ? 'Diskon ${variantName.isEmpty ? 'Varian' : variantName}'
          : variantDiscountName;
    }
    if (variantId == null && product.hasDiscount) return product.discountName;
    return '';
  }

  String get displayName =>
      variantName.isEmpty ? product.name : '${product.name} ($variantName)';

  String get sizeName => variantName;

  /// C4: label ringkas add-on untuk ditampilkan di panel keranjang / struk.
  String get modifiersLabel => modifiers.map((m) => m.name).join(', ');

  CartItem copyWith({
    int? qty,
    String? note,
    String? manualDiscountType,
    double? manualDiscountValue,
  }) =>
      CartItem(
        product,
        qty ?? this.qty,
        variantId: variantId,
        variantName: variantName,
        variantPrice: variantPrice,
        variantDiscountType: variantDiscountType,
        variantDiscountValue: variantDiscountValue,
        variantDiscountName: variantDiscountName,
        note: note ?? this.note,
        manualDiscountType: manualDiscountType ?? this.manualDiscountType,
        manualDiscountValue: manualDiscountValue ?? this.manualDiscountValue,
        modifiers: modifiers,
      );

  bool sameVariantAs(Product p, String? vId) {
    // For custom products (id is 0 or null)
    if (product.remoteId == null && p.remoteId == null) {
      return product.name == p.name && product.price == p.price;
    }
    return product.remoteId == p.remoteId && variantId == vId;
  }
}
