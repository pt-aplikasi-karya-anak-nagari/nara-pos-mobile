import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/i18n.dart';
import '../../../core/responsive.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../../user/data/auth_service.dart';
import '../../user/domain/user_role.dart';
import '../data/access_rights_repository.dart';
import '../domain/permission.dart';

/// Halaman manajemen hak akses — hanya untuk owner.
///
/// Menampilkan Master-Detail pattern untuk tablet, dan vertical list untuk mobile.
class AccessRightsPage extends HookConsumerWidget {
  const AccessRightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final isAdminOwner =
        user?.role == UserRole.admin ||
        user?.role == UserRole.owner ||
        user?.role == UserRole.adminOutlet;
    final isTablet = context.isTablet;

    final selectedRole = useState<UserRole>(UserRole.adminOutlet);

    return Scaffold(
      backgroundColor: isTablet ? kBg : Colors.transparent,
      appBar: isTablet
          ? null
          : AppBar(
              backgroundColor: kCard,
              elevation: 0,
              title: Text(
                ref.t('access_rights.title'),
                style: TextStyle(
                  color: kTextDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              iconTheme: IconThemeData(color: kTextDark),
            ),
      body: SafeArea(
        child: !isAdminOwner
            ? _NotAuthorized(message: ref.t('access_rights.not_authorized'))
            : isTablet
            ? _TabletLayout(
                selectedRole: selectedRole.value,
                onSelect: (r) => selectedRole.value = r,
              )
            : _MobileLayout(),
      ),
    );
  }
}

class _MobileLayout extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accessRightsProvider);
    final horizontalPad = context.responsive<double>(
      compact: 16,
      medium: 20,
      expanded: 24,
      large: 28,
    );

    return ContentConstrained(
      child: ListView(
        padding: EdgeInsets.fromLTRB(horizontalPad, 16, horizontalPad, 32),
        children: [
          _OwnerBanner(message: ref.t('access_rights.owner_note')),
          const Gap(16),

          // ── Permission summary overview ──
          _PermissionSummaryBar(state: state),
          const Gap(16),

          // ── Admin section ──
          _RoleSection(
            role: UserRole.adminOutlet,
            accent: kAccent,
            titleKey: 'access_rights.role_admin',
            subtitleKey: 'access_rights.role_admin_desc',
          ),
          const Gap(16),

          // ── Kasir section ──
          _RoleSection(
            role: UserRole.cashier,
            accent: kSuccess,
            titleKey: 'access_rights.role_kasir',
            subtitleKey: 'access_rights.role_kasir_desc',
          ),
        ],
      ),
    );
  }
}

// ─── Tablet Layout ────────────────────────────────────────────────────────

class _TabletLayout extends StatelessWidget {
  final UserRole selectedRole;
  final ValueChanged<UserRole> onSelect;

  const _TabletLayout({required this.selectedRole, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: _TabletMasterPanel(
            selectedRole: selectedRole,
            onSelect: onSelect,
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: kDivider),
        Expanded(
          flex: 2,
          child: _TabletDetailPanel(
            key: ValueKey(selectedRole),
            role: selectedRole,
          ),
        ),
      ],
    );
  }
}

class _TabletMasterPanel extends ConsumerWidget {
  final UserRole selectedRole;
  final ValueChanged<UserRole> onSelect;

