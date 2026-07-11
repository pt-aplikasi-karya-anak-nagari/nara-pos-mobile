import 'pos_table.dart';

class TableGroup {
  String id;
  String name;
  int order;

  List<PosTable> tables = [];

  String? outletRemoteId;

  TableGroup({this.id = '', required this.name, this.order = 0, this.outletRemoteId});

  factory TableGroup.fromJson(Map<String, dynamic> json) {
    return TableGroup(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      order: json['sort_order'] is int ? json['sort_order'] : int.tryParse(json['sort_order']?.toString() ?? '0') ?? 0,
      outletRemoteId: json['outlet_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'sort_order': order,
    };
  }

  /// Serialisasi setia-fromJson untuk cache offline (EntityCache). Menyertakan
  /// `id` & `outlet_id`. `tables` dihilangkan — di-rehydrate oleh
  /// tableGroupsFutureProvider lewat join dengan cache 'tables'.
  Map<String, dynamic> toCacheJson() {
    return {
      'id': id,
      'name': name,
      'sort_order': order,
      'outlet_id': outletRemoteId,
    };
  }
}
