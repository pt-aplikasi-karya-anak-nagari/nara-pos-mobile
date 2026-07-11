class PaymentMethod {
  String id;
  String name;
  String type; // 'cash', 'qris', 'card', 'transfer'
  bool isActive;
  bool isDefault;
  /// True untuk metode bawaan (Cash/QRIS/Card/Transfer) yang di-seed
  /// otomatis backend per outlet. Tidak bisa dihapus & sebagian field-nya
  /// (name/code/type) terkunci di backend.
  bool isSystem;
  String? providerName;
  String? accountNumber;
  String? accountName;
  String? qrData;
  String? outletRemoteId;
  String? logoUrl;
  String code;

  PaymentMethod({
    this.id = '',
    required this.name,
    required this.type,
    this.code = '',
    this.isActive = true,
    this.isDefault = false,
    this.isSystem = false,
    this.providerName,
    this.accountNumber,
    this.accountName,
    this.qrData,
    this.outletRemoteId,
    this.logoUrl,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    // Backend bisa menyimpan type sebagai 'CASH', 'cash', dll. Normalisasi
    // ke lowercase di satu tempat agar semua perbandingan di UI konsisten.
    final rawType = (json['type'] as String? ?? 'cash').toLowerCase().trim();
    return PaymentMethod(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      type: rawType.isEmpty ? 'cash' : rawType,
      isActive: json['is_active'] as bool? ?? true,
      isDefault: json['is_default'] as bool? ?? false,
      isSystem: json['is_system'] as bool? ?? false,
      providerName: json['provider_name'] as String?,
      accountNumber: json['account_number'] as String?,
      accountName: json['account_name'] as String?,
      qrData: json['qr_data'] as String?,
      outletRemoteId: json['outlet_id'] as String?,
      logoUrl: json['logo_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'name': name,
      'code': code.isNotEmpty ? code : name.toUpperCase().replaceAll(' ', '_'),
      'type': type,
      'is_active': isActive,
      'is_default': isDefault,
      'provider_name': providerName ?? '',
      'account_number': accountNumber ?? '',
      'account_name': accountName ?? '',
      'qr_data': qrData ?? '',
      'logo_url': logoUrl ?? '',
    };
  }

  /// Serialisasi setia-fromJson untuk cache offline (EntityCache). Beda dari
  /// [toJson] (payload API) karena menyertakan `is_system` & `outlet_id` yang
  /// dibaca fromJson tapi tidak ikut di payload create/update.
  Map<String, dynamic> toCacheJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'type': type,
      'is_active': isActive,
      'is_default': isDefault,
      'is_system': isSystem,
      'provider_name': providerName,
      'account_number': accountNumber,
      'account_name': accountName,
      'qr_data': qrData,
      'outlet_id': outletRemoteId,
      'logo_url': logoUrl,
    };
  }
}
