import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../../app/theme.dart';

class AppListTile extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isSelected;
  final Color? selectedColor;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  const AppListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isSelected = false,
    this.selectedColor,
    this.padding = const EdgeInsets.all(14),
    this.borderRadius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSelectedColor = selectedColor ?? kPrimary;
    
    return Material(
      color: isSelected ? effectiveSelectedColor.withValues(alpha: 0.08) : kCard,
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: isSelected
                  ? effectiveSelectedColor.withValues(alpha: 0.3)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const Gap(12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DefaultTextStyle(
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? effectiveSelectedColor : kTextDark,
                        fontSize: 14,
                      ),
                      child: title,
                    ),
                    if (subtitle != null) ...[
                      const Gap(2),
                      DefaultTextStyle(
                        style: TextStyle(fontSize: 12, color: kTextMid),
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const Gap(8),
                trailing!,
              ] else if (onTap != null && !isSelected) ...[
                const Gap(8),
                Icon(Icons.chevron_right, color: kTextMid, size: 20),
              ],
              if (isSelected) ...[
                const Gap(8),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: effectiveSelectedColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
