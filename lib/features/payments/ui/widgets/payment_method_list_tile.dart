import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../domain/payment_method.dart';
import '../../../../app/theme.dart';
import '../../../../core/app_icons.dart';
import '../../../../shared/widgets/app_list_tile.dart';

class PaymentMethodListTile extends StatelessWidget {
  final PaymentMethod method;
  final bool isSelected;
  final VoidCallback? onTap;

  const PaymentMethodListTile({
    super.key,
    required this.method,
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
            icon: _getIcon(method.type),
            color: isSelected ? kPrimary : kTextMid,
            size: 18,
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(method.name)),
          if (method.isSystem) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(4),
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
            ),
          ],
        ],
      ),
      subtitle: Text(method.type.toUpperCase()),
      trailing: !method.isActive
          ? const Text(
              'Nonaktif',
              style: TextStyle(
                fontSize: 10,
                color: kDanger,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );
  }

  IconAsset _getIcon(String type) {
    switch (type) {
      case 'qris':
        return AppIcons.qrCode;
      case 'card':
        return AppIcons.creditCard;
      case 'transfer':
        return AppIcons.payment;
      default:
        return AppIcons.money;
    }
  }
}
