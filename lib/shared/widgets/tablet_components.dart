import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme.dart';
import '../../core/app_icons.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Reusable tablet UI components for master-detail layouts.
//
// These widgets enforce a single source of truth for header bars, icon
// badges, action buttons, and empty-state placeholders used across all
// profile sub-pages (Outlet, Employee, Category, AccessRights, Tax, Printer).
// ═══════════════════════════════════════════════════════════════════════════

// ─── Resizable Divider ────────────────────────────────────────────────────────
/// A vertical divider that can be dragged to resize adjacent panels.
class TabletResizableDivider extends StatelessWidget {
  final ValueChanged<double> onResize;
  final double width;

  const TabletResizableDivider({
    super.key,
    required this.onResize,
    this.width = 12,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) => onResize(details.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: Container(
          width: width,
          color: Colors.transparent,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(width: 1, height: double.infinity, color: kDivider),
              Container(
                width: 6,
                height: 32,
                decoration: BoxDecoration(
                  color: kDivider.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    3,
                    (_) => Container(
                      width: 3,
                      height: 3,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Panel Header ─────────────────────────────────────────────────────────────
/// Standard header bar for tablet panels (master or detail).
///
/// ```
/// ┌──────────────────────────────────────────────────┐
/// │  [leading]  Title          [trailing]            │
/// │             Subtitle (optional)                  │
/// ├──────────────────────────────────────────────────┤
/// ```
class TabletPanelHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  const TabletPanelHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final trailingWidget = trailing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: kCard,
          padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const Gap(14)],
              Expanded(
                child: Container(
                  alignment: Alignment.centerLeft,
                  child: subtitle != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: kTextDark,
                              ),
                            ),
                            Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 11,
                                color: kTextMid,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: kTextDark,
                          ),
                        ),
                ),
              ),
              ?trailingWidget,
            ],
          ),
        ),
        Divider(height: 1, color: kDivider),
      ],
    );
  }
}

// ─── Header Icon Badge ────────────────────────────────────────────────────────
/// A 40×40 rounded square with a tinted background and centred icon.
///
/// Used as `leading` in [TabletPanelHeader].
class TabletHeaderBadge extends StatelessWidget {
  final IconAsset icon;
  final Color color;

  const TabletHeaderBadge({super.key, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: HugeIcon(icon: icon, color: color, size: 20),
      ),
    );
  }
}

// ─── Primary Add Button ───────────────────────────────────────────────────────
/// The "＋ Tambah" filled button used in master panel headers.
class TabletAddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const TabletAddButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kPrimary,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HugeIcon(icon: AppIcons.add, color: Colors.white, size: 16),
              const Gap(6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Delete Button ────────────────────────────────────────────────────────────
/// A 40×40 icon button with danger-tinted background, typically used as
/// `trailing` in a detail [TabletPanelHeader].
class TabletDeleteButton extends StatelessWidget {
  final VoidCallback onTap;

  const TabletDeleteButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: kDanger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: HugeIcon(icon: AppIcons.delete, color: kDanger, size: 20),
        ),
      ),
    );
  }
}

// ─── Detail Empty State ───────────────────────────────────────────────────────
/// Large, centred placeholder shown in the detail panel when no item is
/// selected and the user is not adding a new item.
class TabletDetailEmptyState extends StatelessWidget {
  final IconAsset icon;
  final String title;
  final String subtitle;

  const TabletDetailEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: kCard,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Center(
                child: HugeIcon(icon: icon, color: kPrimary, size: 40),
              ),
            ),
            const Gap(24),
            Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: kTextDark,
              ),
            ),
            const Gap(8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: kTextMid,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Master Empty State ───────────────────────────────────────────────────────
/// Smaller centred placeholder shown inside a master panel's list area
/// when the list is empty.
class TabletMasterEmptyState extends StatelessWidget {
  final IconAsset icon;
  final String message;

  const TabletMasterEmptyState({
    super.key,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: HugeIcon(icon: icon, color: kTextMid, size: 28),
            ),
          ),
          const Gap(12),
          Text(message, style: TextStyle(color: kTextMid, fontSize: 13)),
        ],
      ),
    );
  }
}

// ─── Detail Form Header Illustration ──────────────────────────────────────────
/// The icon + title + subtitle block at the top of a detail form.
class TabletFormIllustration extends StatelessWidget {
  final IconAsset icon;
  final Color color;
  final String title;
  final String? subtitle;

  const TabletFormIllustration({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(22),
          ),
          child: HugeIcon(icon: icon, color: color, size: 36),
        ),
        const Gap(20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: kTextDark,
          ),
        ),
        if (subtitle != null) ...[
          const Gap(6),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: kTextMid),
          ),
        ],
        const Gap(32),
      ],
    );
  }
}

// ─── Primary Save Button ──────────────────────────────────────────────────────
/// Full-width primary action button (Save / Tambah).
class TabletPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;

  const TabletPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}

// ─── Danger Outlined Button ───────────────────────────────────────────────────
/// Full-width outlined danger button (Delete).
class TabletDangerButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const TabletDangerButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const HugeIcon(icon: AppIcons.delete, color: kDanger, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: kDanger,
          side: BorderSide(color: kDanger.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

// ─── Styled Text Field ────────────────────────────────────────────────────────
/// Consistent text field with icon prefix, used in detail form panels.
class TabletStyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final dynamic icon;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final bool autofocus;
  final bool enabled;

  const TabletStyledTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
    this.autofocus = false,
    this.enabled = true,
    this.obscureText = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kDivider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        autofocus: autofocus,
        enabled: enabled,
        obscureText: obscureText,
        style: TextStyle(fontSize: 15, color: enabled ? kTextDark : kTextMid),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: kTextMid, fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: HugeIcon(
              icon: icon,
              color: enabled ? kTextMid : kTextMid.withValues(alpha: 0.5),
              size: 18,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0),
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }
}

// ─── Field Label ──────────────────────────────────────────────────────────────
/// Consistent label above form fields.
class TabletFieldLabel extends StatelessWidget {
  final String label;

  const TabletFieldLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: kTextDark.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
