import '../../user/domain/user.dart';
import '../../user/domain/user_role.dart';

class OutletStaff {
  int id;

  String? userRemoteId;
  String? outletRemoteId;
  User? user;
  
  int roleIndex;

  OutletStaff({
    this.id = 0,
    this.roleIndex = 2, // Default Kasir
  });

  UserRole get role => roleFromIndex(roleIndex);
  set role(UserRole r) => roleIndex = r.index;

  factory OutletStaff.fromJson(Map<String, dynamic> json) {
    final u = User.fromJson(json);
    return OutletStaff(
      roleIndex: _mapRoleIdToRoleIndex(json['role_id']),
    )
      ..userRemoteId = u.remoteId
      ..user = u;
  }
}

int _mapRoleIdToRoleIndex(dynamic roleId) {
  final id = int.tryParse(roleId.toString()) ?? 4;
  return switch (id) {
    1 => 0, // admin
    2 => 1, // owner
    3 => 2, // admin_outlet
    4 => 3, // cashier
    _ => 3,
  };
}
