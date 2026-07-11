import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../app/theme.dart';
import '../../../../core/app_icons.dart';

class QtyButton extends StatelessWidget {
  final IconAsset icon;
  final VoidCallback? onTap;
  final bool primary;
  const QtyButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: primary
              ? (enabled ? kPrimary : kTextMid.withValues(alpha: 0.3))
              : kBg,
          borderRadius: BorderRadius.circular(9),
        ),
        child: HugeIcon(
          icon: icon,
          size: 14,
          color: primary
              ? Colors.white
              : (enabled ? kTextDark : kTextMid),
        ),
      ),
    );
  }
}
