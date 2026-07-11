import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../app/theme.dart';
import '../../core/app_icons.dart';
import '../../core/responsive.dart';
import 'tablet_components.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:flutter/services.dart';
import 'package:sizer/sizer.dart';

class MasterDetailScaffold<T extends Object> extends HookConsumerWidget {
  final String title;
  final AsyncValue<List<T>> asyncItems;
  final Object Function(T item) identity;
  final Widget Function(BuildContext context, T item) phoneTileBuilder;
  final Widget Function(
    BuildContext context,
    T item,
    bool isSelected,
    VoidCallback onSelect,
  )
  tabletMasterTileBuilder;
  final Widget Function(
    BuildContext context,
    T? item,
    bool isAdding,
    VoidCallback onSaved,
    VoidCallback onDeleted,
  )
  detailBuilder;
  final VoidCallback? onAddPressed;
  final Future<void> Function()? onRefresh;
  final String emptyMessage;
  final IconAsset emptyIcon;
  final List<Widget>? appBarActions;
  final Widget? tabletMasterHeaderTrailing;
  final Widget? tabletMasterHeaderBottom;
  final Widget? phoneHeaderSubtitle;

  const MasterDetailScaffold({
    super.key,
    required this.title,
    required this.asyncItems,
    required this.identity,
    required this.phoneTileBuilder,
    required this.tabletMasterTileBuilder,
    required this.detailBuilder,
    this.onAddPressed,
    this.onRefresh,
    this.emptyMessage = 'Belum ada data',
    this.emptyIcon = AppIcons.storefront,
    this.appBarActions,
    this.tabletMasterHeaderTrailing,
    this.tabletMasterHeaderBottom,
    this.phoneHeaderSubtitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTablet = context.isTablet;
    final selectedId = useState<Object?>(null);
    final isAdding = useState<bool>(false);
    final formRevision = useState(0);
    final masterWidth = useState<double>(350.0);

    return Scaffold(
      backgroundColor: kBg,
      appBar: isTablet
          ? null
          : AppBar(
              backgroundColor: kCard,
              elevation: 0,
              iconTheme: IconThemeData(color: kTextDark),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: kTextDark,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  phoneHeaderSubtitle ?? const SizedBox.shrink(),
                ],
              ),
              actions: [
                if (onRefresh != null)
                  IconButton(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.sync, color: kPrimary),
                  ),
                ...?appBarActions,
                const SizedBox(width: 8),
              ],
            ),
      floatingActionButton: isTablet || onAddPressed == null
          ? null
          : FloatingActionButton.extended(
              onPressed: onAddPressed,
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Tambah'),
            ),
      body: SafeArea(
        child: asyncItems.when(
          loading: () => Skeletonizer(
            enabled: true,
            child: isTablet
                ? Row(
                    children: [
                      SizedBox(
                        width: masterWidth.value,
                        child: Column(
                          children: [
                            TabletPanelHeader(title: title),
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: 6,
                                separatorBuilder: (context, index) => const Gap(4),
                                itemBuilder: (context, index) => Bone(
                                  height: 60,
                                  width: double.infinity,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      VerticalDivider(width: 1, color: kDivider),
                      const Expanded(child: Center(child: Bone.text(width: 200))),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: 8,
                    separatorBuilder: (context, index) => const Gap(8),
                    itemBuilder: (context, index) => Bone(
                      height: 70,
                      width: double.infinity,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
          ),
          error: (e, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: kDanger.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.error_outline, color: kDanger, size: 32),
                  ),
                  const Gap(16),
                  Text(
                    'Terjadi Kesalahan',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                      color: kTextDark,
                    ),
                  ),
                  const Gap(8),
                  Text(
                    e.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kTextMid),
                  ),
                  const Gap(24),
                  if (onRefresh != null)
                    SizedBox(
                      width: 200,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: onRefresh,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text('Coba Lagi'),
                      ),
                    ),
                  if (onAddPressed != null) ...[
                    const Gap(12),
                    TextButton(
                      onPressed: onAddPressed,
                      child: const Text('Atau Tambah Data Baru'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          data: (list) {
            if (!isTablet) {
              if (list.isEmpty) {
                return RefreshIndicator(
                  onRefresh: onRefresh ?? () async {},
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 120),
                    children: [
                      Center(
                        child: Text(
                          emptyMessage,
                          style: TextStyle(color: kTextMid),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: onRefresh ?? () async {},
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Gap(8),
                  itemBuilder: (ctx, i) => phoneTileBuilder(ctx, list[i]),
                ),
              );
            }

            // Tablet Layout
            return Row(
              children: [
                SizedBox(
                  width: masterWidth.value,
                  child: Container(
                    color: kBg,
                    child: Column(
                      children: [
                        TabletPanelHeader(
                          title: title,
                          subtitle: list.isNotEmpty
                              ? '${list.length} data'
                              : null,
                          trailing:
                              tabletMasterHeaderTrailing ??
                              (onAddPressed != null
                                  ? TabletAddButton(
                                      label: 'Tambah',
                                      onTap: () {
                                        HapticFeedback.mediumImpact();
                                        selectedId.value = null;
                                        isAdding.value = true;
                                        formRevision.value++;
                                      },
                                    )
                                  : null),
                        ),
                        if (tabletMasterHeaderBottom != null) ...[
                          tabletMasterHeaderBottom!,
                          Divider(height: 1, color: kDivider),
                        ],
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: onRefresh ?? () async {},
                            child: list.isEmpty
                                ? ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    children: [
                                      SizedBox(
                                        height:
                                            MediaQuery.of(context).size.height *
                                            0.6,
                                        child: TabletMasterEmptyState(
                                          icon: emptyIcon,
                                          message: emptyMessage,
                                        ),
                                      ),
                                    ],
                                  )
                                : ListView.separated(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      12,
                                      12,
                                      20,
                                    ),
                                    itemCount: list.length,
                                    separatorBuilder: (_, _) => const Gap(4),
                                    itemBuilder: (ctx, i) {
                                      final item = list[i];
                                      final itemId = identity(item);
                                      final isSelected =
                                          selectedId.value != null &&
                                          selectedId.value == itemId;
                                      return tabletMasterTileBuilder(
                                        ctx,
                                        item,
                                        isSelected,
                                        () {
                                          HapticFeedback.selectionClick();
                                          if (isSelected) {
                                            selectedId.value = null;
                                          } else {
                                            selectedId.value = itemId;
                                          }
                                          isAdding.value = false;
                                          formRevision.value++;
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                TabletResizableDivider(
                  onResize: (delta) {
                    final newWidth = masterWidth.value + delta;
                    if (newWidth >= 280 && newWidth <= 600) {
                      masterWidth.value = newWidth;
                    }
                  },
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.02, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(
                        'detail-${selectedId.value ?? 'null'}-${isAdding.value}-${formRevision.value}',
                      ),
                      child: Builder(
                        builder: (ctx) {
                          // Find the actual item in the list by its ID
                          T? currentItem;
                          if (selectedId.value != null) {
                            try {
                              currentItem = list.firstWhere(
                                (it) => identity(it) == selectedId.value,
                              );
                            } catch (_) {
                              // If not found (maybe deleted), reset selection
                              selectedId.value = null;
                            }
                          }

                          return detailBuilder(
                            context,
                            currentItem,
                            isAdding.value,
                            () {
                              // onSaved
                              isAdding.value = false;
                              formRevision.value++;
                            },
                            () {
                              // onDeleted
                              selectedId.value = null;
                              isAdding.value = false;
                              formRevision.value++;
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
