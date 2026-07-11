
class OrderType {
  String id;

  String name;

  bool isDefault;

  /// Nama ikon (mengacu pada AppIcons keys atau IconData)
  String iconName;

  bool showInSelection;
  bool showInReceipt;
  bool showInHistory;
  bool showInReport;
  bool isSystem;

  String? outletRemoteId;

  OrderType({
    this.id = '',
    required this.name,
    this.isDefault = false,
    this.iconName = 'storefront',
    this.showInSelection = true,
    this.showInReceipt = true,
    this.showInHistory = true,
    this.showInReport = true,
    this.isSystem = false,
    this.outletRemoteId,
  });

  factory OrderType.fromJson(Map<String, dynamic> json) {
    return OrderType(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      isDefault: json['is_default'] == true,
      iconName: json['icon_name']?.toString() ?? 'storefront',
      showInSelection: json['show_in_selection'] != false,
      showInReceipt: json['show_in_receipt'] != false,
      showInHistory: json['show_in_history'] != false,
      showInReport: json['show_in_report'] != false,
      isSystem: json['is_system'] == true,
      outletRemoteId: json['outlet_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'is_default': isDefault,
      'icon_name': iconName,
      'show_in_selection': showInSelection,
      'show_in_receipt': showInReceipt,
      'show_in_history': showInHistory,
      'show_in_report': showInReport,
      'is_system': isSystem,
    };
  }

  /// Serialisasi setia-fromJson untuk cache offline (EntityCache). Menambah
  /// `outlet_id` yang dibaca fromJson tapi tidak ikut payload create/update.
  Map<String, dynamic> toCacheJson() {
    return {
      ...toJson(),
      'outlet_id': outletRemoteId,
    };
  }
}
