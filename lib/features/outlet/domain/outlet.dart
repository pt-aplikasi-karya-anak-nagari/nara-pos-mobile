import 'outlet_staff.dart';

class Outlet {
  int id;
  String? remoteId;

  String name;
  String address;
  String phone;
  int order;
  bool isActive;

  // Pengaturan pajak per-outlet (lengket di DB, bukan SharedPrefs).
  bool taxEnabled;
  double taxPercent;
  double serviceChargePercent;

  // taxInclusive: apakah harga produk yang owner input sudah termasuk
  // pajak (gross). Kalau true, kasir HARUS strip pajak dari harga total
  // sebelum tampilkan di struk (bukan double-add). Default false sama
  // dengan flow lama (tax di-add on top).
  bool taxInclusive;

  // Label di struk & UI kasir. Owner bisa custom (mis. "PB1", "VAT",
  // "GST"). Default mengikuti konvensi Indonesia.
  String taxName;
  String serviceChargeName;

  // Toggle UI per-outlet: tampilkan badge "Terjual: N" di card produk.
  // Default false supaya outlet existing tidak otomatis ekspos angka.
  bool showSoldCount;

  // Daftar staff (admin, kasir, atau owner lain) yang ditugaskan ke outlet ini
  List<OutletStaff> staffMembers = [];

  Outlet({
    this.id = 0,
    this.remoteId,
    required this.name,
    this.address = '',
    this.phone = '',
    this.order = 0,
    this.isActive = true,
    this.taxEnabled = true,
    this.taxPercent = 10,
    this.serviceChargePercent = 0,
    this.taxInclusive = false,
    this.taxName = 'PPN',
    this.serviceChargeName = 'Service Charge',
    this.showSoldCount = false,
  });

  factory Outlet.fromJson(Map<String, dynamic> json) {
    double parseNum(dynamic v, double fallback) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      return fallback;
    }

    return Outlet(
      remoteId: json['id']?.toString(),
      name: json['name'] as String? ?? '',
      address: json['address'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      taxEnabled: json['tax_enabled'] as bool? ?? true,
      taxPercent: parseNum(json['tax_percent'], 10),
      serviceChargePercent: parseNum(json['service_charge_percent'], 0),
      // Field tax baru (migration 000092). Default match backend supaya
      // outlet existing yg payloadnya belum punya field ini tetap aman.
      taxInclusive: json['tax_inclusive'] as bool? ?? false,
      taxName: (json['tax_name'] as String?)?.trim().isNotEmpty == true
          ? json['tax_name'] as String
          : 'PPN',
      serviceChargeName:
          (json['service_charge_name'] as String?)?.trim().isNotEmpty == true
              ? json['service_charge_name'] as String
              : 'Service Charge',
      showSoldCount: json['show_sold_count'] as bool? ?? false,
    )..staffMembers = (json['employees'] as List? ?? [])
        .map((e) => OutletStaff.fromJson(e))
        .toList();
  }

  /// Serialisasi setia-fromJson untuk cache offline (EntityCache). Berbeda
  /// dari payload API: memetakan balik `remoteId` → 'id' dan menulis seluruh
  /// field tax/service yang dibaca [fromJson]. `employees`/staff sengaja
  /// dihilangkan — tidak dipakai kasir saat offline.
  Map<String, dynamic> toCacheJson() {
    return {
      'id': remoteId,
      'name': name,
      'address': address,
      'phone': phone,
      'is_active': isActive,
      'tax_enabled': taxEnabled,
      'tax_percent': taxPercent,
      'service_charge_percent': serviceChargePercent,
      'tax_inclusive': taxInclusive,
      'tax_name': taxName,
      'service_charge_name': serviceChargeName,
      'show_sold_count': showSoldCount,
    };
  }

  /// Kalkulasi pajak yang konsisten dengan logika di backend
  /// (mako-be/internal/service/outlet_service.go) dan preview di
  /// mako-web (lib/tax.ts).
  ///
  /// Untuk mode `tax_inclusive`, harga di produk dianggap sudah include
  /// pajak — net price = harga / (1 + tax%). Service charge tetap di-add
  /// on top dari net (konvensi resto Indonesia).
  ///
  /// [amount] = subtotal SELURUH baris (setelah diskon per item).
  /// [taxableSubtotal] = Σ subtotal baris yang KENA pajak saja (item
  /// non-pajak dikecualikan). Bila null → dianggap sama dengan [amount]
  /// (semua item kena pajak) supaya pemanggil lama tidak berubah perilaku.
  /// Service charge tetap dihitung dari [amount] penuh dan ikut dipajaki
  /// (mode exclusive), persis seperti server.
  ///
  /// Return tuple: (subtotal, serviceCharge, tax, grandTotal). Subtotal
  /// di sini = net price (sudah strip tax kalau inclusive).
  ({double subtotal, double serviceCharge, double tax, double grandTotal})
      computeTaxBreakdown(double amount, {double? taxableSubtotal}) {
    final taxable = taxableSubtotal ?? amount;
    if (!taxEnabled || amount <= 0) {
      return (
        subtotal: amount,
        serviceCharge: 0,
        tax: 0,
        grandTotal: amount,
      );
    }
    final taxRate = (taxPercent / 100).clamp(0, 1).toDouble();
    final serviceRate = (serviceChargePercent / 100).clamp(0, 1).toDouble();

    if (taxInclusive && taxRate > 0) {
      // Pajak di-back-out HANYA dari porsi taxable; item bebas pajak tidak
      // mengandung PPN di harganya. displaySubtotal (net) = subtotal penuh
      // dikurangi pajak yang di-strip.
      final taxableNet = taxable / (1 + taxRate);
      final tax = taxable - taxableNet;
      final net = amount - tax;
      final service = net * serviceRate;
      return (
        subtotal: net.roundToDouble(),
        serviceCharge: service.roundToDouble(),
        tax: tax.roundToDouble(),
        grandTotal: (net + tax + service).roundToDouble(),
      );
    }

    final service = amount * serviceRate;
    // Service charge ikut dipajaki penuh; basis pajak = taxableSubtotal +
    // service charge.
    final tax = (taxable + service) * taxRate;
    return (
      subtotal: amount.roundToDouble(),
      serviceCharge: service.roundToDouble(),
      tax: tax.roundToDouble(),
      grandTotal: (amount + service + tax).roundToDouble(),
    );
  }
}