  const _TabletMasterPanel({
    required this.selectedRole,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: kBg,
      child: Column(
        children: [
          TabletPanelHeader(title: ref.t('access_rights.title')),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _OwnerBanner(message: ref.t('access_rights.owner_note')),
                const Gap(24),
                _MasterRoleTile(
                  role: UserRole.adminOutlet,
                  isSelected: selectedRole == UserRole.adminOutlet,
                  onTap: () => onSelect(UserRole.adminOutlet),
                ),
                const Gap(8),
                _MasterRoleTile(
                  role: UserRole.cashier,
                  isSelected: selectedRole == UserRole.cashier,
                  onTap: () => onSelect(UserRole.cashier),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MasterRoleTile extends ConsumerWidget {
  final UserRole role;
  final bool isSelected;
  final VoidCallback onTap;

  const _MasterRoleTile({
    required this.role,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accessRightsProvider);
    final count = state.of(role).length;
    final total = Permission.values.length;
    final accent = role == UserRole.adminOutlet ? kAccent : kSuccess;
    final titleKey = role == UserRole.adminOutlet
        ? 'access_rights.role_admin'
        : 'access_rights.role_kasir';
    final subtitleKey = role == UserRole.adminOutlet
        ? 'access_rights.role_admin_desc'
        : 'access_rights.role_kasir_desc';

    return Material(
      color: isSelected ? accent.withValues(alpha: 0.08) : kCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? accent.withValues(alpha: 0.3)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              TabletHeaderBadge(
                icon: role == UserRole.adminOutlet
                    ? AppIcons.person
                    : AppIcons.storefront,
                color: accent,
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ref.t(titleKey),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected ? accent : kTextDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      ref.t(subtitleKey),
                      style: TextStyle(fontSize: 11, color: kTextMid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Gap(8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count/$total',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              if (isSelected) ...[
                const Gap(8),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: accent,
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

class _TabletDetailPanel extends ConsumerWidget {
  final UserRole role;

  const _TabletDetailPanel({super.key, required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = role == UserRole.adminOutlet ? kAccent : kSuccess;
    final titleKey = role == UserRole.adminOutlet
        ? 'access_rights.role_admin'
        : 'access_rights.role_kasir';

    return Container(
      color: kBg,
      child: Column(
        children: [
          TabletPanelHeader(
            leading: TabletHeaderBadge(
              icon: role == UserRole.adminOutlet
                  ? AppIcons.person
                  : AppIcons.storefront,
              color: accent,
            ),
            title: ref.t(titleKey),
          ),
          // ── Permissions List ──
          Expanded(
            child: Container(
              color: kCard,
              child: _PermissionsListContent(role: role, accent: accent),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared Components ───────────────────────────────────────────────────

class _PermissionsListContent extends ConsumerWidget {
  final UserRole role;
  final Color accent;

  const _PermissionsListContent({required this.role, required this.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accessRightsProvider);
    final notifier = ref.read(accessRightsProvider.notifier);
    final effective = state.of(role);
    final isDefault = state.isDefault(role);

    Future<void> confirmReset() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ref.t('access_rights.reset_title')),
          content: Text(ref.t('access_rights.reset_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ref.t('common.cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                ref.t('access_rights.reset'),
                style: const TextStyle(color: kPrimary),
              ),
            ),
          ],
        ),
      );
      if (ok == true) {
        await notifier.resetToDefault(role);
      }
    }

    Future<void> toggleAll(bool enable) async {
      for (final p in Permission.values) {
        await notifier.setPermission(role, p, enable);
      }
    }

    // Group permissions by category
    final grouped = <_PermCategory, List<Permission>>{};
    for (final p in Permission.values) {
      grouped.putIfAbsent(_categoryOf(p), () => []).add(p);
    }

    final enabledCount = effective.length;
    final totalCount = Permission.values.length;
    final allEnabled = enabledCount == totalCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Bulk actions bar ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: kDivider)),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: () => toggleAll(!allEnabled),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: allEnabled ? kPrimary.withValues(alpha: 0.08) : kBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: allEnabled
                          ? kPrimary.withValues(alpha: 0.2)
                          : kDivider,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        allEnabled
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 16,
                        color: allEnabled ? kPrimary : kTextMid,
                      ),
                      const Gap(6),
                      Text(
                        allEnabled
                            ? ref.t('access_rights.deselect_all')
                            : ref.t('access_rights.select_all'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: allEnabled ? kPrimary : kTextMid,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: isDefault ? null : confirmReset,
                icon: HugeIcon(
                  icon: AppIcons.reset,
                  color: isDefault ? kTextLight : kPrimary,
                  size: 14,
                ),
                label: Text(
                  ref.t('access_rights.reset'),
                  style: const TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: kPrimary,
                  disabledForegroundColor: kTextLight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Grouped permissions ──
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final category in _PermCategory.values) ...[
                if (grouped.containsKey(category)) ...[
                  _CategoryHeader(category: category, accent: accent),
                  for (var i = 0; i < grouped[category]!.length; i++) ...[
                    _PermissionRow(
                      permission: grouped[category]![i],
                      enabled: effective.contains(grouped[category]![i]),
                      accent: accent,
                      onChanged: (v) => notifier.setPermission(
                        role,
                        grouped[category]![i],
                        v,
                      ),
                    ),
                    if (i < grouped[category]!.length - 1)
                      Divider(
                        height: 1,
                        color: kDivider,
                        indent: 56,
                        endIndent: 16,
                      ),
                  ],
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PermissionSummaryBar extends StatelessWidget {
  final AccessRightsState state;
  const _PermissionSummaryBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final total = Permission.values.length;
    final adminCount = state.of(UserRole.adminOutlet).length;
    final kasirCount = state.of(UserRole.cashier).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _SummaryChip(
            label: 'Owner',
            count: total,
            total: total,
            color: kPrimary,
            icon: HugeIcons.strokeRoundedCrown,
          ),
          const Gap(10),
          _SummaryChip(
            label: 'Admin',
            count: adminCount,
            total: total,
            color: kAccent,
            icon: AppIcons.person,
          ),
          const Gap(10),
          _SummaryChip(
            label: 'Kasir',
            count: kasirCount,
            total: total,
            color: kSuccess,
            icon: AppIcons.storefront,
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;
  final dynamic icon;
  const _SummaryChip({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : count / total;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HugeIcon(icon: icon, color: color, size: 16),
                const Gap(6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            const Gap(8),
            Text(
              '$count / $total',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const Gap(6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                backgroundColor: color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotAuthorized extends StatelessWidget {
  final String message;
  const _NotAuthorized({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: kDanger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: HugeIcon(
                  icon: AppIcons.accessRights,
                  color: kDanger,
                  size: 32,
                ),
              ),
            ),
            const Gap(16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: kTextDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerBanner extends StatelessWidget {
  final String message;
  const _OwnerBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPrimary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kPrimary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: HugeIcon(
                icon: AppIcons.accessRights,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const Gap(12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: kTextDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PermCategory { produk, transaksi, pengaturan }

extension _PermCategoryX on _PermCategory {
  String labelId(WidgetRef ref) => switch (this) {
    _PermCategory.produk => ref.t('access_rights.cat_products'),
    _PermCategory.transaksi => ref.t('access_rights.cat_transactions'),
    _PermCategory.pengaturan => ref.t('access_rights.cat_settings'),
  };

  IconAsset get icon => switch (this) {
    _PermCategory.produk => AppIcons.inventory,
    _PermCategory.transaksi => AppIcons.receiptLong,
    _PermCategory.pengaturan => AppIcons.printer,
  };
}

_PermCategory _categoryOf(Permission p) => switch (p) {
  Permission.manageProducts => _PermCategory.produk,
  Permission.manageCategories => _PermCategory.produk,
  Permission.markProducts86 => _PermCategory.produk,
  Permission.viewReports => _PermCategory.transaksi,
  Permission.viewHistory => _PermCategory.transaksi,
  Permission.refund => _PermCategory.transaksi,
  Permission.giveDiscount => _PermCategory.transaksi,
  Permission.managePrinter => _PermCategory.pengaturan,
  Permission.manageTax => _PermCategory.pengaturan,
};

class _RoleSection extends ConsumerWidget {
  final UserRole role;
  final Color accent;
  final String titleKey;
  final String subtitleKey;
  const _RoleSection({
    required this.role,
    required this.accent,
    required this.titleKey,
    required this.subtitleKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accessRightsProvider);
    final enabledCount = state.of(role).length;
    final totalCount = Permission.values.length;

    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.04)),
            child: Row(
              children: [
                TabletHeaderBadge(
                  icon: role == UserRole.adminOutlet
                      ? AppIcons.person
                      : AppIcons.storefront,
                  color: accent,
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            ref.t(titleKey),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: kTextDark,
                            ),
                          ),
                          const Gap(8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$enabledCount/$totalCount',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Gap(2),
                      Text(
                        ref.t(subtitleKey),
                        style: TextStyle(fontSize: 11.5, color: kTextMid),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Render the shared permissions list
          _PermissionsListContent(role: role, accent: accent),
        ],
      ),
    );
  }
}

class _CategoryHeader extends ConsumerWidget {
  final _PermCategory category;
  final Color accent;
  const _CategoryHeader({required this.category, required this.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          HugeIcon(icon: category.icon, color: kTextMid, size: 14),
          const Gap(8),
          Text(
            category.labelId(ref),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: kTextMid,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends ConsumerWidget {
  final Permission permission;
  final bool enabled;
  final Color accent;
  final ValueChanged<bool> onChanged;
  const _PermissionRow({
    required this.permission,
    required this.enabled,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => onChanged(!enabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: enabled ? accent.withValues(alpha: 0.03) : Colors.transparent,
        child: Row(
          children: [
            // Animated icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: enabled ? accent.withValues(alpha: 0.12) : kBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(
                  enabled ? Icons.check_rounded : Icons.close_rounded,
                  size: 16,
                  color: enabled ? accent : kTextLight,
                ),
              ),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ref.t(permission.labelKey),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: enabled ? kTextDark : kTextMid,
                    ),
                  ),
                  const Gap(2),
                  Text(
                    ref.t(permission.descKey),
                    style: TextStyle(fontSize: 11.5, color: kTextMid),
                  ),
                ],
              ),
            ),
            const Gap(12),
            Switch.adaptive(
              value: enabled,
              onChanged: onChanged,
              activeThumbColor: accent,
            ),
          ],
        ),
      ),
    );
  }
}
