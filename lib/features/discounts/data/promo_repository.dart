import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../kasir/domain/cart_item.dart';
import '../../../core/offline/entity_cache.dart';
import '../../../core/offline/sale_outbox.dart' show isOfflineError;
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

/// Promo outlet yang disimpan di perangkat — supaya kode promo tetap bisa
/// dipakai saat offline.
final _promoCache = EntityCache<Map<String, dynamic>>(
  'promo',
  toJson: (m) => m,
  fromJson: (m) => m,
);

DateTime? _waktu(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// Validasi kode promo TANPA server — aturan yang sama dengan
/// entity.Promotion.IsCurrentlyActive di backend (aktif, jadwal tanggal, hari,
/// jam, kuota). Kuota memakai pemakaian terakhir yang diketahui perangkat.
/// Throw pesan untuk kasir bila tak berlaku. MURNI.
AppliedPromo validasiPromoOffline(
  List<Map<String, dynamic>> promos,
  String kode,
  DateTime kini,
) {
  final k = kode.trim().toUpperCase();
  final p = promos
      .where((m) => (m['code']?.toString() ?? '').trim().toUpperCase() == k)
      .firstOrNull;
  if (k.isEmpty || p == null) {
    throw 'Kode promo tidak dikenal di perangkat ini (offline).';
  }
  final tidakBerlaku = 'Kode promo tidak aktif atau di luar jadwal.';
  if (p['is_active'] == false || p['deleted_at'] != null) throw tidakBerlaku;
  final mulai = _waktu(p['starts_at']), akhir = _waktu(p['ends_at']);
  if (mulai != null && kini.isBefore(mulai)) throw tidakBerlaku;
  if (akhir != null && kini.isAfter(akhir)) throw tidakBerlaku;
  final batas = p['usage_limit'], dipakai = p['usage_count'];
  if (batas is num && dipakai is num && dipakai >= batas) throw tidakBerlaku;
  final hari = p['schedule_days_of_week'];
  // Server: Minggu = 0. Dart: Senin = 1 … Minggu = 7.
  if (hari is List && hari.isNotEmpty && !hari.contains(kini.weekday % 7)) {
    throw tidakBerlaku;
  }
  final jamMulai = p['schedule_hour_start'], jamAkhir = p['schedule_hour_end'];
  if (jamMulai is num && jamAkhir is num) {
    final j = kini.hour;
    final masuk = jamMulai <= jamAkhir
        ? j >= jamMulai && j <= jamAkhir
        : j >= jamMulai || j <= jamAkhir; // melewati tengah malam
    if (!masuk) throw tidakBerlaku;
  }
  return AppliedPromo.fromJson(p);
}

class PromoRepository {
  final Ref ref;
  PromoRepository(this.ref);

  /// Validasi kode promo ke backend. Throw (dengan pesan dari backend) kalau
  /// kode tidak valid / tidak aktif / di luar jadwal.
  ///
  /// Offline: divalidasi dari promo yang tersimpan di perangkat. Server
  /// menilainya ulang pada waktu jual saat transaksinya terkirim; yang tak
  /// sah tetap tercatat (pelanggan sudah membayar) dengan penanda
  /// promo_tidak_berlaku.
  Future<AppliedPromo> validate(String outletId, String code) async {
    try {
      final raw = await ref
          .read(outletServiceProvider)
          .validatePromo(outletId, code.trim());
      return AppliedPromo.fromJson(raw);
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      return validasiPromoOffline(
        await _promoCache.getAll(outletId),
        code,
        DateTime.now(),
      );
    }
  }

  /// Simpan daftar promo outlet untuk dipakai saat offline (dipanggil saat
  /// data kasir disiapkan selagi online).
  Future<void> simpanUntukOffline(String outletId) async {
    final promos = await ref
        .read(outletServiceProvider)
        .getPromotions(outletId);
    await _promoCache.replaceAll(outletId, promos);
  }
}

final promoRepositoryProvider = Provider<PromoRepository>(
  (ref) => PromoRepository(ref),
);
