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
  'nav.profil': {'id': 'Profil', 'en': 'Profile'},

  // categories
  'cat.all': {'id': 'Semua', 'en': 'All'},
  'cat.makanan': {'id': 'Makanan', 'en': 'Food'},
  'cat.minuman': {'id': 'Minuman', 'en': 'Drinks'},
  'cat.snack': {'id': 'Snack', 'en': 'Snacks'},

  // kasir
  'kasir.search': {'id': 'Cari produk...', 'en': 'Search products...'},
  'kasir.view_order': {'id': 'Lihat Pesanan', 'en': 'View Order'},
  'kasir.active': {'id': 'Kasir Aktif', 'en': 'Cashier Active'},
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
  // Dipakai sebagai lanjutan kalimat: '"Nama Produk" — <teks ini>'.
  'product.delete_perm': {
    'id': 'dihapus permanen dan tidak bisa dikembalikan.',
    'en': 'will be permanently deleted and cannot be restored.',
  },
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
  'login.email': {'id': 'Email', 'en': 'Email'},
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
  // Ketiga kunci di bawah DIPAKAI UI tapi tak pernah didaftarkan, jadi tr()
  // mengembalikannya apa adanya dan layar benar-benar menampilkan tulisan
  // "common.active" / "common.required" / "product.delete_perm" kepada
  // penggunanya. Tak ada crash, tak ada log, tak ada peringatan — lihat
  // test/i18n_kunci_test.dart yang menutup kelasnya, bukan cuma ketiganya.
  'common.active': {'id': 'Aktif', 'en': 'Active'},
  'common.required': {'id': 'Wajib diisi', 'en': 'Required'},
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

  // ── alur kasir: shell, keranjang, pembayaran ──
  'common.no': {'id': 'Tidak', 'en': 'No'},
  'common.add': {'id': 'Tambah', 'en': 'Add'},
  'common.apply': {'id': 'Terapkan', 'en': 'Apply'},
  'common.reset': {'id': 'Reset', 'en': 'Reset'},
  'common.change': {'id': 'Ubah', 'en': 'Change'},
  'common.product': {'id': 'Produk', 'en': 'Product'},
  'shell.scan': {'id': 'Scan', 'en': 'Scan'},
  'shell.calc_short': {'id': 'Hitung', 'en': 'Calc'},
  'shell.calc': {'id': 'Kalkulator', 'en': 'Calculator'},
  'shell.custom_short': {'id': 'Custom', 'en': 'Custom'},
  'shell.custom': {'id': 'Custom Order', 'en': 'Custom Order'},
  'shell.table': {'id': 'Meja', 'en': 'Tables'},
  'shell.draft': {'id': 'Draft', 'en': 'Drafts'},
  'cart.title': {'id': 'Pesanan', 'en': 'Order'},
  'cart.tab_direct_full': {'id': 'Langsung di Kasir', 'en': 'At the Counter'},
  'cart.tab_table_full': {
    'id': 'Pesanan dari Scan Meja',
    'en': 'Table QR Orders',
  },
  'cart.tab_direct': {'id': 'Langsung', 'en': 'Counter'},
  'cart.tab_table': {'id': 'Meja', 'en': 'Tables'},
  'cart.n_products': {'id': '{n} Produk', 'en': '{n} Products'},
  'cart.n_items': {'id': '{n} Item', 'en': '{n} Items'},
  'cart.draft_saved': {
    'id': 'Pesanan disimpan ke draft',
    'en': 'Order saved as a draft',
  },
  'cart.draft_failed': {
    'id': 'Gagal menyimpan draft',
    'en': 'Could not save the draft',
  },
  'cart.draft': {'id': 'Draft', 'en': 'Draft'},
  'cart.save_draft': {'id': 'Simpan Draft', 'en': 'Save Draft'},
  'cart.confirm': {'id': 'Konfirmasi', 'en': 'Confirm'},
  'cart.clear_q': {
    'id': 'Anda yakin ingin menghapus semua pesanan?',
    'en': 'Remove every item from this order?',
  },
  'cart.clear_all_short': {'id': 'Semua', 'en': 'All'},
  'cart.clear_all': {'id': 'Hapus Semua', 'en': 'Clear All'},
  'cart.subtotal': {'id': 'Subtotal', 'en': 'Subtotal'},
  'cart.discount': {'id': 'Diskon', 'en': 'Discount'},
  'cart.total': {'id': 'Total', 'en': 'Total'},
  'cart.pay': {'id': 'Bayar {total}', 'en': 'Pay {total}'},
  'cart.edit_discount': {'id': 'Edit Diskon', 'en': 'Edit Discount'},
  'cart.give_discount': {'id': 'Beri Diskon', 'en': 'Add Discount'},
  'cart.tax_free': {'id': 'Bebas pajak', 'en': 'Tax-free'},
  'cart.bundle': {'id': 'Isi: {items}', 'en': 'Includes: {items}'},
  'cart.discount_badge': {'id': 'DISKON {label}', 'en': 'DISCOUNT {label}'},
  'cart.save': {'id': 'Hemat {amount}', 'en': 'Save {amount}'},
  'cart.note_hint': {
    'id': 'Catatan (mis. tanpa es, extra pedas)',
    'en': 'Note (e.g. no ice, extra spicy)',
  },
  'cat.best': {'id': 'Terlaris', 'en': 'Best Sellers'},
  'kasir.low_stock': {
    'id': '⚠️ Stok menipis: {name} — sisa {stock} {unit}',
    'en': '⚠️ Low stock: {name} — {stock} {unit} left',
  },
  'kasir.paid_title': {'id': 'Pembayaran Berhasil', 'en': 'Payment Successful'},
  'kasir.paid_sub': {
    'id': 'Transaksi #{invoice} telah selesai.',
    'en': 'Transaction #{invoice} is complete.',
  },
  'kasir.total_payment': {'id': 'Total Pembayaran', 'en': 'Payment Total'},
  'kasir.print_receipt': {'id': 'Cetak Struk', 'en': 'Print Receipt'},
  'kasir.load_failed': {
    'id': 'Gagal memuat produk',
    'en': 'Could not load products',
  },
  'kasir.empty': {'id': 'Belum ada produk', 'en': 'No products yet'},
  'kasir.try_other': {
    'id': 'Coba kata kunci lain',
    'en': 'Try another keyword',
  },
  'kasir.add_first': {
    'id': 'Tambahkan produk dulu untuk mulai berjualan',
    'en': 'Add products to start selling',
  },
  'kasir.manage_products': {'id': 'Kelola Produk', 'en': 'Manage Products'},
  'kasir.closed_title': {
    'id': 'Kasir Masih Tertutup',
    'en': 'The Register Is Closed',
  },
  'kasir.closed_sub': {
    'id':
        'Silakan buka kasir terlebih dahulu\nuntuk mulai memproses transaksi.',
    'en': 'Open the register first\nto start taking orders.',
  },
  'kasir.open_now': {'id': 'Buka Kasir Sekarang', 'en': 'Open Register Now'},
  'density.large': {'id': 'Besar', 'en': 'Large'},
  'density.normal': {'id': 'Normal', 'en': 'Normal'},
  'density.small': {'id': 'Kecil', 'en': 'Small'},
  'custom.disabled': {
    'id':
        'Pesanan custom dimatikan Pemilik untuk outlet ini. Pilih produk dari katalog, atau minta Pemilik mengaktifkannya di Pengaturan App.',
    'en':
        'Custom orders are turned off by the Owner for this outlet. Pick a product from the catalog, or ask the Owner to enable them in App Settings.',
  },
  'custom.title': {'id': 'Pesanan Custom', 'en': 'Custom Order'},
  'custom.name': {'id': 'Nama Produk / Pesanan', 'en': 'Item Name'},
  'custom.name_hint': {
    'id': 'Misal: Nasi Goreng Spesial',
    'en': 'e.g. Special Fried Rice',
  },
  'custom.price': {'id': 'Harga Satuan', 'en': 'Unit Price'},
  'custom.add': {'id': 'Tambah ke Keranjang', 'en': 'Add to Cart'},
  'auth.title': {'id': 'Otorisasi', 'en': 'Authorization'},
  'auth.discount_over': {
    'id':
        'Diskon melampaui batas kasir. Minta PIN otorisasi dari Pemilik atau penyelia yang berwenang untuk melanjutkan.',
    'en':
        'This discount is above the cashier limit. Ask the Owner or an authorized supervisor for their PIN to continue.',
  },
  'auth.pin': {'id': 'PIN Otorisasi', 'en': 'Authorization PIN'},
  'auth.pin_hint': {'id': '4-6 digit', 'en': '4–6 digits'},
  'auth.submit': {'id': 'Otorisasi', 'en': 'Authorize'},
  'pay.promo_offline': {
    'id': 'Kode promo butuh internet untuk diperiksa. Coba lagi saat online.',
    'en':
        'Promo codes need an internet connection to be checked. Try again when online.',
  },
  'pay.outlet_inactive': {
    'id': 'Outlet tidak aktif.',
    'en': 'The outlet is not active.',
  },
  'pay.promo_min': {
    'id': 'Min. belanja {amount} untuk promo ini.',
    'en': 'This promo needs a minimum spend of {amount}.',
  },
  'pay.promo_na': {
    'id': 'Promo tidak berlaku untuk item di keranjang.',
    'en': 'This promo does not apply to the items in the cart.',
  },
  'pay.promo_invalid': {
    'id': 'Kode promo tidak valid / tidak aktif.',
    'en': 'Promo code is invalid or inactive.',
  },
  'pay.crop_title': {'id': 'Crop bukti pembayaran', 'en': 'Crop payment proof'},
  'pay.proof_upload_failed': {
    'id': 'Gagal upload bukti: {error}',
    'en': 'Could not upload the proof: {error}',
  },
  'pay.queue_no': {'id': 'Nomor antrian {no}. ', 'en': 'Queue number {no}. '},
  'pay.saved_offline': {
    'id': 'Tersimpan offline — otomatis disinkronkan saat koneksi kembali.',
    'en':
        'Saved offline — it will sync automatically once the connection is back.',
  },
  'pay.save_failed': {
    'id': 'Gagal menyimpan transaksi: {error}',
    'en': 'Could not save the transaction: {error}',
  },
  'pay.add_payment': {'id': 'Tambah Pembayaran', 'en': 'Add Payment'},
  'pay.remaining_amount': {
    'id': 'Sisa tagihan: {amount}',
    'en': 'Remaining: {amount}',
  },
  'pay.method': {'id': 'Metode', 'en': 'Method'},
  'pay.amount': {'id': 'Nominal', 'en': 'Amount'},
  'pay.title': {'id': 'Pembayaran', 'en': 'Payment'},
  'pay.total_due': {'id': 'Total yang harus dibayar', 'en': 'Amount due'},
  'pay.inclusive': {'id': ' · termasuk', 'en': ' · included'},
  'pay.promo': {'id': 'Promo', 'en': 'Promo'},
  'pay.redeem_n': {'id': 'Tukar {n} poin', 'en': 'Redeem {n} points'},
  'pay.total_pay': {'id': 'Total Bayar', 'en': 'Total Due'},
  'pay.promo_code': {'id': 'Kode promo', 'en': 'Promo code'},
  'pay.promo_applied': {
    'id': 'Promo "{name}" diterapkan.',
    'en': 'Promo "{name}" applied.',
  },
  'pay.redeem': {'id': 'Tukar poin', 'en': 'Redeem points'},
  'pay.points_available': {
    'id': '{points} poin tersedia · tukar {n} poin = {amount}',
    'en': '{points} points available · redeem {n} points = {amount}',
  },
  'pay.table': {'id': 'Meja', 'en': 'Table'},
  'pay.points_mult': {'id': 'poin ×{m}', 'en': 'points ×{m}'},
  'pay.type': {'id': 'Tipe Pembayaran', 'en': 'Payment Type'},
  'pay.split_toggle': {
    'id': 'Bagi jadi beberapa metode (Split)',
    'en': 'Split across several methods',
  },
  'pay.split_title': {'id': 'Split Pembayaran', 'en': 'Split Payment'},
  'pay.add_method': {'id': '+ Tambah metode', 'en': '+ Add method'},
  'pay.settled': {'id': 'Lunas', 'en': 'Settled'},
  'pay.remaining': {'id': 'Sisa tagihan', 'en': 'Remaining'},
  'pay.over': {'id': 'Kelebihan', 'en': 'Overpaid'},
  'pay.transfer_detail': {
    'id': 'Detail Rekening Transfer',
    'en': 'Bank Transfer Details',
  },
  'pay.bank': {'id': 'Bank', 'en': 'Bank'},
  'pay.account_no': {'id': 'Nomor Rekening', 'en': 'Account Number'},
  'pay.account_name': {'id': 'Atas Nama', 'en': 'Account Holder'},
  'pay.cash_amount': {'id': 'Jumlah Uang Tunai', 'en': 'Cash Received'},
  'pay.exact': {'id': 'Uang Pas', 'en': 'Exact'},
  'pay.paid': {'id': 'Dibayar', 'en': 'Paid'},
  'pay.change': {'id': 'Kembalian', 'en': 'Change'},
  'pay.confirm_later': {
    'id': 'Simpan Pesanan (Bayar Nanti)',
    'en': 'Save Order (Pay Later)',
  },
  'pay.confirm': {'id': 'Konfirmasi Pembayaran', 'en': 'Confirm Payment'},
  'pay.pick_table': {'id': 'Pilih Meja', 'en': 'Choose a Table'},
  'pay.table_seats': {'id': '{group} — {n} Kursi', 'en': '{group} — {n} seats'},
  'pay.no_table': {'id': 'Belum ada meja dipilih', 'en': 'No table selected'},
  'pay.proof_title': {
    'id': 'Bukti Pembayaran (opsional)',
    'en': 'Payment Proof (optional)',
  },
  'pay.proof_sub': {
    'id': 'Foto QRIS scan, struk transfer, atau receipt mesin EDC.',
    'en': 'A photo of the QRIS scan, transfer slip, or card terminal receipt.',
  },
  'pay.proof_upload': {'id': 'Upload Foto Bukti', 'en': 'Upload Proof Photo'},
  'pay.qris_scan_filled': {
    'id': 'Scan & Bayar — nominal sudah terisi',
    'en': 'Scan & Pay — amount is pre-filled',
  },
  'pay.qris_scan': {'id': 'Scan QRIS untuk Bayar', 'en': 'Scan QRIS to Pay'},
  'pay.qris_manual': {
    'id':
        'Nominal belum masuk ke QR — minta pelanggan mengetik {amount} sendiri.',
    'en':
        'The amount is not in the QR — ask the customer to enter {amount} themselves.',
  },
  'pay.today': {'id': 'Hari ini', 'en': 'Today'},
  'pay.due': {'id': 'Jatuh tempo', 'en': 'Due date'},
  'pay.due_reset': {'id': 'Kembalikan ke hari ini', 'en': 'Reset to today'},
  'pay.due_help': {'id': 'Jatuh tempo pembayaran', 'en': 'Payment due date'},
};

