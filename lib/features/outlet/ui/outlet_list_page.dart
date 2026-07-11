import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../app/app_routes.dart';
import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../shared/widgets/master_detail_scaffold.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../../user/data/auth_service.dart';
import '../../user/domain/user.dart';
import '../data/outlet_service.dart';
import '../domain/outlet.dart';
import 'widgets/outlet_list_tile.dart';
import '../../../core/i18n.dart';

class OutletListPage extends ConsumerWidget {
  const OutletListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outletsAsync = ref.watch(outletsProvider);

    return MasterDetailScaffold<Outlet>(
      title: ref.t('outlet.title'),
      asyncItems: outletsAsync,
      identity: (item) => item.remoteId ?? '',
      onRefresh: () => ref.read(outletsProvider.notifier).refresh(),
      // onAddPressed: () => context.push(AppRoutes.outletsNew),
      phoneTileBuilder: (context, outlet) => OutletListTile(
        outlet: outlet,
        onTap: () => context.push(
          AppRoutes.outletsEdit.replaceAll(':id', outlet.remoteId ?? ''),
        ),
      ),
      tabletMasterTileBuilder: (context, outlet, isSelected, onSelect) =>
          OutletListTile(
            outlet: outlet,
            isSelected: isSelected,
            onTap: onSelect,
          ),
      detailBuilder: (context, outlet, isAdding, onSaved, onDeleted) =>
          _OutletDetailPanel(
            outlet: outlet,
            isAdding: isAdding,
            onSaved: onSaved,
            onDeleted: onDeleted,
          ),
      emptyMessage: ref.t('outlet.empty'),
      emptyIcon: AppIcons.storefront,
    );
  }
}

class _OutletDetailPanel extends HookConsumerWidget {
  final Outlet? outlet;
  final bool isAdding;
  final VoidCallback onSaved;
  final VoidCallback onDeleted;

  const _OutletDetailPanel({
    required this.outlet,
    required this.isAdding,
    required this.onSaved,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (outlet == null && !isAdding) {
      return TabletDetailEmptyState(
        icon: AppIcons.storefront,
        title: ref.t('outlet.title'),
        subtitle: ref.t('outlet.select_hint'),
      );
    }

    final existing = outlet;
    final isEdit = existing != null;

    final currentUser = ref.watch(authProvider).user;

    final detailColor = isEdit ? kAccent : kSuccess;

    return Container(
      color: kBg,
      child: Column(
        children: [
          TabletPanelHeader(
            leading: const TabletHeaderBadge(
              icon: AppIcons.storefront,
              color: kPrimary,
            ),
            title: ref.t('outlet.title'),
            trailing: null,
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TabletFormIllustration(
                        icon: AppIcons.storefront,
                        color: detailColor,
                        title: existing?.name ?? '',
                        subtitle: existing?.address ?? '',
                      ),
                      const Gap(24),
                      if (isEdit) ...[
                        Divider(height: 1, color: kDivider),
                        const Gap(24),
                        _StaffSection(
                          outlet: existing,
                          currentUser: currentUser,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffSection extends ConsumerWidget {
  final Outlet outlet;
  final User? currentUser;

  const _StaffSection({required this.outlet, required this.currentUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (outlet.remoteId == null) return const SizedBox.shrink();
    final employeesAsync = ref.watch(outletEmployeesProvider(outlet.remoteId!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const TabletHeaderBadge(
              icon: HugeIcons.strokeRoundedUserGroup,
              color: kPrimary,
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ref.t('outlet.staff_list'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: kTextDark,
                    ),
                  ),
                  employeesAsync.when(
                    data: (list) => Text(
                      '${list.length} orang bergabung',
                      style: TextStyle(fontSize: 12, color: kTextMid),
                    ),
                    error: (_, _) => const Text('Error loading staff'),
                    loading: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => context.push(AppRoutes.employeesNew),
              icon: const Icon(Icons.add, size: 18),
              label: Text(ref.t('product.add')),
              style: TextButton.styleFrom(
                foregroundColor: kPrimary,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const Gap(16),
        employeesAsync.when(
          // Skeleton kartu karyawan supaya tinggi area employee tidak
          // melonjak antara loading → data.
          loading: () => Skeletonizer(
            enabled: true,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, _) => const Gap(8),
              itemBuilder: (_, _) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kDivider),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: kPrimary.withValues(alpha: 0.1),
                      child: const Text('?'),
                    ),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nama Karyawan',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: kTextDark,
                            ),
                          ),
                          Text(
                            'ROLE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: kPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          error: (e, _) => Center(child: Text('$e')),
          data: (list) {
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    ref.t('outlet.staff_empty'),
                    style: TextStyle(
                      fontSize: 12,
                      color: kTextMid,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Gap(8),
              itemBuilder: (ctx, i) {
                final user = list[i];
                final isMe =
                    user.remoteId != null &&
                    user.remoteId == currentUser?.remoteId;

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isMe ? kPrimary.withValues(alpha: 0.05) : kCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isMe ? kPrimary.withValues(alpha: 0.2) : kDivider,
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: kPrimary.withValues(alpha: 0.1),
                        child: Text(
                          (user.name.characters.firstOrNull ?? '?')
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: kPrimary,
                          ),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  user.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: kTextDark,
                                  ),
                                ),
                                if (isMe) ...[
                                  const Gap(6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: kPrimary,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      ref.t('employee.you'),
                                      style: const TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              user.role.name.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: kPrimary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
