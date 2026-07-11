class AppRoutes {
  // Auth
  static const String login = '/login';
  static const String loginName = 'login';

  // Shell Branches
  static const String kasir = '/kasir';
  static const String kasirName = 'kasir';

  static const String riwayat = '/riwayat';
  static const String riwayatName = 'riwayat';
  static const String riwayatDetail = '/riwayat/:id';
  static const String riwayatDetailName = 'riwayat-detail';

  static const String laporan = '/laporan';
  static const String laporanName = 'laporan';

  static const String profil = '/profil';
  static const String profilName = 'profil';

  // Products
  static const String products = '/profil/products';
  static const String productsName = 'products';
  static const String productsNew = '/profil/products/new';
  static const String productsNewName = 'products-new';
  static const String productsEdit = '/profil/products/edit/:id';
  static const String productsEditName = 'products-edit';

  // Categories
  static const String categories = '/profil/categories';
  static const String categoriesName = 'categories';
  static const String categoriesNew = '/profil/categories/new';
  static const String categoriesNewName = 'categories-new';
  static const String categoriesEdit = '/profil/categories/edit/:id';
  static const String categoriesEditName = 'categories-edit';

  // Modifier & Add-on (manajemen grup modifier per-outlet)
  static const String modifiers = '/profil/modifiers';
  static const String modifiersName = 'modifiers';

  // Settings
  static const String printer = '/profil/printer';
  static const String printerName = 'printer';
  static const String tax = '/profil/tax';
  static const String taxName = 'tax';
  static const String recipes = '/profil/recipes';
  static const String recipesName = 'recipes';
  static const String expenses = '/profil/expenses';
  static const String expensesName = 'expenses';
  static const String inventory = '/profil/inventory';
  static const String inventoryName = 'inventory';
  static const String display = '/profil/display';
  static const String displayName = 'display';
  static const String loyalty = '/profil/loyalty-settings';
  static const String loyaltyName = 'loyalty';
  static const String billing = '/profil/billing';
  static const String billingName = 'billing';

  // Outlets
  static const String outlets = '/profil/outlets';
  static const String outletsName = 'outlets';
  static const String outletsNew = '/profil/outlets/new';
  static const String outletsNewName = 'outlets-new';
  static const String outletsEdit = '/profil/outlets/edit/:id';
  static const String outletsEditName = 'outlets-edit';

  // Employees
  static const String employees = '/profil/employees';
  static const String employeesName = 'employees';
  static const String employeesNew = '/profil/employees/new';
  static const String employeesNewName = 'employees-new';
  static const String employeesEdit = '/profil/employees/edit/:id';
  static const String employeesEditName = 'employees-edit';

  // Management
  static const String accessRights = '/profil/access-rights';
  static const String accessRightsName = 'access-rights';
  static const String orderTypes = '/profil/order-types';
  static const String orderTypesName = 'order-types';
  static const String tables = '/profil/tables';
  static const String tablesName = 'tables';

  // Attendance (absensi pegawai)
  static const String attendance = '/profil/attendance';
  static const String attendanceName = 'attendance';

  // Notifikasi inbox lokal (riwayat push FCM yang pernah masuk ke device).
  // Path root-level karena dipakai sebagai tab di bottom navigation.
  static const String notifications = '/notifikasi';
  static const String notificationsName = 'notifications';

  // Customers
  static const String customers = '/profil/customers';
  static const String customersName = 'customers';
  static const String customersNew = '/profil/customers/new';
  static const String customersNewName = 'customers-new';
  static const String customersEdit = '/profil/customers/edit/:id';
  static const String customersEditName = 'customers-edit';
  static const String customersDetail = '/profil/customers/:id';
  static const String customersDetailName = 'customers-detail';
}
