import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../kasir/domain/cart_item.dart';
import '../../outlet/data/outlet_service.dart';

/// Promo yang sudah divalidasi backend (`GET /outlets/:id/promotions/validate`).
///
/// Nominal diskon dihitung di sisi kasir (lihat [discountFor]) supaya angka
/// yang dilihat kasir == yang ditagih == yang tersimpan. Backend tetap yang
/// memvalidasi keabsahan kode + mencatat pemakaian saat checkout.
class AppliedPromo {
  final String code;
  final String name;
  final String discountType; // percent | fixed
  final double discountValue;
  final String scope; // cart | product | category
  final String? targetId; // product/category id untuk scope non-cart
  final double minPurchaseAmount;

  const AppliedPromo({
    required this.code,
    required this.name,
    required this.discountType,
    required this.discountValue,
    required this.scope,
    required this.targetId,
    required this.minPurchaseAmount,
  });

  factory AppliedPromo.fromJson(Map<String, dynamic> j) => AppliedPromo(
    code: (j['code'] ?? '').toString(),
    name: (j['name'] ?? 'Promo').toString(),
    discountType: (j['discount_type'] ?? 'percent').toString(),
    discountValue: (j['discount_value'] as num?)?.toDouble() ?? 0,
    scope: (j['scope'] ?? 'cart').toString(),
    targetId: j['target_id']?.toString(),
    minPurchaseAmount: (j['min_purchase_amount'] as num?)?.toDouble() ?? 0,
  );

  /// Hitung nominal diskon promo terhadap isi cart.
  ///   - scope cart     → basis = subtotal order
  ///   - scope product  → basis = jumlah subtotal baris produk yang cocok
  ///   - scope category → basis = jumlah subtotal baris kategori yang cocok
  /// Hasil di-clamp ke [0, basis]. Return 0 kalau tidak ada basis yang eligible.
  double discountFor(List<CartItem> cart, double subtotal) {
    double base;
    switch (scope) {
      case 'product':
        base = cart
            .where((c) => targetId != null && c.product.remoteId == targetId)
            .fold(0.0, (s, c) => s + c.subtotal);
        break;
      case 'category':
        base = cart
            .where((c) => targetId != null && c.product.categoryId == targetId)
            .fold(0.0, (s, c) => s + c.subtotal);
        break;
      default: // cart
        base = subtotal;
    }
    if (base <= 0) return 0;
    double d = discountType == 'percent'
        ? base * (discountValue / 100.0)
        : discountValue;
    if (d > base) d = base;
    if (d < 0) d = 0;
    return d.roundToDouble();
  }
}

class PromoRepository {
  final Ref ref;
  PromoRepository(this.ref);

  /// Validasi kode promo ke backend. Throw (dengan pesan dari backend) kalau
  /// kode tidak valid / tidak aktif / di luar jadwal.
  Future<AppliedPromo> validate(String outletId, String code) async {
    final raw = await ref
        .read(outletServiceProvider)
        .validatePromo(outletId, code.trim());
    return AppliedPromo.fromJson(raw);
  }
}

final promoRepositoryProvider = Provider<PromoRepository>(
  (ref) => PromoRepository(ref),
);