String tr(String key, AppLocale locale) {
  final entry = _strings[key];
  if (entry == null) return key;
  return entry[locale.name] ?? entry['id'] ?? key;
}

/// Seperti [tr], dengan pengganti `{nama}` di dalam teks:
/// `trf('cart.pay', locale, {'total': 'Rp10.000'})` → "Bayar Rp10.000".
/// Urutan kata boleh berbeda per bahasa, jadi kalimat berisi angka/nama
/// JANGAN dirangkai dari potongan terjemahan — pakai satu kunci berparameter.
String trf(String key, AppLocale locale, Map<String, Object?> args) {
  var s = tr(key, locale);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  return s;
}

extension TrRef on WidgetRef {
  String t(String key) => tr(key, watch(localeProvider));
  String tf(String key, Map<String, Object?> args) =>
      trf(key, watch(localeProvider), args);
}

/// Terjemahan lewat [BuildContext] — untuk tempat yang tak punya [WidgetRef]
/// (StatelessWidget, dialog, callback).
///
/// Sumber bahasanya SAMA dengan `ref.t`: [localeProvider]. Bukan
/// `Localizations.localeOf` — itu mengikuti bahasa perangkat bila
/// `MaterialApp.locale` tak diisi, sehingga dua jalur terjemahan bisa
/// menampilkan bahasa yang berbeda di layar yang sama.
///
/// [Localizations] tetap disentuh, tetapi hanya sebagai pemicu: app.dart
/// mengisi `MaterialApp.locale` dari [localeProvider], jadi bergantung padanya
/// membuat widget pemanggil dibangun ulang saat bahasa diganti. Berbeda dari
/// `ref.watch`, ini aman dipanggil dari callback.
///
/// Tanpa ProviderScope di atasnya (mis. tes yang memompa satu widget) jatuh ke
/// bahasa Indonesia.
extension TrContext on BuildContext {
  AppLocale get bahasa {
    Localizations.maybeLocaleOf(this);
    try {
      return ProviderScope.containerOf(
        this,
        listen: false,
      ).read(localeProvider);
    } catch (_) {
      return AppLocale.id;
    }
  }

  String t(String key) => tr(key, bahasa);
  String tf(String key, Map<String, Object?> args) => trf(key, bahasa, args);
}

extension TrRefX on Ref {
  String t(String key) => tr(key, read(localeProvider));
}
