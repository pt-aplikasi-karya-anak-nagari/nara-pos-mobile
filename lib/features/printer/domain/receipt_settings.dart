// Domain model untuk pengaturan struk per outlet — backed by
// backend table outlet_receipt_settings (migration 000095).
//
// Sebelumnya configurasi struk hanya di SharedPreferences (per device).
// Sekarang single source of truth di backend supaya:
//   1. Owner web bisa edit branding
//   2. Multi-device kasir di outlet sama konsisten
//   3. Logo + custom fields (Instagram, QR review) bisa disetting
//
// PrinterSettings (SharedPreferences-based) tetap dipakai untuk hal
// yang memang per-device: device MAC bluetooth printer. Field branding
// (storeName/storeAddress/storeFooter/copies/autoPrint/paperSize) bisa
// ter-override dari OutletReceiptSettings kalau row backend ada.

class OutletReceiptSettings {
  final String outletId;
  final int paperSize; // 58 | 72 | 80

  // Header
  final String headerBusinessName;
  final String headerAddress;
  final String headerPhone;
  final String headerTaxId;
  final String? headerLogoUrl;
  final bool headerShowLogo;
  final List<String> headerExtraLines;

  // Footer
  final String footerThanksText;
  final String footerPromoText;
  final bool footerShowQr;
  final String footerQrUrl;
  final String footerQrCaption;

  // Display toggles
  final bool showCashierName;
  final bool showTableNumber;
  final bool showCustomerName;
  final bool showOrderType;
  final bool showTaxBreakdown;
  final bool showPaymentDetail;
  final bool showItemNotes;
  final bool showTransactionId;
  final bool showLoyaltyPoints;

  // Print behavior
  final String fontSize; // small | medium | large
  final int printCopies;
  final bool autoPrintAfterPaid;

  const OutletReceiptSettings({
    required this.outletId,
    this.paperSize = 58,
    this.headerBusinessName = '',
    this.headerAddress = '',
    this.headerPhone = '',
    this.headerTaxId = '',
    this.headerLogoUrl,
    this.headerShowLogo = true,
    this.headerExtraLines = const [],
    this.footerThanksText = 'Terima kasih atas kunjungan Anda!',
    this.footerPromoText = '',
    this.footerShowQr = false,
    this.footerQrUrl = '',
    this.footerQrCaption = 'Scan untuk review',
    this.showCashierName = true,
    this.showTableNumber = true,
    this.showCustomerName = true,
    this.showOrderType = true,
    this.showTaxBreakdown = true,
    this.showPaymentDetail = true,
    this.showItemNotes = true,
    this.showTransactionId = true,
    this.showLoyaltyPoints = true,
    this.fontSize = 'medium',
    this.printCopies = 1,
    this.autoPrintAfterPaid = false,
  });

  factory OutletReceiptSettings.fromJson(Map<String, dynamic> json) {
    final extra = json['header_extra_lines'];
    return OutletReceiptSettings(
      outletId: (json['outlet_id'] as String?) ?? '',
      paperSize: (json['paper_size'] as num?)?.toInt() ?? 58,
      headerBusinessName: (json['header_business_name'] as String?) ?? '',
      headerAddress: (json['header_address'] as String?) ?? '',
      headerPhone: (json['header_phone'] as String?) ?? '',
      headerTaxId: (json['header_tax_id'] as String?) ?? '',
      headerLogoUrl: json['header_logo_url'] as String?,
      headerShowLogo: json['header_show_logo'] as bool? ?? true,
      headerExtraLines: extra is List
          ? extra.map((e) => (e as String?) ?? '').toList()
          : const <String>[],
      footerThanksText: (json['footer_thanks_text'] as String?) ??
          'Terima kasih atas kunjungan Anda!',
      footerPromoText: (json['footer_promo_text'] as String?) ?? '',
      footerShowQr: json['footer_show_qr'] as bool? ?? false,
      footerQrUrl: (json['footer_qr_url'] as String?) ?? '',
      footerQrCaption:
          (json['footer_qr_caption'] as String?) ?? 'Scan untuk review',
      showCashierName: json['show_cashier_name'] as bool? ?? true,
      showTableNumber: json['show_table_number'] as bool? ?? true,
      showCustomerName: json['show_customer_name'] as bool? ?? true,
      showOrderType: json['show_order_type'] as bool? ?? true,
      showTaxBreakdown: json['show_tax_breakdown'] as bool? ?? true,
      showPaymentDetail: json['show_payment_detail'] as bool? ?? true,
      showItemNotes: json['show_item_notes'] as bool? ?? true,
      showTransactionId: json['show_transaction_id'] as bool? ?? true,
      showLoyaltyPoints: json['show_loyalty_points'] as bool? ?? true,
      fontSize: (json['font_size'] as String?) ?? 'medium',
      printCopies: (json['print_copies'] as num?)?.toInt() ?? 1,
      autoPrintAfterPaid: json['auto_print_after_paid'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'paper_size': paperSize,
        'header_business_name': headerBusinessName,
        'header_address': headerAddress,
        'header_phone': headerPhone,
        'header_tax_id': headerTaxId,
        'header_logo_url': headerLogoUrl,
        'header_show_logo': headerShowLogo,
        'header_extra_lines': headerExtraLines,
        'footer_thanks_text': footerThanksText,
        'footer_promo_text': footerPromoText,
        'footer_show_qr': footerShowQr,
        'footer_qr_url': footerQrUrl,
        'footer_qr_caption': footerQrCaption,
        'show_cashier_name': showCashierName,
        'show_table_number': showTableNumber,
        'show_customer_name': showCustomerName,
        'show_order_type': showOrderType,
        'show_tax_breakdown': showTaxBreakdown,
        'show_payment_detail': showPaymentDetail,
        'show_item_notes': showItemNotes,
        'show_transaction_id': showTransactionId,
        'show_loyalty_points': showLoyaltyPoints,
        'font_size': fontSize,
        'print_copies': printCopies,
        'auto_print_after_paid': autoPrintAfterPaid,
      };

  // Default factory — match backend NewDefaultReceiptSettings().
  factory OutletReceiptSettings.defaults(String outletId) {
    return OutletReceiptSettings(outletId: outletId);
  }
}
