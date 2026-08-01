import 'user_role.dart';

class User {
  String? remoteId;
  String name;
  String username;
  String? email;
  String? phone;
  String passwordHash;

  /// Nama peran PERSIS seperti di server ("Cashier", "Barista", "Waiter", …).
  ///
  /// [roleIndex]/[role] tetap ada sebagai keranjang izin yang kasar — empat
  /// nilai untuk sepuluh peran server — dan itu memang cukup untuk gerbang
  /// lokal saat offline. Yang TIDAK cukup adalah memakainya untuk menampilkan
  /// peran orang: enam dari sepuluh peran server jatuh ke keranjang kasir,
  /// sehingga Barista, Dapur, Pramusaji, Gudang, Finance, dan Supervisor
  /// semuanya tertulis "Kasir" di layar.
  ///
  /// Field ini menyimpan yang sebenarnya, untuk ditampilkan dan untuk dikirim
  /// balik saat menyimpan.
  String roleName;
  int roleIndex;
  bool active;
  List<String> outletRemoteIds = [];
  DateTime createdAt;

  User({
    this.remoteId,
    required this.name,
    required this.username,
    this.email,
    this.phone,
    required this.passwordHash,
    this.roleName = '',
    this.roleIndex = 2,
    this.active = true,
    this.outletRemoteIds = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  UserRole get role => roleFromIndex(roleIndex);
  set role(UserRole r) => roleIndex = r.index;

  factory User.fromJson(Map<String, dynamic> json, {List<dynamic>? outlets}) {
    // Priority 1: 'role' string (new API)
    // Priority 2: 'role_id' int (old API)
    UserRole role;
    if (json.containsKey('role')) {
      final roleStr = json['role'] as String? ?? 'cashier';
      role = switch (roleStr) {
        'admin' => UserRole.admin,
        'owner' => UserRole.owner,
        'admin_outlet' => UserRole.adminOutlet,
        'cashier' => UserRole.cashier,
        _ => UserRole.cashier,
      };
    } else {
      final roleId = json['role_id'] as int? ?? 4;
      role = switch (roleId) {
        1 => UserRole.admin,
        2 => UserRole.owner,
        3 => UserRole.adminOutlet,
        4 => UserRole.cashier,
        _ => UserRole.cashier,
      };
    }

    // Ambil outlet IDs dari argumen outlets (saat login) atau dari json (saat restore dari storage)
    final List<dynamic>? rawOutlets =
        outlets ?? json['outlet_ids'] as List<dynamic>?;
    final List<String> outletIds = rawOutlets != null
        ? rawOutlets.map((o) {
            if (o is Map) return (o['id'] ?? o['remote_id']).toString();
            return o.toString();
          }).toList()
        : (json['outletRemoteIds'] as List<dynamic>?)?.cast<String>() ??
            <String>[];

    return User(
      remoteId: json['id']?.toString(),
      name: json['full_name'] as String? ?? json['name'] as String? ?? '',
      username: json['username'] as String? ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      passwordHash: '',
      // Apa adanya dari server — bukan turunan huruf kecilnya, dan bukan
      // hasil pemetaan ke enum lokal yang kehilangan enam peran.
      roleName: (json['role'] as String?)?.trim() ??
          (json['role_name'] as String?)?.trim() ??
          '',
      roleIndex: role.index,
      active: json['is_active'] as bool? ?? true,
      outletRemoteIds: outletIds,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    int backendRoleId = 4;
    switch (role) {
      case UserRole.admin:
        backendRoleId = 1;
      case UserRole.owner:
        backendRoleId = 2;
      case UserRole.adminOutlet:
        backendRoleId = 3;
      case UserRole.cashier:
        backendRoleId = 4;
    }

    return {
      'id': remoteId,
      'full_name': name,
      'username': username,
      'role_name': roleName,
      'email': email,
      'phone': phone,
      'role_id': backendRoleId,
      'is_active': active,
      'outletRemoteIds': outletRemoteIds,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
