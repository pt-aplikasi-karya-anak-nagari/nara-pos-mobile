import 'table_group.dart';

class PosTable {
  String id;
  String name;
  int capacity;
  int statusIndex; // 0: Available, 1: Occupied, 2: Reserved

  TableGroup? group;
  String? groupId;
  String? outletRemoteId;

  /// Note opsional per meja yang tampil di QR menu sebagai context
  /// untuk customer ("dekat jendela", "smoking", "stop kontak"). Null
  /// = tidak ada note. Backend field: `description` (migration 000094).
  String? description;

  /// Urutan tampil dalam group. Owner di mako-web bisa drag-drop
  /// reorder. Default 0 (akan di-auto-assign backend saat create).
  int sortOrder;

  /// Nama group meja yang di-hydrate dari LEFT JOIN di backend.
  /// Null saat ambil detail single (caller bisa pakai relasi langsung).
  /// Dipakai UI list yang perlu show area name tanpa lookup kedua.
  String? groupName;

  PosTable({
    this.id = '',
    required this.name,
    this.capacity = 2,
    this.statusIndex = 0,
    this.groupId,
    this.outletRemoteId,
    this.description,
    this.sortOrder = 0,
    this.groupName,
  });

  TableStatus get status => TableStatus.values[statusIndex];
  set status(TableStatus value) {}

  factory PosTable.fromJson(Map<String, dynamic> json) {
    return PosTable(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      capacity: json['capacity'] is int
          ? json['capacity']
          : int.tryParse(json['capacity']?.toString() ?? '0') ?? 0,
      statusIndex: json['status_index'] is int
          ? json['status_index']
          : int.tryParse(json['status_index']?.toString() ?? '0') ?? 0,
      groupId: json['group_id']?.toString(),
      outletRemoteId: json['outlet_id']?.toString(),
      // Field baru dari migration 000094 — optional supaya endpoint
      // legacy / data lama yang belum populate tetap parse-able.
      description: json['description']?.toString(),
      sortOrder: json['sort_order'] is int
          ? json['sort_order']
          : int.tryParse(json['sort_order']?.toString() ?? '0') ?? 0,
      groupName: json['group_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'capacity': capacity,
      'status_index': statusIndex,
      'group_id': groupId,
      if (description != null && description!.isNotEmpty)
        'description': description,
      if (sortOrder > 0) 'sort_order': sortOrder,
    };
  }

  /// Serialisasi setia-fromJson untuk cache offline (EntityCache). Menyertakan
  /// `id`, `outlet_id`, `group_name` yang dibaca fromJson tapi tidak ikut
  /// payload create/update.
  Map<String, dynamic> toCacheJson() {
    return {
      'id': id,
      'name': name,
      'capacity': capacity,
      'status_index': statusIndex,
      'group_id': groupId,
      'outlet_id': outletRemoteId,
      'description': description,
      'sort_order': sortOrder,
      'group_name': groupName,
    };
  }
}

enum TableStatus { available, occupied, reserved }
