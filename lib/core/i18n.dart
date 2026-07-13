import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'shared_prefs.dart';

enum AppLocale { id, en }

extension AppLocaleX on AppLocale {
  Locale toLocale() => switch (this) {
    AppLocale.id => const Locale('id'),
    AppLocale.en => const Locale('en'),
  };
  String get label => switch (this) {
    AppLocale.id => 'Indonesia',
    AppLocale.en => 'English',
  };
}

const _prefsKey = 'app_locale';

class LocaleNotifier extends Notifier<AppLocale> {
  @override
  AppLocale build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final saved = prefs.getString(_prefsKey);
    return AppLocale.values.firstWhere(
      (l) => l.name == saved,
      orElse: () => AppLocale.id,
    );
  }

  Future<void> set(AppLocale locale) async {
    state = locale;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_prefsKey, locale.name);
  }

  Future<void> toggle() =>
      set(state == AppLocale.id ? AppLocale.en : AppLocale.id);
}

final localeProvider = NotifierProvider<LocaleNotifier, AppLocale>(
  LocaleNotifier.new,
);

const Map<String, Map<String, String>> _strings = {
  // bottom nav
  'nav.kasir': {'id': 'Kasir', 'en': 'Cashier'},
  'nav.riwayat': {'id': 'Riwayat', 'en': 'History'},
  'nav.notifikasi': {'id': 'Notifikasi', 'en': 'Inbox'},
  'nav.laporan': {'id': 'Laporan', 'en': 'Reports'},
  'nav.profil': {'id': 'Profil', 'en': 'Profile'},

  // categories
  'cat.all': {'id': 'Semua', 'en': 'All'},
  'cat.favorit': {'id': 'Favorit', 'en': 'Favorites'},
  'cat.makanan': {'id': 'Makanan', 'en': 'Food'},
  'cat.minuman': {'id': 'Minuman', 'en': 'Drinks'},
  'cat.snack': {'id': 'Snack', 'en': 'Snacks'},

  // kasir
  'kasir.search': {'id': 'Cari produk...', 'en': 'Search products...'},
  'kasir.view_order': {'id': 'Lihat Pesanan', 'en': 'View Order'},
  'kasir.active': {'id': 'Kasir Aktif', 'en': 'Cashier Active'},
  'kasir.empty_fav': {
    'id': 'Belum ada produk favorit',
    'en': 'No favorite products yet',
  },
  'kasir.not_found': {
    'id': 'Produk tidak ditemukan',
    'en': 'Product not found',
  },
  'kasir.not_found_sub': {
    'id': 'Coba kata kunci lain\natau tambah produk baru',
    'en': 'Try another keyword\nor add a new product',
  },
  'kasir.success': {
    'id': 'Transaksi berhasil!',
    'en': 'Transaction successful!',
  },

  // product management
  'product.title': {'id': 'Manajemen Produk', 'en': 'Product Management'},
  'product.add': {'id': 'Tambah', 'en': 'Add'},
  'product.add_full': {'id': 'Tambah Produk', 'en': 'Add Product'},
  'product.edit': {'id': 'Edit Produk', 'en': 'Edit Product'},
  'product.save_changes': {'id': 'Simpan Perubahan', 'en': 'Save Changes'},
  'product.name': {'id': 'Nama Produk', 'en': 'Product Name'},
  'product.category': {'id': 'Kategori', 'en': 'Category'},
  'product.price': {'id': 'Harga (Rp)', 'en': 'Price (Rp)'},
  'product.name_hint': {
    'id': 'Contoh: Nasi Goreng',
    'en': 'Example: Fried Rice',
  },
  'product.empty_cat': {
    'id': 'Belum ada produk pada kategori ini',
    'en': 'No products in this category yet',
  },
  'product.delete_q': {'id': 'Hapus produk?', 'en': 'Delete product?'},
  'category.add_subtitle': {
    'id': 'Tambahkan kategori baru untuk produk',
    'en': 'Add a new category for products',
  },
  'category.edit_subtitle': {
    'id': 'Ubah nama kategori produk',
    'en': 'Change product category name',
  },
  'category.select_hint': {
    'id':
        'Pilih kategori dari daftar di sebelah kiri\natau tambahkan kategori baru.',
    'en': 'Select a category from the list on the left\nor add a new category.',
  },
  'product.select_outlet': {
    'id': 'Silakan Pilih Outlet',
    'en': 'Please Select an Outlet',
  },
  'product.select_outlet_subtitle': {
    'id':
        'Pilih outlet melalui tab atau chip di atas\nuntuk melihat daftar produk.',
    'en':
        'Select an outlet from the tabs or chips above\nto see the product list.',
  },

  // login
  'login.welcome': {'id': 'Selamat Datang', 'en': 'Welcome'},
  'login.subtitle': {
    'id': 'Masuk untuk mengelola outlet Anda',
    'en': 'Login to manage your outlet',
  },
  'login.email': {'id': 'Email atau Username', 'en': 'Email or Username'},
  'login.password': {'id': 'Password', 'en': 'Password'},
  'login.mode_password': {'id': 'Password', 'en': 'Password'},
  'login.mode_otp': {'id': 'Kode OTP', 'en': 'OTP Code'},
  'login.otp_code': {'id': 'Kode OTP', 'en': 'OTP Code'},
  'login.otp_hint': {
    'id': 'Kami akan mengirim kode 6 digit ke email terdaftar.',
    'en': 'We will send a 6-digit code to your registered email.',
  },
  'login.otp_send': {'id': 'Kirim Kode OTP', 'en': 'Send OTP Code'},
  'login.otp_verify': {'id': 'Verifikasi & Masuk', 'en': 'Verify & Login'},
  'login.otp_resend': {'id': 'Kirim ulang kode', 'en': 'Resend code'},
  'login.otp_sent': {
    'id': 'Kode OTP telah dikirim. Periksa email Anda.',
    'en': 'OTP code has been sent. Please check your email.',
  },
  'login.otp_email_empty': {
    'id': 'Email wajib diisi untuk menerima OTP',
    'en': 'Email is required to receive OTP',
  },
  'login.otp_code_empty': {
    'id': 'Kode OTP harus 6 digit',
    'en': 'OTP code must be 6 digits',
  },
  'login.submit': {'id': 'Masuk ke Akun', 'en': 'Login to Account'},
  'login.forgot': {
    'id': 'Lupa password? Hubungi Admin',
    'en': 'Forgot password? Contact Admin',
  },
  'login.no_account': {
    'id': 'Belum punya akun? ',
    'en': "Don't have an account? ",
  },
  'login.register': {'id': 'Daftar Sekarang', 'en': 'Register Now'},
  'login.error_empty': {
    'id': 'Email dan password wajib diisi',
    'en': 'Email and password are required',
  },
  'login.error_owner': {
    'id': 'Akun Owner hanya dapat digunakan pada Web Dashboard',
    'en': 'Owner accounts can only be used on the Web Dashboard',
  },
  'login.branding_title': {
    'id': 'Optimalkan Bisnis\nAnda Sekarang.',
    'en': 'Optimize Your\nBusiness Now.',
  },
  'login.branding_sub': {
    'id':
        'Kelola transaksi, stok, dan laporan dalam satu aplikasi kasir yang cerdas dan modern.',
    'en':
        'Manage transactions, stock, and reports in one smart and modern cashier application.',
  },
  'login.secure': {'id': 'Aman', 'en': 'Secure'},
  'login.fast': {'id': 'Cepat', 'en': 'Fast'},
  'login.cloud': {'id': 'Cloud', 'en': 'Cloud'},

  // outlets
  'outlet.title': {'id': 'Manajemen Outlet', 'en': 'Outlet Management'},
  'outlet.add': {'id': 'Tambah Outlet', 'en': 'Add Outlet'},
  'outlet.edit': {'id': 'Edit Outlet', 'en': 'Edit Outlet'},
  'outlet.empty': {'id': 'Belum ada outlet', 'en': 'No outlets yet'},
  'outlet.select_hint': {
    'id':
        'Pilih outlet dari daftar di sebelah kiri\natau tambahkan outlet baru.',
    'en': 'Select an outlet from the list on the left\nor add a new outlet.',
  },
  'outlet.name': {'id': 'Nama Outlet', 'en': 'Outlet Name'},
  'outlet.address': {'id': 'Alamat', 'en': 'Address'},
  'outlet.phone': {'id': 'Telepon', 'en': 'Phone'},
  'outlet.staff_list': {'id': 'Daftar Karyawan', 'en': 'Employee List'},
  'outlet.staff_empty': {
    'id': 'Belum ada karyawan ditugaskan',
    'en': 'No employees assigned yet',
  },
  'outlet.delete_q': {'id': 'Hapus outlet?', 'en': 'Delete outlet?'},
  'outlet.delete_msg': {
    'id': 'Karyawan yang terhubung tidak akan ikut dihapus.',
    'en': 'Connected employees will not be deleted.',
  },
  'outlet.name_required': {
    'id': 'Nama outlet wajib diisi',
    'en': 'Outlet name is required',
  },
  'outlet.add_subtitle': {
    'id': 'Tambahkan outlet baru untuk bisnis Anda',
    'en': 'Add a new outlet for your business',
  },
  'outlet.edit_subtitle': {
    'id': 'Ubah informasi outlet',
    'en': 'Change outlet information',
  },

  // employees / users
  'employee.title': {'id': 'Daftar Pengguna', 'en': 'User List'},
  'employee.add': {'id': 'Tambah Pengguna', 'en': 'Add User'},
  'employee.edit': {'id': 'Edit Pengguna', 'en': 'Edit User'},
  'employee.name': {'id': 'Nama Lengkap', 'en': 'Full Name'},
  'employee.username': {'id': 'Username', 'en': 'Username'},
  'employee.role': {'id': 'Peran / Hak Akses', 'en': 'Role / Access Rights'},
  'employee.password_hint': {
    'id': 'Password baru (kosongkan jika tidak diubah)',
    'en': 'New password (leave empty if no change)',
  },
  'table.occupied': {'id': 'TERISI', 'en': 'OCCUPIED'},
  'table.available': {'id': 'TERSEDIA', 'en': 'AVAILABLE'},
  'table.groups': {'id': 'Grup Meja', 'en': 'Table Groups'},
  'table.empty_hint': {
    'id': 'Belum ada area meja.\nKlik "Tambah" untuk memulai.',
    'en': 'No table areas yet.\nClick "Add" to start.',
  },
  'table.select_area': {
    'id': 'Pilih atau tambah area',
    'en': 'Select or add an area',
  },
  'employee.username_hint': {
    'id': 'huruf kecil, tanpa spasi',
    'en': 'lowercase, no spaces',
  },
  'employee.active_msg': {
    'id': 'Pengguna nonaktif tidak bisa login',
    'en': 'Inactive users cannot login',
  },
  'outlet.empty_error': {
    'id': 'Belum ada outlet. Tambahkan outlet terlebih dahulu.',
    'en': 'No outlets yet. Please add an outlet first.',
  },
  'employee.delete_q': {'id': 'Hapus pengguna?', 'en': 'Delete user?'},
  'employee.delete_msg': {
    'id': 'Pengguna ini tidak akan bisa masuk lagi.',
    'en': 'This user will no longer be able to login.',
  },
  'employee.you': {'id': 'KAMU', 'en': 'YOU'},

  // common
  'common.save': {'id': 'Simpan', 'en': 'Save'},
  'common.cancel': {'id': 'Batal', 'en': 'Cancel'},
  'common.delete': {'id': 'Hapus', 'en': 'Delete'},
  'common.loading': {'id': 'Memuat...', 'en': 'Loading...'},
  'common.error': {'id': 'Terjadi kesalahan', 'en': 'An error occurred'},
  'common.success': {'id': 'Berhasil', 'en': 'Success'},
  'common.search': {'id': 'Cari...', 'en': 'Search...'},
  'common.close': {'id': 'Tutup', 'en': 'Close'},
  'common.back': {'id': 'Kembali', 'en': 'Back'},
  'common.retry': {'id': 'Coba Lagi', 'en': 'Retry'},
  'common.offline': {
    'id': 'Koneksi Terputus. Beberapa fitur mungkin tidak berfungsi.',
    'en': 'Connection Lost. Some features may not work.',
  },
  'common.unstable': {
    'id': 'Koneksi Tidak Stabil. Harap cek jaringan Anda.',
    'en': 'Unstable Connection. Please check your network.',
  },
  'product.sku': {'id': 'SKU', 'en': 'SKU'},
  'product.sku_hint': {'id': 'Contoh: MKN-001', 'en': 'Example: MKN-001'},
  'product.barcode': {'id': 'Barcode', 'en': 'Barcode'},
  'product.barcode_hint': {
    'id': 'Contoh: 8990001000017',
    'en': 'Example: 8990001000017',
  },
  'product.generate': {'id': 'Generate', 'en': 'Generate'},
  'product.scan_barcode': {'id': 'Pindai Barcode', 'en': 'Scan Barcode'},
  'product.track_stock': {'id': 'Kelola Stok', 'en': 'Track Stock'},
  'product.track_stock_hint': {
    'id': 'Aktifkan untuk memantau jumlah stok produk',
    'en': 'Enable to track product stock quantity',
  },
  'product.stock': {'id': 'Stok', 'en': 'Stock'},
  'product.stock_hint': {'id': 'Contoh: 50', 'en': 'Example: 50'},
  'product.out_of_stock': {'id': 'Habis', 'en': 'Out of Stock'},
  'product.sold': {'id': 'Terjual', 'en': 'Sold'},
  // Auto-86: bahan resep habis → produk tak bisa dijual.
  'product.ingredient_out': {'id': 'Bahan habis', 'en': 'Out of ingredients'},
  // Auto-86: sisa porsi yang masih bisa dibuat dari stok bahan.
  'product.portions_left': {'id': 'sisa', 'en': 'left'},
  // Auto-86 manual: produk ditandai habis (86) oleh kasir.
  'product.marked_86': {'id': 'Di-86', 'en': 'Marked 86'},
  // Aksi kasir: tandai / pulihkan status 86 manual.
  'product.mark_86': {'id': 'Tandai habis (86)', 'en': 'Mark out (86)'},
  'product.restore_86': {'id': 'Pulihkan', 'en': 'Restore'},
  'product.mark_86_hint': {
    'id': 'Sembunyikan dari penjualan sampai dipulihkan',
    'en': 'Hide from sale until restored',
  },
  'product.restore_86_hint': {
    'id': 'Tampilkan kembali untuk dijual',
    'en': 'Show again for sale',
  },
  'product.marked_86_done': {
    'id': 'ditandai habis (86)',
    'en': 'marked out of stock (86)',
  },
  'product.restored_done': {'id': 'dipulihkan', 'en': 'restored'},
  'product.mark_86_failed': {
    'id': 'Gagal memperbarui status 86',
    'en': 'Failed to update 86 status',
  },
  'scanner.title': {'id': 'Pindai Barcode', 'en': 'Scan Barcode'},
  'scanner.hint': {
    'id': 'Arahkan kamera ke barcode',
    'en': 'Point camera at barcode',
  },
  'scanner.torch': {'id': 'Senter', 'en': 'Torch'},
  'scanner.flip': {'id': 'Balik Kamera', 'en': 'Flip Camera'},
  'scanner.error': {
    'id': 'Tidak dapat mengakses kamera',
    'en': 'Cannot access camera',
  },
  'scanner.not_found': {
    'id': 'Produk tidak ditemukan',
    'en': 'Product not found',
  },
  'scanner.added': {'id': 'ditambahkan ke keranjang', 'en': 'added to cart'},
  'scanner.close': {'id': 'Tutup pemindai', 'en': 'Close scanner'},
  'scanner.multi_hint': {
    'id': 'Pindai beberapa barcode berturut-turut',
    'en': 'Scan multiple barcodes in a row',
  },
  'product.sku_exists': {
    'id': 'SKU sudah dipakai produk lain',
    'en': 'SKU already used by another product',
  },
  'product.category_hint': {
    'id': 'Pilih kategori produk',
    'en': 'Choose product category',
  },
  'product.category_empty_hint': {
    'id': 'Belum ada kategori di outlet ini',
    'en': 'No categories in this outlet',
  },

  // payment
  'payment.customer_name': {'id': 'Nama Pembeli', 'en': 'Customer Name'},
  'payment.customer_name_hint': {'id': 'Opsional', 'en': 'Optional'},

  // order type
  'order.type': {'id': 'Tipe Pesanan', 'en': 'Order Type'},
  'order.dine_in': {'id': 'Dine In', 'en': 'Dine In'},
  'order.takeaway': {'id': 'Takeaway', 'en': 'Takeaway'},
  'order.delivery': {'id': 'Delivery', 'en': 'Delivery'},

  // refund
  'refund.action': {'id': 'Refund', 'en': 'Refund'},
  'refund.confirm_title': {
    'id': 'Refund transaksi?',
    'en': 'Refund transaction?',
  },
  'refund.confirm_body': {
    'id':
        'Stok produk akan dikembalikan dan transaksi ditandai refund. Tindakan ini tidak dapat dibatalkan.',
    'en':
        'Product stock will be restored and the transaction marked as refunded. This cannot be undone.',
  },
  'refund.success': {
    'id': 'Transaksi berhasil di-refund',
    'en': 'Transaction refunded',
  },
  'refund.mode_full': {'id': 'Refund penuh', 'en': 'Full refund'},
  'refund.mode_partial': {'id': 'Refund sebagian', 'en': 'Partial refund'},
  'refund.select_items': {
    'id': 'Pilih item yang diretur',
    'en': 'Select items to refund',
  },
  'refund.select_items_hint': {
    'id': 'Atur jumlah tiap item yang ingin diretur (min. 1 item).',
    'en': 'Set the quantity of each item to refund (min. 1 item).',
  },
  'refund.status_partial': {'id': 'Retur sebagian', 'en': 'Partially refunded'},
  'refund.refunded_amount': {'id': 'Total diretur', 'en': 'Refunded'},
  'refund.item_refunded': {'id': 'Diretur', 'en': 'Refunded'},

  // common

  // laporan
  'report.title': {'id': 'Laporan Penjualan', 'en': 'Sales Report'},
  'report.daily': {'id': 'Harian', 'en': 'Daily'},
  'report.monthly': {'id': 'Bulanan', 'en': 'Monthly'},
  'report.yearly': {'id': 'Tahunan', 'en': 'Yearly'},
  'report.revenue': {'id': 'Pendapatan', 'en': 'Revenue'},
  'report.transactions': {'id': 'Transaksi', 'en': 'Transactions'},
  'report.items_sold': {'id': 'Produk Terjual', 'en': 'Items Sold'},
  'report.average': {'id': 'Rata-rata', 'en': 'Average'},
  'report.per_hour': {'id': 'Per Jam', 'en': 'Per Hour'},
  'report.per_day': {'id': 'Per Hari', 'en': 'Per Day'},
  'report.per_month': {'id': 'Per Bulan', 'en': 'Per Month'},
  'report.export': {'id': 'Ekspor', 'en': 'Export'},
  'report.export_title': {'id': 'Ekspor Laporan', 'en': 'Export Report'},
  'report.export_pdf': {'id': 'PDF', 'en': 'PDF'},
  'report.export_excel': {'id': 'CSV', 'en': 'CSV'},
  'report.empty': {
    'id': 'Tidak ada transaksi pada periode ini',
    'en': 'No transactions in this period',
  },
  'report.top_products': {'id': 'Produk Terlaris', 'en': 'Top Products'},
  'report.qty_sold': {'id': 'Terjual', 'en': 'Sold'},
  'report.revenue_short': {'id': 'Omzet', 'en': 'Revenue'},
  'report.cashier_performance': {
    'id': 'Kinerja Kasir',
    'en': 'Cashier Performance',
  },
  'report.cashier_trx': {'id': 'Transaksi', 'en': 'Transactions'},
  'report.cashier_empty': {
    'id': 'Belum ada transaksi kasir',
    'en': 'No cashier transactions yet',
  },

  // riwayat
  'history.title': {'id': 'Riwayat Transaksi', 'en': 'Transaction History'},
  'history.empty': {'id': 'Belum ada transaksi', 'en': 'No transactions yet'},
  'history.detail': {'id': 'Detail Transaksi', 'en': 'Transaction Detail'},
  'history.share': {'id': 'Bagikan', 'en': 'Share'},
  'history.share_receipt': {
    'id': 'Bagikan Resi (Gambar)',
    'en': 'Share Receipt (Image)',
  },

  // profil
  'profile.title': {'id': 'Profil', 'en': 'Profile'},
  'profile.products': {'id': 'Manajemen Produk', 'en': 'Product Management'},
  'profile.categories': {'id': 'Kategori Produk', 'en': 'Product Categories'},
  'profile.print': {'id': 'Printer Termal', 'en': 'Thermal Printers'},
  'profile.tax': {'id': 'Pajak', 'en': 'Tax'},
  'profile.display': {'id': 'Tampilan Card', 'en': 'Card Display'},
  'profile.language': {'id': 'Bahasa', 'en': 'Language'},
  'profile.access_rights': {'id': 'Hak Akses', 'en': 'Access Rights'},
  'profile.group_products': {
    'id': 'Produk & Inventori',
    'en': 'Products & Inventory',
  },
  'profile.group_ops': {'id': 'Operasional Toko', 'en': 'Store Operations'},
  'profile.group_users': {'id': 'Karyawan & Akses', 'en': 'Employees & Access'},
  'profile.group_crm': {'id': 'CRM & Pelanggan', 'en': 'CRM & Customers'},
  'profile.group_app': {'id': 'Pengaturan Aplikasi', 'en': 'App Settings'},
  'profile.outlets': {'id': 'Kelola Outlet', 'en': 'Manage Outlets'},
  'profile.order_types': {'id': 'Tipe Pesanan', 'en': 'Order Types'},
  'profile.tables': {'id': 'Manajemen Meja', 'en': 'Table Management'},
  'profile.shifts': {'id': 'Riwayat Shift', 'en': 'Shift History'},
  'profile.payments': {'id': 'Metode Pembayaran', 'en': 'Payment Methods'},
  'profile.users': {'id': 'Daftar Pengguna', 'en': 'User List'},
  'profile.customers': {'id': 'Data Pelanggan', 'en': 'Customer Data'},
  'profile.loyalty': {'id': 'Loyalty & Poin', 'en': 'Loyalty & Points'},
  'profile.close_shift': {'id': 'Tutup Shift', 'en': 'Close Shift'},
  'profile.logout': {'id': 'Keluar Akun', 'en': 'Logout'},
  'profile.logout_q': {'id': 'Keluar?', 'en': 'Logout?'},
  'profile.logout_msg': {
    'id': 'Apakah Anda yakin ingin keluar dari akun ini?',
    'en': 'Are you sure you want to logout from this account?',
  },
  'profile.empty_detail': {
    'id': 'Pilih menu di samping untuk melihat pengaturan.',
    'en': 'Select a menu on the side to view settings.',
  },
  'profile.all_outlets': {'id': 'Semua Outlet', 'en': 'All Outlets'},

  // access rights (owner-only)
  'access_rights.title': {
    'id': 'Manajemen Hak Akses',
    'en': 'Access Rights Management',
  },
  'access_rights.owner_note': {
    'id':
        'Pemilik memiliki seluruh hak akses. Atur izin untuk peran Admin dan Kasir di bawah.',
    'en':
        'Owner has full access. Configure permissions for Admin and Cashier roles below.',
  },
  'access_rights.not_authorized': {
    'id': 'Hanya pemilik yang dapat mengatur hak akses',
    'en': 'Only the owner can manage access rights',
  },
  'access_rights.no_access': {
    'id': 'Anda tidak memiliki akses ke halaman ini',
    'en': 'You do not have access to this page',
  },
  'access_rights.role_admin': {'id': 'Admin', 'en': 'Admin'},
  'access_rights.role_admin_desc': {
    'id': 'Peran manajerial — biasanya kelola produk dan laporan',
    'en': 'Managerial role — usually manages products and reports',
  },
  'access_rights.role_kasir': {'id': 'Kasir', 'en': 'Cashier'},
  'access_rights.role_kasir_desc': {
    'id': 'Peran operasional kasir — akses terbatas',
    'en': 'Cashier operational role — limited access',
  },
  'access_rights.reset': {'id': 'Reset', 'en': 'Reset'},
  'access_rights.reset_title': {
    'id': 'Reset ke default?',
    'en': 'Reset to default?',
  },
  'access_rights.reset_body': {
    'id':
        'Semua izin peran ini akan dikembalikan ke pengaturan bawaan. Lanjutkan?',
    'en':
        'All permissions for this role will be restored to factory defaults. Continue?',
  },
  'access_rights.select_all': {'id': 'Pilih Semua', 'en': 'Select All'},
  'access_rights.deselect_all': {'id': 'Hapus Semua', 'en': 'Deselect All'},
  'access_rights.cat_products': {'id': 'PRODUK', 'en': 'PRODUCTS'},
  'access_rights.cat_transactions': {'id': 'TRANSAKSI', 'en': 'TRANSACTIONS'},
  'access_rights.cat_settings': {'id': 'PENGATURAN', 'en': 'SETTINGS'},

  // permissions
  'perm.manageProducts': {'id': 'Kelola Produk', 'en': 'Manage Products'},
  'perm.manageProducts.desc': {
    'id': 'Menambah, mengedit, dan menghapus produk',
    'en': 'Add, edit, and delete products',
  },
  'perm.manageCategories': {'id': 'Kelola Kategori', 'en': 'Manage Categories'},
  'perm.manageCategories.desc': {
    'id': 'Menambah dan mengedit kategori produk',
    'en': 'Add and edit product categories',
  },
  'perm.managePrinter': {'id': 'Kelola Printer', 'en': 'Manage Printer'},
  'perm.managePrinter.desc': {
    'id': 'Konfigurasi printer termal',
    'en': 'Configure thermal printer',
  },
  'perm.manageTax': {'id': 'Kelola Pajak', 'en': 'Manage Tax'},
  'perm.manageTax.desc': {
    'id': 'Mengatur pajak penjualan',
    'en': 'Configure sales tax',
  },
  'perm.viewReports': {'id': 'Lihat Laporan', 'en': 'View Reports'},
  'perm.viewReports.desc': {
    'id': 'Melihat laporan penjualan',
    'en': 'View sales reports',
  },
  'perm.viewHistory': {'id': 'Lihat Riwayat', 'en': 'View History'},
  'perm.viewHistory.desc': {
    'id': 'Melihat riwayat transaksi',
    'en': 'View transaction history',
  },
  'perm.refund': {'id': 'Refund Transaksi', 'en': 'Refund Transactions'},
  'perm.refund.desc': {
    'id': 'Mengembalikan dana dari transaksi selesai',
    'en': 'Refund completed transactions',
  },
  'perm.giveDiscount': {'id': 'Beri Diskon', 'en': 'Give Discount'},
  'perm.giveDiscount.desc': {
    'id': 'Menerapkan diskon di kasir',
    'en': 'Apply discount at the cashier',
  },
  'perm.markProducts86': {'id': 'Tandai Habis (86)', 'en': 'Mark Out (86)'},
  'perm.markProducts86.desc': {
    'id': 'Menandai produk habis atau memulihkannya di kasir',
    'en': 'Mark a product sold out or restore it at the cashier',
  },

  // category
  'category.title': {'id': 'Kategori Produk', 'en': 'Product Categories'},
  'category.add': {'id': 'Tambah', 'en': 'Add'},
  'category.add_full': {'id': 'Tambah Kategori', 'en': 'Add Category'},
  'category.edit': {'id': 'Edit Kategori', 'en': 'Edit Category'},
  'category.name': {'id': 'Nama Kategori', 'en': 'Category Name'},
  'category.name_hint': {'id': 'Contoh: Dessert', 'en': 'Example: Dessert'},
  'category.empty': {'id': 'Belum ada kategori', 'en': 'No categories yet'},
  'category.delete_q': {'id': 'Hapus kategori?', 'en': 'Delete category?'},
  'category.delete_perm': {
    'id': 'Produk pada kategori ini akan kehilangan kategori.',
    'en': 'Products in this category will become uncategorized.',
  },
  'category.exists': {
    'id': 'Nama kategori sudah ada',
    'en': 'Category name already exists',
  },
};

String tr(String key, AppLocale locale) {
  final entry = _strings[key];
  if (entry == null) return key;
  return entry[locale.name] ?? entry['id'] ?? key;
}

extension TrRef on WidgetRef {
  String t(String key) => tr(key, watch(localeProvider));
}

extension TrRefX on Ref {
  String t(String key) => tr(key, read(localeProvider));
}
