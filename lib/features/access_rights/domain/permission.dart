/// Granular permissions yang bisa dikonfigurasi oleh **owner** untuk
/// peran Admin dan Kasir.
///
/// Owner selalu memiliki seluruh permission (tidak dikonfigurasi di sini).
/// Permission yang memang _hanya_ untuk owner (mis. kelola outlet, kelola
/// karyawan, kelola hak akses itu sendiri) sengaja tidak dimasukkan ke enum
/// ini — gate-nya tetap pakai pengecekan `role == UserRole.admin` atau `role == UserRole.owner`.
enum Permission {
  /// Tambah / edit / hapus produk.
  manageProducts,

  /// Tambah / edit kategori produk.
  manageCategories,

  /// Konfigurasi printer termal.
  managePrinter,

  /// Atur pajak penjualan.
  manageTax,

  /// Lihat laporan penjualan.
  viewReports,

  /// Lihat riwayat transaksi.
  viewHistory,

  /// Refund transaksi yang sudah selesai.
  refund,

  /// Terapkan diskon di kasir.
  giveDiscount,
}

extension PermissionX on Permission {
  /// i18n key untuk label permission (misal "Kelola Produk").
  String get labelKey => 'perm.$name';

  /// i18n key untuk deskripsi singkat permission.
  String get descKey => 'perm.$name.desc';

  /// Key permission di katalog backend yang setara. Null berarti permission
  /// ini tidak dikelola backend (mis. `managePrinter` = konfigurasi perangkat
  /// lokal; `giveDiscount` belum punya key di katalog) — untuk yang null,
  /// enforcement tetap pakai konfigurasi lokal.
  ///
  /// Untuk yang non-null, aplikasi kasir menegakkan izin sesuai yang diatur
  /// owner di web (fetch via /outlets/:id/my-permissions).
  String? get backendKey {
    switch (this) {
      case Permission.manageProducts:
        return 'products.create';
      case Permission.manageCategories:
        return 'categories.manage';
      case Permission.manageTax:
        return 'settings.tax';
      case Permission.viewReports:
        return 'reports.view';
      case Permission.viewHistory:
        return 'transactions.view';
      case Permission.refund:
        return 'transactions.refund';
      case Permission.managePrinter:
      case Permission.giveDiscount:
        return null;
    }
  }
}
