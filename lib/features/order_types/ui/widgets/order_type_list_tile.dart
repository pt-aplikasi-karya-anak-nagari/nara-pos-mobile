import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../domain/order_type.dart';
import '../../../../app/theme.dart';
import '../../../../core/app_icons.dart';
import '../../../../shared/widgets/app_list_tile.dart';

class OrderTypeListTile extends StatelessWidget {
  final OrderType orderType;
  final bool isSelected;
  final VoidCallback? onTap;

  const OrderTypeListTile({
    super.key,
    required this.orderType,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      isSelected: isSelected,
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected
              ? kPrimary.withValues(alpha: 0.15)
              : kPrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Center(
          child: HugeIcon(
            icon: _getIcon(orderType.iconName),
            color: isSelected ? kPrimary : kTextMid,
            size: 18,
          ),
        ),
      ),
      title: Text(orderType.name),
      subtitle: orderType.isDefault
          ? const Text(
              'Default',
              style: TextStyle(
                color: kSuccess,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            )
          : null,
      // Badge "SISTEM" untuk tipe bawaan (Dine In, Takeaway) sebagai
      // sinyal visual bahwa item tidak dapat diubah / dihapus.
      trailing: orderType.isSystem
          ? Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: kDivider),
              ),
              child: Text(
                'SISTEM',
                style: TextStyle(
                  color: kTextMid,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            )
          : null,
    );
  }

  IconAsset _getIcon(String name) {
    switch (name) {
      case 'takeaway':
        return AppIcons.takeaway;
      case 'delivery':
        return AppIcons.delivery;
      default:
        return AppIcons.storefront;
    }
  }
}
