import 'cart_item.dart';

/// Persentase diskon yang DIBERIKAN KASIR pada keranjang — padanan persis
/// `cashierDiscountPercent` di server (internal/transaction/discount.go).
///
/// # KENAPA DIHITUNG DI PERANGKAT
///
/// Saat online, server yang menolak diskon di atas batas kasir lalu aplikasi
/// meminta PIN manajer. Saat offline tak ada server untuk bertanya, dan PIN
/// manajer pun tak bisa diperiksa. Tanpa perhitungan ini transaksinya lolos
/// di tablet, pelanggan menerima diskonnya, lalu server menolaknya saat
/// sinkron — omzetnya tak pernah tercatat.
///
/// Aturannya harus SAMA dengan server, termasuk keanehannya: server
/// memperlakukan diskon varian sebagai diskon kasir (varian tak punya "diskon
/// master"), jadi di sini pun begitu. Bila aturan server berubah, ubah juga
/// fungsi ini — tesnya (batas_diskon_test.dart) menyalin kasus dari server.
///
///   persen = (Σ diskon kasir per baris + diskon level order) / harga kotor × 100
///
/// - harga kotor: harga dasar × qty, sebelum diskon apa pun dan tanpa add-on;
/// - diskon kasir per baris: selisih harga "master" (diskon bawaan Pemilik
///   untuk produk; tanpa diskon untuk varian) dengan harga yang dikirim;
/// - diskon order: promo + tukar poin (lihat [diskonOrderDari]).
double persenDiskonKasir(List<CartItem> keranjang, {double diskonOrder = 0}) {
  var kotor = 0.0;
  var diskonKasir = 0.0;
  for (final item in keranjang) {
    final dasar = item.basePrice;
    kotor += dasar * item.qty;

    final tipe = item.effectiveDiscountType;
    if (tipe != 'percent' && tipe != 'fixed') continue;
    final hargaMaster = item.variantId != null
        ? dasar
        : _terapkan(
            dasar,
            item.product.discountType,
            item.product.discountValue,
          );
    final hargaDikirim = _terapkan(dasar, tipe, item.effectiveDiscountValue);
    if ((hargaMaster - hargaDikirim).abs() > 0.005) {
      diskonKasir += (hargaMaster - hargaDikirim) * item.qty;
    }
  }
  if (kotor <= 0) return 0;
  final total = diskonKasir + (diskonOrder < 0 ? 0 : diskonOrder);
  if (total <= 0) return 0;
  return total / kotor * 100;
}

/// Diskon level order seperti dihitung server: seluruh diskon dikurangi
/// diskon per baris (dibulatkan), tak pernah negatif.
double diskonOrderDari({
  required double diskonTotal,
  required List<CartItem> keranjang,
}) {
  // Per baris dijepit >= 0, seperti discountAmount di server.
  final diskonBaris = keranjang.fold<double>(0, (s, i) {
    final d = (i.basePrice - (i.effectivePrice - i.modifiersTotal)) * i.qty;
    return s + (d < 0 ? 0 : d);
  });
  final sisa = diskonTotal - diskonBaris.roundToDouble();
  return sisa < 0 ? 0 : sisa;
}

/// Bagian diskon order yang diberikan KASIR: diskon order dikurangi potongan
/// promo resmi & tukar poin. Padanan `diskonOrderKasir` di server — promo
/// buatan Pemilik dan poin pelanggan bukan diskon kasir. Tak pernah negatif.
double diskonOrderKasir(double diskonOrder, {double diskonResmi = 0}) {
  final d = diskonOrder - (diskonResmi < 0 ? 0 : diskonResmi);
  return d < 0 ? 0 : d;
}

/// Apakah [persen] melebihi [batas] — sama dengan server (toleransi 0,001).
/// Batas 0 atau kurang = tak ada batas.
bool melebihiBatasDiskon(double persen, num batas) =>
    batas > 0 && persen > batas + 0.001;

double _terapkan(double harga, String tipe, double nilai) {
  switch (tipe) {
    case 'percent':
      final v = harga * (1 - nilai / 100);
      return v < 0 ? 0 : v;
    case 'fixed':
      final v = harga - nilai;
      return v < 0 ? 0 : v;
    default:
      return harga;
  }
}
