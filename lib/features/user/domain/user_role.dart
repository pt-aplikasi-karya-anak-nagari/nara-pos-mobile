enum UserRole { admin, owner, adminOutlet, cashier }

extension UserRoleX on UserRole {
  String get label => switch (this) {
    UserRole.admin => 'Admin',
    UserRole.owner => 'Owner',
    UserRole.adminOutlet => 'Admin Outlet',
    UserRole.cashier => 'Kasir',
  };

  bool get canManageEmployees => this != UserRole.cashier;
  bool get canManageOutlets => this == UserRole.admin || this == UserRole.owner;
  bool get canManageProducts => this != UserRole.cashier;
  bool get canManageSettings => this != UserRole.cashier;
  bool get canManagePrinter => true;
  bool get canRefund => this != UserRole.cashier;
  bool get canViewReports => this != UserRole.cashier;
}

UserRole roleFromIndex(int i) {
  if (i < 0 || i >= UserRole.values.length) return UserRole.cashier;
  return UserRole.values[i];
}
