import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';
import 'package:flutter/services.dart';
import '../../kasir/providers.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../../app/app_routes.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/i18n.dart';
import '../../../core/responsive.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../../outlet/data/outlet_service.dart';
import 'package:collection/collection.dart';
import '../domain/category.dart';
import '../../user/data/auth_service.dart';
import '../../user/domain/user_role.dart';
import '../../../core/outlet_scope.dart';

/// Halaman kategori produk.
///
/// Phone  : list sederhana, tap → push ke form page.
/// Tablet : master-detail split (WA-style). List di kiri, inline form di kanan.
class CategoryListPage extends HookConsumerWidget {
  const CategoryListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeOutletId = ref.watch(activeOutletIdProvider);

    final categoriesAsync = activeOutletId != null
        ? ref.watch(categoriesByOutletStreamProvider(activeOutletId))
        : const AsyncValue<List<Category>>.data([]);

    final isTablet = context.isTablet;

    // selectedId: null = tidak ada pilihan, >0 = mode "edit"
    // Untuk tablet saja.
    final selectedId = useState<String?>(null);
    final isAdding = useState<bool>(false);
    // Trigger rebuild form panel ketika save/delete terjadi.
    final formRevision = useState(0);
    final masterWidth = useState<double>(350.0);

    if (isTablet) {
      return Scaffold(
        backgroundColor: kBg,
        body: SafeArea(
          child: Row(
            children: [
              // ── Left: Master list ──
              SizedBox(
                width: masterWidth.value,
                child: _TabletMasterPanel(
                  asyncItems: categoriesAsync,
                  activeOutletId: activeOutletId,
                  selectedId: selectedId.value,
                  onSelect: (id) {
                    HapticFeedback.selectionClick();
                    if (selectedId.value == id) {
                      selectedId.value = null;
                    } else {
                      selectedId.value = id;
                    }
                    isAdding.value = false;
                    formRevision.value++;
                  },
                  onAddNew: () {
                    HapticFeedback.mediumImpact();
                    selectedId.value = null;
                    isAdding.value = true;
                    formRevision.value++;
                  },
                ),
              ),
              TabletResizableDivider(
                onResize: (delta) {
                  final newWidth = masterWidth.value + delta;
                  if (newWidth >= 280 && newWidth <= 500) {
                    masterWidth.value = newWidth;
                  }
                },
              ),
              // ── Right: Detail / Form panel ──
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
                  child: _TabletDetailPanel(
                    key: ValueKey(
                      'form-${selectedId.value}-${isAdding.value}-${formRevision.value}',
                    ),
                    categoryId: selectedId.value,
                    isAdding: isAdding.value,
                    onSaved: () {
                      isAdding.value = false;
                      formRevision.value++;
                    },
                    onDeleted: () {
                      selectedId.value = null;
                      isAdding.value = false;
                      formRevision.value++;
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Mobile Layout ──
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard,
        elevation: 0,
        title: Text(
          ref.t('category.title'),
          style: TextStyle(
            color: kTextDark,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        iconTheme: IconThemeData(color: kTextDark),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.push(
            activeOutletId != null
                ? '${AppRoutes.categoriesNew}?outletId=$activeOutletId'
                : AppRoutes.categoriesNew,
          );
        },
        backgroundColor: kPrimary,
        icon: const HugeIcon(icon: AppIcons.add, color: Colors.white),
        label: Text(
          ref.t('category.add'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: categoriesAsync.when(
        // Skeleton meniru tile kategori sehingga transisi loading → data
        // tidak menggeser layout.
        loading: () => Skeletonizer(
          enabled: true,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: 6,
            separatorBuilder: (_, _) => const Gap(10),
            itemBuilder: (_, _) =>
                _CategoryTile(category: Category(name: 'Kategori contoh')),
          ),
        ),
        error: (e, _) => Center(child: Text('$e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(ref.t('category.empty')));
          }
          return _PhoneList(items: items);
        },
      ),
    );
  }
}

// ─── Phone: Simple list (sama seperti sebelumnya) ──────────────────────────

class _PhoneList extends ConsumerWidget {
  final List<Category> items;
  const _PhoneList({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return RefreshIndicator(
        color: kPrimary,
        onRefresh: () async {
          ref.invalidate(categoriesStreamProvider);
          await Future.delayed(const Duration(milliseconds: 400));
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Center(
                child: Text(
                  ref.t('category.empty'),
                  style: TextStyle(color: kTextMid),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: kPrimary,
      onRefresh: () async {
        ref.invalidate(categoriesStreamProvider);
        await Future.delayed(const Duration(milliseconds: 400));
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Gap(10),
        itemBuilder: (_, i) {
          final c = items[i];
          return _DismissibleTile(category: c);
        },
      ),
    );
  }
}

class _DismissibleTile extends ConsumerWidget {
  final Category category;
  const _DismissibleTile({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('category-${category.remoteId}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: kDanger,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const HugeIcon(icon: AppIcons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context, ref, category.name),
      onDismissed: (_) {
        ref.read(outletServiceProvider).deleteCategory(category.remoteId ?? '');
        ref.invalidate(outletCategoriesProvider);
      },
      child: InkWell(
        onTap: () => context.push(
          AppRoutes.categoriesEdit.replaceAll(':id', category.remoteId ?? ''),
        ),
        borderRadius: BorderRadius.circular(14),
        child: _CategoryTile(category: category),
      ),
    );
  }
}

// ─── Tablet: Master Panel (left side) ──────────────────────────────────────

class _TabletMasterPanel extends ConsumerWidget {
  final AsyncValue<List<Category>> asyncItems;
  final String? activeOutletId;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onAddNew;

  const _TabletMasterPanel({
    required this.asyncItems,
    required this.activeOutletId,
    required this.selectedId,
    required this.onSelect,
    required this.onAddNew,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: kBg,
      child: Column(
        children: [
          TabletPanelHeader(
            title: ref.t('category.title'),
            trailing: TabletAddButton(
              label: ref.t('category.add'),
              onTap: onAddNew,
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(categoriesStreamProvider);
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: asyncItems.isLoading && (asyncItems.value ?? []).isEmpty
                  ? Skeletonizer(
                      enabled: true,
                      child: ListView.separated(
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        itemCount: 6,
                        separatorBuilder: (_, _) => const Gap(12),
                        itemBuilder: (_, _) => _SkeletonTile(),
                      ),
                    )
                  : (asyncItems.value ?? []).isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  HugeIcon(
                                    icon: AppIcons.inventory,
                                    color: kTextLight,
                                    size: 48,
                                  ),
                                  const Gap(12),
                                  Text(
                                    ref.t('category.empty'),
                                    style: TextStyle(
                                      color: kTextMid,
                                      fontSize: 13,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const Gap(16),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      HapticFeedback.mediumImpact();
                                      onAddNew();
                                    },
                                    icon: const Icon(Icons.add, size: 18),
                                    label: Text(ref.t('category.add_full')),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kPrimary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                      itemCount: (asyncItems.value ?? []).length,
                      separatorBuilder: (_, _) => const Gap(12),
                      itemBuilder: (_, i) {
                        final c = (asyncItems.value ?? [])[i];
                        final isSelected = c.remoteId == selectedId;
                        return _MasterTile(
                          category: c,
                          isSelected: isSelected,
                          onTap: () => onSelect(c.remoteId),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MasterTile extends StatelessWidget {
  final Category category;
  final bool isSelected;
  final VoidCallback onTap;

  const _MasterTile({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? kPrimary.withValues(alpha: 0.08) : Colors.transparent,
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
                  ? kPrimary.withValues(alpha: 0.3)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isSelected
                      ? kPrimary.withValues(alpha: 0.15)
                      : kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: HugeIcon(
                    icon: AppIcons.inventory,
                    color: isSelected ? kPrimary : kTextMid,
                    size: 18,
                  ),
                ),
              ),
              const Gap(12),
              Expanded(
                child: Text(
                  category.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? kPrimary : kTextDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSelected)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: kPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tablet: Detail Panel (right side — inline form) ───────────────────────

class _TabletDetailPanel extends HookConsumerWidget {
  final String? categoryId;
  final bool isAdding;
  final VoidCallback onSaved;
  final VoidCallback onDeleted;

  const _TabletDetailPanel({
    super.key,
    required this.categoryId,
    required this.isAdding,
    required this.onSaved,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (categoryId == null && !isAdding) {
      return TabletDetailEmptyState(
        icon: AppIcons.inventory,
        title: ref.t('category.title'),
        subtitle: ref.t('category.select_hint'),
      );
    }

    final catsAsync = ref.watch(categoriesStreamProvider);
    final existing = categoryId != null
        ? catsAsync.value?.firstWhereOrNull((c) => c.remoteId == categoryId)
        : null;
    final isEdit = existing != null;

    final nameCtrl = useTextEditingController(text: existing?.name ?? '');
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final saved = useState(false);

    final user = ref.watch(authProvider).user;
    final isOwner = user?.role != UserRole.cashier;
    final outletsAsync = ref.watch(outletsProvider);

    final selectedOutletId = useState<String?>(null);

    useEffect(() {
      if (existing != null) {
        selectedOutletId.value = existing.outletRemoteId;
      } else if (!isOwner && user?.outletRemoteIds.isNotEmpty == true) {
        selectedOutletId.value = user!.outletRemoteIds.first;
      } else {
        final activeId = ref.read(activeOutletIdProvider);
        if (activeId != null) selectedOutletId.value = activeId;
      }
      return null;
    }, [existing, user, isOwner]);

    Future<void> save() async {
      if (!formKey.currentState!.validate()) return;
      if (selectedOutletId.value == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Pilih satu outlet')));
        return;
      }

      final name = nameCtrl.text.trim();
      final category = existing ?? Category(name: name);
      category.name = name;

      if (existing == null) {
        // category.order logic can be removed or simplified for API
        category.order = 0;
      }

      category.outletRemoteId = selectedOutletId.value;
      await ref
          .read(outletServiceProvider)
          .saveCategory(selectedOutletId.value!, category);
      // Invalidate cache kategori supaya halaman list & dropdown kategori
      // di tempat lain (kasir, form produk) langsung memuat data terbaru.
      // Tanpa ini, perubahan baru muncul setelah app di-restart karena
      // FutureProvider.family men-cache nilai sebelumnya.
      ref.invalidate(outletCategoriesProvider);
      saved.value = true;
      nameCtrl.clear();
      onSaved();
    }

    Future<void> confirmDelete() async {
      if (existing == null) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ref.t('category.delete_q')),
          content: Text(
            '"${existing.name}" — ${ref.t('category.delete_perm')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ref.t('common.cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: kDanger),
              child: Text(ref.t('common.delete')),
            ),
          ],
        ),
      );
      if (ok == true) {
        await ref
            .read(outletServiceProvider)
            .deleteCategory(existing.remoteId ?? '');
        ref.invalidate(outletCategoriesProvider);
        onDeleted();
      }
    }

    final detailColor = isEdit ? kAccent : kSuccess;

    return Container(
      color: kBg,
      child: Column(
        children: [
          TabletPanelHeader(
            leading: TabletHeaderBadge(
              icon: isEdit ? AppIcons.inventory : AppIcons.add,
              color: detailColor,
            ),
            title: isEdit ? ref.t('category.edit') : ref.t('category.add_full'),
            trailing: isEdit ? TabletDeleteButton(onTap: confirmDelete) : null,
          ),

          // ── Form content ──
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TabletFormIllustration(
                          icon: AppIcons.inventory,
                          color: detailColor,
                          title: isEdit
                              ? ref.t('category.edit')
                              : ref.t('category.add_full'),
                          subtitle: isEdit
                              ? ref.t('category.edit_subtitle')
                              : ref.t('category.add_subtitle'),
                        ),

                        // Label
                        TabletFieldLabel(label: ref.t('category.name')),
                        // Input
                        Container(
                          decoration: BoxDecoration(
                            color: kCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: kDivider),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextFormField(
                            controller: nameCtrl,
                            autofocus: !isEdit,
                            style: const TextStyle(fontSize: 15),
                            decoration: InputDecoration(
                              hintText: ref.t('category.name_hint'),
                              hintStyle: TextStyle(
                                color: kTextMid,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 16,
                              ),
                              prefixIcon: Padding(
                                padding: EdgeInsets.only(right: 10),
                                child: HugeIcon(
                                  icon: AppIcons.inventory,
                                  color: kTextMid,
                                  size: 18,
                                ),
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 0,
                              ),
                            ),
                            onFieldSubmitted: (_) => save(),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? ref.t('common.required')
                                : null,
                          ),
                        ),
                        const Gap(16),
                        if (isOwner) ...[
                          const TabletFieldLabel(label: 'Outlet'),
                          outletsAsync.when(
                            data: (outlets) => Column(
                              children: outlets.map((o) {
                                return RadioListTile<String>(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    o.name,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  value: o.remoteId!,
                                  // ignore: deprecated_member_use
                                  groupValue: selectedOutletId.value,
                                  activeColor: kPrimary,
                                  // ignore: deprecated_member_use
                                  onChanged: (v) => selectedOutletId.value = v,
                                );
                              }).toList(),
                            ),
                            error: (e, s) => Text(ref.t('common.error')),
                            loading: () => const LinearProgressIndicator(),
                          ),
                        ] else ...[
                          const TabletFieldLabel(label: 'Outlet'),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: kCard,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: kDivider),
                            ),
                            child: Text(
                              ref.watch(activeOutletProvider)?.name ??
                                  ref.t('profile.all_outlets'),
                              style: const TextStyle(
                                color: kPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        const Gap(24),

                        // Save button
                        TabletPrimaryButton(
                          label: isEdit
                              ? ref.t('product.save_changes')
                              : ref.t('category.add_full'),
                          onPressed: save,
                        ),

                        if (isEdit) ...[
                          const Gap(12),
                          TabletDangerButton(
                            label: ref.t('common.delete'),
                            onPressed: confirmDelete,
                          ),
                        ],
                      ],
                    ),
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

// ─── Shared Widgets ────────────────────────────────────────────────────────

class _CategoryTile extends StatelessWidget {
  final Category category;
  const _CategoryTile({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const TabletHeaderBadge(icon: AppIcons.inventory, color: kPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              category.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kTextDark,
              ),
            ),
          ),
          HugeIcon(
            icon: AppIcons.chevronRight,
            color: kTextMid,
            size: 20,
          ),
        ],
      ),
    );
  }
}

Future<bool> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  String name,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ref.t('category.delete_q')),
          content: Text('"$name" — ${ref.t('category.delete_perm')}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ref.t('common.cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: kDanger),
              child: Text(ref.t('common.delete')),
            ),
          ],
        ),
      ) ??
      false;
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Bone.square(size: 38, borderRadius: BorderRadius.circular(10)),
          const Gap(12),
          const Expanded(child: Bone.text(width: 120)),
        ],
      ),
    );
  }
}
