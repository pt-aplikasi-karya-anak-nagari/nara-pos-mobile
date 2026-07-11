class ApiEndpoint {
  static const String login = '/login';
  static const String loginOtpRequest = '/login/otp/request';
  static const String loginOtpVerify = '/login/otp/verify';
  static const String register = '/register';
  static const String refresh = '/refresh';
  static const String logout = '/logout';
  static const String subscriptionPlans = '/subscription-plans';
  static const String outletTypes = '/outlet-types';
  static const String outlets = '/outlets';

  static String outletSubscription(String outletId) =>
      '/outlets/$outletId/subscription';
  static String outletBillingInvoices(String outletId) =>
      '/outlets/$outletId/billing/invoices';
  static String billingCheckout(String outletId) =>
      '/outlets/$outletId/billing/checkout';
  static String billingInvoiceSync(String invoiceId) =>
      '/billing/invoices/$invoiceId/sync-gateway';
  static String billingInvoiceDownload(String invoiceId) =>
      '/billing/invoices/$invoiceId/download';
  static String outletEmployees(String outletId) =>
      '/outlets/$outletId/employees';
  static String outletCategories(String outletId) =>
      '/outlets/$outletId/categories';
  static String outletDetail(String outletId) => '/outlets/$outletId';
  static String outletProducts(String outletId) =>
      '/outlets/$outletId/products';
  static String outletFavorites(String outletId) =>
      '/outlets/$outletId/products/favorites';
  static String outletBestSellers(String outletId) =>
      '/outlets/$outletId/products/best-sellers';
  static String outletCustomers(String outletId) =>
      '/outlets/$outletId/customers';
  static String outletOrderTypes(String outletId) =>
      '/outlets/$outletId/ordertypes';
  static String outletPosTables(String outletId) =>
      '/outlets/$outletId/postables';
  static String outletTableGroups(String outletId) =>
      '/outlets/$outletId/tablegroups';

  static String customer(String id) => '/customers/$id';
  static String orderType(String id) => '/ordertypes/$id';
  static String posTable(String id) => '/postables/$id';
  static String tableGroup(String id) => '/tablegroups/$id';

  static String transactionCheckout(String outletId) =>
      '/transactions/checkout/$outletId';
  static String transactionHistory(String outletId) =>
      '/transactions/outlet/$outletId';

  static String outletPaymentMethods(String outletId) =>
      '/outlets/$outletId/payment-methods';
  static String outletPaymentMethodsSummary(String outletId) =>
      '/outlets/$outletId/payment-methods-summary';
  static String paymentMethod(String id) => '/payment-methods/$id';
  static String paymentMethodActive(String id) => '/payment-methods/$id/active';
  static String paymentMethodDefault(String id) =>
      '/payment-methods/$id/default';

  // Receipt branding settings — pindah dari SharedPreferences ke
  // backend supaya owner web bisa atur + multi-device kasir konsisten.
  static String outletReceiptSettings(String outletId) =>
      '/outlets/$outletId/receipt-settings';
  static String outletReceiptLogo(String outletId) =>
      '/outlets/$outletId/receipt-settings/logo';

  // Image quality settings — atur resize + compression per context.
  static String outletImageSettings(String outletId) =>
      '/outlets/$outletId/image-settings';

  // Loyalty settings per-outlet (enabled, amount_per_point, point_value).
  static String outletLoyaltySettings(String outletId) =>
      '/outlets/$outletId/loyalty-settings';
  // E11: stasiun cetak per outlet (routing struk dapur/bar).
  static String outletPrintStations(String outletId) =>
      '/outlets/$outletId/print-stations';
  // C4: grup modifier/add-on yang melekat pada sebuah produk.
  // GET  → daftar grup untuk produk (dipakai kasir & init form attach).
  // PUT  → set/replace grup untuk produk (body {group_ids: [...]}).
  static String productModifierGroups(String outletId, String productId) =>
      '/outlets/$outletId/products/$productId/modifier-groups';

  // C4 (manajemen): CRUD grup modifier per-outlet — padanan menu
  // "Modifier & Add-on" di dashboard web.
  //   GET/POST   /outlets/:outletId/modifier-groups
  //   PUT/DELETE /outlets/:outletId/modifier-groups/:id
  static String modifierGroups(String outletId) =>
      '/outlets/$outletId/modifier-groups';
  static String modifierGroup(String outletId, String id) =>
      '/outlets/$outletId/modifier-groups/$id';

  // Validasi kode promo untuk checkout (?code=XXX).
  static String outletPromotionsValidate(String outletId) =>
      '/outlets/$outletId/promotions/validate';

  // Permission efektif user yang sedang login di outlet (RBAC dari backend).
  static String outletMyPermissions(String outletId) =>
      '/outlets/$outletId/my-permissions';
}
