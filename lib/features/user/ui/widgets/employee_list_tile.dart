import 'package:flutter/material.dart';
import '../../domain/user.dart';
import '../../domain/user_role.dart';
import '../../../../app/theme.dart';
import '../../../../shared/widgets/app_list_tile.dart';

class EmployeeListTile extends StatelessWidget {
  final User employee;
  final String outletName;
  final bool isSelected;
  final VoidCallback? onTap;

  const EmployeeListTile({
    super.key,
    required this.employee,
    required this.outletName,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      isSelected: isSelected,
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _roleColor(employee.role).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          employee.name.isEmpty ? '?' : employee.name[0].toUpperCase(),
          style: TextStyle(
            color: _roleColor(employee.role),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(child: Text(employee.name)),
          if (!employee.active)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: kDanger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Nonaktif',
                style: TextStyle(fontSize: 10, color: kDanger),
              ),
            ),
        ],
      ),
      subtitle: Text('@${employee.username} • $outletName'),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _roleColor(employee.role).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          employee.role.label,
          style: TextStyle(
            color: _roleColor(employee.role),
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Color _roleColor(UserRole r) => switch (r) {
    UserRole.admin || UserRole.owner => kAccent,
    UserRole.adminOutlet => kPrimary,
    UserRole.cashier => kSuccess,
  };
}
