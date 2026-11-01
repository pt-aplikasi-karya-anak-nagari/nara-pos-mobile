import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../features/subscription/data/subscription_repository.dart';
import 'outlet_scope.dart';

/// Jenis usaha outlet yang sedang login — menentukan fitur apa yang tampil
/// dan bagaimana menu dinamai/dikelompokkan, supaya kasir kafe tak melihat
/// menu gudang ritel dan toko baju tak melihat menu meja & dapur.
///
/// # DUA LAPIS, DUA TUGAS
///
/// Server sudah MEMATIKAN fitur yang tak berlaku untuk tipe outlet (lihat
/// outlet_types.disabled_feature_keys — mis. meja untuk Retail); hasilnya
/// sampai lewat [FeatureCheckRef.hasFeature]. Itu soal BOLEH.
///
/// Lapis ini soal RELEVAN: fitur yang boleh tapi tak masuk akal untuk jenis
/// usahanya (Transfer Stok untuk salon) disembunyikan dari menu, dan yang
/// tersisa diberi nama & urutan yang cocok. Ia tak pernah MEMBUKA fitur yang
/// dimatikan server — [FiturUsahaRef.fiturTampil] selalu meng-AND keduanya.
enum JenisUsaha {
  fnb,
  jasa,
  retail,

  /// Jenis tak dikenali / belum termuat → semua fitur tampil (fail-open),
  /// sama seperti perilaku sebelum pengelompokan ini ada.
  umum;

  /// Tebak jenis dari data outlet. Nama dipakai lebih dulu karena itulah
  /// yang dilihat & diubah SuperAdmin; id hanya cadangan (seed bawaan:
  /// 1 Retail, 2 F&B, 3 Service).
  static JenisUsaha dari({int typeId = 0, String typeName = ''}) {
    // "F&B" → "fnb", "Food & Beverage" → "foodnbeverage".
    final n = typeName
        .toLowerCase()
        .replaceAll('&', 'n')
        .replaceAll(RegExp(r'[^a-z]'), '');
    if (n.isNotEmpty) {
      if (n == 'fb' ||
          n.contains('fnb') ||
          n.contains('food') ||
          n.contains('resto') ||
          n.contains('kafe') ||
          n.contains('cafe') ||
          n.contains('kuliner') ||
          n.contains('makan')) {
        return JenisUsaha.fnb;
      }
      if (n.contains('retail') ||
          n.contains('ritel') ||
          n.contains('toko') ||
          n.contains('shop')) {
        return JenisUsaha.retail;
      }
      if (n.contains('service') ||
          n.contains('jasa') ||
          n.contains('layanan') ||
          n.contains('salon') ||
          n.contains('laundry') ||
          n.contains('barber')) {
        return JenisUsaha.jasa;
      }
      return JenisUsaha.umum;
    }
    return switch (typeId) {
      1 => JenisUsaha.retail,
      2 => JenisUsaha.fnb,
      3 => JenisUsaha.jasa,
      _ => JenisUsaha.umum,
    };
  }

  /// Nama singkat untuk lencana di profil.
  String get nama => switch (this) {
    JenisUsaha.fnb => 'F&B',
    JenisUsaha.jasa => 'Jasa',
    JenisUsaha.retail => 'Retail',
    JenisUsaha.umum => 'Umum',
  };

  /// Sebutan barang yang dijual: Menu / Layanan / Produk.
  String get sebutanKatalog => switch (this) {
    JenisUsaha.fnb => 'Menu',
    JenisUsaha.jasa => 'Layanan',
    _ => 'Produk',
  };

  /// Judul grup katalog di profil.
  String get judulGrupKatalog => switch (this) {
    JenisUsaha.fnb => 'Menu & Dapur',
    JenisUsaha.jasa => 'Layanan',
    JenisUsaha.retail => 'Produk & Stok',
    JenisUsaha.umum => 'Produk & Inventori',
  };

  /// Judul grup operasional di profil.
  String get judulGrupOperasional => switch (this) {
    JenisUsaha.fnb => 'Meja & Pesanan',
    JenisUsaha.jasa => 'Operasional Layanan',
    _ => 'Operasional Toko',
  };

  /// Sebutan modifier: topping untuk F&B, tambahan untuk jasa.
  String get sebutanModifier => switch (this) {
    JenisUsaha.fnb => 'Topping & Add-on',
    JenisUsaha.jasa => 'Layanan Tambahan',
    _ => 'Modifier & Add-on',
  };

  /// Apakah fitur [kunci] RELEVAN untuk jenis usaha ini. Kunci yang tak
  /// disebut di sini relevan untuk semua jenis.
  ///
  /// Kunci memakai katalog fitur server (table_management, recipe_bom, …)
  /// plus beberapa kunci tampilan yang tak punya padanan di katalog
  /// ('order_types', 'stock_transfer', 'scan').
  bool relevan(String kunci) {
    if (this == JenisUsaha.umum) return true;
    final untuk = _relevanUntuk[kunci];
    return untuk == null || untuk.contains(this);
  }
}

/// Fitur yang hanya relevan untuk sebagian jenis usaha.
const Map<String, Set<JenisUsaha>> _relevanUntuk = {
  // Makan di tempat: meja, QR meja, layar dapur, resep bahan baku.
  'table_management': {JenisUsaha.fnb},
  'qr_self_order': {JenisUsaha.fnb},
  'kitchen_display': {JenisUsaha.fnb},
  'recipe_bom': {JenisUsaha.fnb},
  // Topping (F&B) / layanan tambahan (jasa); barang ritel memakai varian.
  'modifiers': {JenisUsaha.fnb, JenisUsaha.jasa},
  // Dine-in / take-away / antar-jemput — tak dipakai toko ritel.
  'order_types': {JenisUsaha.fnb, JenisUsaha.jasa},
  // Memindah stok antar cabang — usaha jasa tak menjual stok.
  'stock_transfer': {JenisUsaha.fnb, JenisUsaha.retail},
  'supplier_po': {JenisUsaha.fnb, JenisUsaha.retail},
  // Scan barcode di kasir — jasa tak punya barang berbarcode.
  'scan': {JenisUsaha.fnb, JenisUsaha.retail},
};

/// Jenis usaha outlet aktif. Outlet belum termuat → [JenisUsaha.umum].
final jenisUsahaProvider = Provider<JenisUsaha>((ref) {
  final o = ref.watch(activeOutletProvider);
  if (o == null) return JenisUsaha.umum;
  return JenisUsaha.dari(typeId: o.typeId, typeName: o.typeName);
});

extension FiturUsahaRef on WidgetRef {
  JenisUsaha get jenisUsaha => watch(jenisUsahaProvider);

  /// Tampilkan fitur [kunci]? Harus DIIZINKAN paket & tipe outlet (server)
  /// DAN relevan untuk jenis usahanya. Kunci tampilan yang bukan bagian
  /// katalog server cukup lewat cek relevansi saja.
  bool fiturTampil(String kunci) {
    final relevan = jenisUsaha.relevan(kunci);
    if (!relevan) return false;
    if (_kunciTampilanSaja.contains(kunci)) return true;
    return hasFeature(kunci);
  }
}

/// Kunci yang bukan bagian katalog fitur server — tak dicek ke paket.
const Set<String> _kunciTampilanSaja = {'order_types', 'scan'};
