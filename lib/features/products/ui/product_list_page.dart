import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';
import 'package:flutter/services.dart';
import '../../outlet/data/outlet_service.dart';
import '../../../app/app_routes.dart';
import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/i18n.dart';
import '../../../core/responsive.dart';
import '../../../core/format.dart';
import '../../../core/product_image.dart';
import '../domain/product.dart';
import '../domain/category.dart';
import 'product_form_page.dart';
import '../../kasir/providers.dart';
import '../../user/data/auth_service.dart';
import '../data/product_export_service.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../../../core/outlet_scope.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

String _tabLabel(WidgetRef ref, String t) {
  final keys = {
    'Semua': 'cat.all',
    'Favorit': 'cat.favorit',
    'Makanan': 'cat.makanan',
    'Minuman': 'cat.minuman',
    'Snack': 'cat.snack',
  };
  final key = keys[t];
  return key != null ? ref.t(key) : t;
}

class ProductListPage extends HookConsumerWidget {
  final String? initialOutletId;
  const ProductListPage({super.key, this.initialOutletId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTablet = context.isTablet;

    // Hooks — always called regardless of layout
    final selectedId = useState<String?>(null);
    final query = useState('');
    final activeCategory = useState('Semua');
    final globalOutletId = ref.watch(activeOutletIdProvider);
    final activeOutletId = initialOutletId ?? globalOutletId;
    final searchCtrl = useTextEditingController();
    final scrollController = useScrollController();
    final showBackToTop = useState(false);

    useEffect(() {
      void listener() {
        if (scrollController.offset > 400) {
          if (!showBackToTop.value) showBackToTop.value = true;
        } else {
          if (showBackToTop.value) showBackToTop.value = false;
        }
      }

      scrollController.addListener(listener);
      return () => scrollController.removeListener(listener);
    }, [scrollController]);

    final pagingController = useMemoized(
      () => PagingController<int, Product>(
        fetchPage: (pageKey) async {
          if (activeOutletId == null) return [];

          String? catId;
          bool isFav = activeCategory.value == 'Favorit';

          if (activeCategory.value != 'Semua' && !isFav) {
            final cats = ref
                .read(categoriesByOutletStreamProvider(activeOutletId))
                .value;
            catId = cats
                ?.firstWhereOrNull((c) => c.name == activeCategory.value)
                ?.remoteId;
          }

          final products = await ref
              .read(outletServiceProvider)
              .getProducts(
                activeOutletId,
                categoryId: catId,
                isFavorite: isFav,
                search: query.value.isNotEmpty ? query.value : null,
                page: pageKey,
                limit: 10,
              );

          return products;
        },
        getNextPageKey: (state) {
          final lastPage = state.pages?.lastOrNull;
          if (lastPage != null && lastPage.length < 10) {
            return null;
          }
          return (state.keys?.lastOrNull ?? 0) + 1;
        },
      ),
      [activeOutletId],
    );

    useEffect(() {
      pagingController.refresh();
      return null;
    }, [activeCategory.value, query.value]);

    final masterWidth = useState<double>(350.0);

    // ── Tablet layout ────────────────────────────────────────────────────
    if (isTablet) {
      return Scaffold(
        backgroundColor: kBg,
        floatingActionButton: showBackToTop.value
            ? FloatingActionButton.small(
                onPressed: () => scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                ),
                backgroundColor: kPrimary,
                child: const HugeIcon(
                  icon: AppIcons.chevronUp,
                  color: Colors.white,
                ),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        body: Row(
          children: [
            // ── Left panel ─────────────────────────────────────────────
            SizedBox(
              width: masterWidth.value,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 38,
                                decoration: BoxDecoration(
                                  color: kBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: TextField(
                                  controller: searchCtrl,
                                  onChanged: (v) => query.value = v,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: kTextDark,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: ref.t('kasir.search'),
                                    hintStyle: TextStyle(
                                      fontSize: 13,
                                      color: kTextMid,
                                    ),
                                    prefixIcon: Padding(
                                      padding: EdgeInsets.only(
                                        left: 10,
                                        right: 6,
                                      ),
                                      child: HugeIcon(
                                        icon: AppIcons.search,
                                        color: kTextMid,
                                        size: 16,
                                      ),
                                    ),
                                    prefixIconConstraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
                                    suffixIcon: query.value.isNotEmpty
                                        ? IconButton(
                                            onPressed: () {
                                              searchCtrl.clear();
                                              query.value = '';
                                            },
                                            icon: const Icon(
                                              Icons.close,
                                              size: 16,
                                            ),
                                            color: kTextMid,
                                          )
                                        : null,
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _ExportImportPopup(outletId: activeOutletId),
                          ],
                        ),
                        if (activeOutletId != null) ...[
                          const SizedBox(height: 10),
                          // Category filter chips
                          Consumer(
                            builder: (context, ref, _) {
                              final catsAsync = ref.watch(
                                categoriesByOutletStreamProvider(
                                  activeOutletId,
                                ),
                              );
                              final cats = catsAsync.value ?? [];
                              final tabs = [
                                'Semua',
                                'Favorit',
                                ...cats.map((c) => c.name),
                              ];

                              return SizedBox(
                                height: 30,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: tabs.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 6),
                                  itemBuilder: (_, i) {
                                    final tab = tabs[i];
                                    final isActive =
                                        activeCategory.value == tab;
                                    return GestureDetector(
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        activeCategory.value = tab;
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 150,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isActive ? kPrimary : kBg,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          _tabLabel(ref, tab),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isActive
                                                ? Colors.white
                                                : kTextMid,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  Divider(height: 1, color: kDivider),
                  // Product list
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        pagingController.refresh();
                      },
                      child: activeOutletId == null
                          ? const _OutletSelectionPlaceholder()
                          : PagingListener<int, Product>(
                              controller: pagingController,
                              builder: (context, state, fetchNextPage) =>
                                  PagedListView<int, Product>.separated(
                                    state: state,
                                    fetchNextPage: fetchNextPage,
                                    scrollController: scrollController,
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      12,
                                      12,
                                      40,
                                    ),
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 6),
                                    builderDelegate:
                                        PagedChildBuilderDelegate<Product>(
                                          itemBuilder: (context, p, i) =>
                                              _TabletProductTile(
                                                product: p,
                                                isSelected:
                                                    selectedId.value ==
                                                    p.remoteId,
                                                onTap: () {
                                                  HapticFeedback.selectionClick();
                                                  if (selectedId.value ==
                                                      p.remoteId) {
                                                    selectedId.value = null;
                                                  } else {
                                                    selectedId.value =
                                                        p.remoteId;
                                                  }
                                                },
                                              ),
                                          noItemsFoundIndicatorBuilder: (_) =>
                                              Center(
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    24,
                                                  ),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      HugeIcon(
                                                        icon:
                                                            AppIcons.inventory,
                                                        color: kTextLight,
                                                        size: 48,
                                                      ),
                                                      const Gap(12),
                                                      Text(
                                                        ref.t(
                                                          'product.empty_cat',
                                                        ),
                                                        style: TextStyle(
                                                          color: kTextMid,
                                                          fontSize: 13,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                        ),
                                  ),
                            ),
                    ),
                  ),
                ],
              ),
            ),

            TabletResizableDivider(
              onResize: (delta) {
                final newWidth = masterWidth.value + delta;
                if (newWidth >= 300 && newWidth <= 600) {
                  masterWidth.value = newWidth;
                }
              },
            ),

            // ── Right panel ─────────────────────────────────────────────
            // Full-width panel; the form constrains its own content to 50 %.
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
                child: selectedId.value == null
                    ? _EmptyFormPane(
                        key: const ValueKey('empty'),
                        onAdd: () {
                          HapticFeedback.mediumImpact();
                          selectedId.value = 'new';
                        },
                      )
                    : ProductFormPage(
                        key: ValueKey('form-${selectedId.value}'),
                        productRemoteId: selectedId.value == 'new'
                            ? null
                            : selectedId.value,
                        initialOutletId: activeOutletId,
                        embedded: true,
                        onSaved: () {
                          ref.invalidate(outletCategoriesProvider);
                          ref.invalidate(productsStreamProvider);
                          pagingController.refresh();
                          selectedId.value = null;
                        },
                        onDeleted: () {
                          ref.invalidate(outletCategoriesProvider);
                          ref.invalidate(productsStreamProvider);
                          pagingController.refresh();
                          selectedId.value = null;
                        },
                      ),
              ),
            ),
          ],
        ),
      );
    }

    return _MobileProductScaffold(
      pagingController: pagingController,
      activeCategory: activeCategory,
      query: query,
      searchCtrl: searchCtrl,
      scrollController: scrollController,
      showBackToTop: showBackToTop.value,
    );
  }
}

class _MobileProductScaffold extends ConsumerWidget {
  final PagingController<int, Product> pagingController;
  final ValueNotifier<String> activeCategory;
  final ValueNotifier<String> query;
  final TextEditingController searchCtrl;
  final ScrollController scrollController;
  final bool showBackToTop;

  const _MobileProductScaffold({
    required this.pagingController,
    required this.activeCategory,
    required this.query,
    required this.searchCtrl,
    required this.scrollController,
    required this.showBackToTop,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final outletId = user?.outletRemoteIds.firstOrNull;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard,
        elevation: 0,
        title: Text(
          ref.t('product.title'),
          style: TextStyle(
            color: kTextDark,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        iconTheme: IconThemeData(color: kTextDark),
        actions: [_ExportImportPopup(outletId: outletId)],
      ),
      body: _MobileProductContent(
        outletId: outletId,
        pagingController: pagingController,
        activeCategory: activeCategory,
        query: query,
        scrollController: scrollController,
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showBackToTop)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FloatingActionButton.small(
                onPressed: () => scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                ),
                backgroundColor: kPrimary,
                child: const HugeIcon(
                  icon: AppIcons.chevronUp,
                  color: Colors.white,
                ),
              ),
            ),
          FloatingActionButton.extended(
            onPressed: () async {
              final oid = outletId;
              await context.push(
                oid != null
                    ? '${AppRoutes.productsNew}?outletId=$oid'
                    : AppRoutes.productsNew,
              );
              // Setelah form ditutup, refresh list & cache supaya produk baru
              // langsung muncul tanpa user harus pull-to-refresh manual.
              ref.invalidate(productsStreamProvider);
              pagingController.refresh();
            },
            backgroundColor: kPrimary,
            icon: const HugeIcon(icon: AppIcons.add, color: Colors.white),
            label: Text(
              ref.t('product.add'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }
}

class _MobileProductContent extends ConsumerWidget {
  final String? outletId;
  final PagingController<int, Product> pagingController;
  final ValueNotifier<String> activeCategory;
  final ValueNotifier<String> query;
  final ScrollController scrollController;

  const _MobileProductContent({
    required this.outletId,
    required this.pagingController,
    required this.activeCategory,
    required this.query,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = outletId != null
        ? ref.watch(categoriesByOutletStreamProvider(outletId!))
        : const AsyncValue<List<Category>>.data([]);
    final cats = catsAsync.value ?? [];
    final tabs = ['Semua', 'Favorit', ...cats.map((c) => c.name)];

    return Column(
      children: [
        // Category Chips
        Container(
          color: kCard,
          height: 50,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            scrollDirection: Axis.horizontal,
            itemCount: tabs.length,
            separatorBuilder: (_, _) => const Gap(8),
            itemBuilder: (context, i) {
              final cat = tabs[i];
              final isSelected = activeCategory.value == cat;
              return GestureDetector(
                onTap: () => activeCategory.value = cat,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? kPrimary : kBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _tabLabel(ref, cat),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : kTextMid,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Divider(height: 1, color: kDivider),
        Expanded(
          child: PagingListener<int, Product>(
            controller: pagingController,
            builder: (context, state, fetchNextPage) =>
                PagedListView<int, Product>.separated(
                  state: state,
                  fetchNextPage: fetchNextPage,
                  scrollController: scrollController,
                  padding: const EdgeInsets.all(16),
                  separatorBuilder: (_, _) => const Gap(10),
                  builderDelegate: PagedChildBuilderDelegate<Product>(
                    itemBuilder: (context, p, i) => _ProductTile(
                      product: p,
                      onChanged: () {
                        ref.invalidate(productsStreamProvider);
                        pagingController.refresh();
                      },
                    ),
                    noItemsFoundIndicatorBuilder: (_) => Center(
                      child: Text(
                        ref.t('product.empty_cat'),
                        style: TextStyle(color: kTextMid),
                      ),
                    ),
                  ),
                ),
          ),
        ),
      ],
    );
  }
}

class _OutletSelectionPlaceholder extends ConsumerWidget {
  const _OutletSelectionPlaceholder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const HugeIcon(
                icon: AppIcons.storefront,
                color: kPrimary,
                size: 32,
              ),
            ),
            const Gap(20),
            Text(
              ref.t('product.select_outlet'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: kTextDark,
              ),
              textAlign: TextAlign.center,
            ),
            const Gap(8),
            Text(
              ref.t('product.select_outlet_subtitle'),
              style: TextStyle(
                fontSize: 13,
                color: kTextMid,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tablet: product tile with selection highlight ──────────────────────────

class _TabletProductTile extends ConsumerWidget {
  final Product product;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabletProductTile({
    required this.product,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isSelected ? kPrimary.withValues(alpha: 0.06) : kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? kPrimary.withValues(alpha: 0.35)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ProductImage(
                name: product.name,
                imageUrl: product.imageUrl,
                size: 44,
                radius: 10,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: kTextDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (product.sku?.isEmpty ?? true)
                          ? (product.categoryName ?? '-')
                          : '${product.categoryName ?? '-'} · ${product.sku}',
                      style: TextStyle(fontSize: 11, color: kTextMid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatRupiah(product.price),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: isSelected ? kPrimary : kTextDark,
                    ),
                  ),
                  if (!product.trackStock)
                    const SizedBox.shrink()
                  else if (product.stock <= 0)
                    _SmallBadge(
                      label: ref.t('product.out_of_stock'),
                      color: kDanger,
                    )
                  else
                    _SmallBadge(
                      label: '${ref.t('product.stock')}: ${product.stock}',
                      color: kTextMid,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallBadge extends ConsumerWidget {
  final String label;
  final Color color;
  const _SmallBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Tablet: right-panel empty state ──────────────────────────────────────

class _EmptyFormPane extends ConsumerWidget {
  final VoidCallback onAdd;
  const _EmptyFormPane({super.key, required this.onAdd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const HugeIcon(
                icon: AppIcons.inventory,
                color: kPrimary,
                size: 36,
              ),
            ),
            const Gap(20),
            Text(
              'Pilih produk untuk melihat\natau edit detail',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: kTextDark,
              ),
              textAlign: TextAlign.center,
            ),
            const Gap(8),
            Text(
              'Atau tambah produk baru ke katalog',
              style: TextStyle(fontSize: 13, color: kTextMid),
              textAlign: TextAlign.center,
            ),
            const Gap(24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const HugeIcon(
                icon: AppIcons.add,
                color: Colors.white,
                size: 18,
              ),
              label: Text(ref.t('product.add_full')),
              style: FilledButton.styleFrom(
                backgroundColor: kPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mobile: pull-to-refresh list view ────────────────────────────────────

// ── Mobile: swipeable product tile ───────────────────────────────────────

class _ProductTile extends ConsumerWidget {
  final Product product;
  /// Dipanggil setelah aksi yang mengubah daftar (delete, edit-save). Parent
  /// memakai callback ini untuk refresh paging controller.
  final VoidCallback? onChanged;
  const _ProductTile({required this.product, this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('product-${product.remoteId}'),
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
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(ref.t('product.delete_q')),
                content: Text(
                  '"${product.name}" — ${ref.t('product.delete_perm')}',
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
            ) ??
            false;
      },
      onDismissed: (_) async {
        await ref
            .read(outletServiceProvider)
            .deleteProduct(product.remoteId ?? '');
        ref.invalidate(outletCategoriesProvider);
        onChanged?.call();
      },
      child: InkWell(
        onTap: () async {
          await context.push(
            AppRoutes.productsEdit.replaceAll(':id', product.remoteId ?? ''),
          );
          onChanged?.call();
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              ProductImage(
                name: product.name,
                imageUrl: product.imageUrl,
                size: 48,
                radius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: kTextDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!product.trackStock)
                          const SizedBox.shrink()
                        else if (product.stock <= 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: kDanger,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              ref.t('product.out_of_stock'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: kBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${ref.t('product.stock')}: ${product.stock}',
                              style: TextStyle(
                                color: kTextMid,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (product.isFavorite) ...[
                          const SizedBox(width: 6),
                          const HugeIcon(
                            icon: AppIcons.favorite,
                            color: kFav,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                    const Gap(2),
                    Text(
                      (product.sku?.isEmpty ?? true)
                          ? (product.categoryName ?? '-')
                          : '${product.categoryName ?? '-'} · ${product.sku}',
                      style: TextStyle(fontSize: 11, color: kTextMid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                formatRupiah(product.price),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: kPrimary,
                ),
              ),
              const SizedBox(width: 8),
              HugeIcon(
                icon: AppIcons.chevronRight,
                color: kTextMid,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportImportPopup extends ConsumerWidget {
  final String? outletId;
  const _ExportImportPopup({required this.outletId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: HugeIcon(icon: AppIcons.moreHorizontal, color: kTextMid),
      tooltip: 'Export/Import',
      onSelected: (value) async {
        if (outletId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pilih outlet terlebih dahulu')),
          );
          return;
        }

        final service = ref.read(productExportServiceProvider);

        if (value == 'export') {
          await service.exportToCsv(outletId!);
        } else if (value == 'save') {
          await service.saveToCsv(outletId!);
        } else if (value == 'import') {
          final res = await service.importFromCsv(outletId!);
          if (res.imported > 0 || res.skipped > 0) {
            ref.invalidate(productsStreamProvider);
            ref.invalidate(categoriesStreamProvider);
            if (context.mounted) {
              String msg = 'Berhasil mengimpor ${res.imported} produk';
              if (res.skipped > 0) {
                msg += '. (${res.skipped} nama produk sudah ada, dilewati)';
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(msg),
                  duration: const Duration(seconds: 4),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: res.skipped > 0 ? kWarning : kSuccess,
                ),
              );
            }
          }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              HugeIcon(icon: AppIcons.share, color: kTextDark, size: 18),
              const SizedBox(width: 10),
              const Text('Bagikan CSV', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'save',
          child: Row(
            children: [
              HugeIcon(
                icon: AppIcons.download,
                color: kTextDark,
                size: 18,
              ),
              const SizedBox(width: 10),
              const Text('Simpan ke Perangkat', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'import',
          child: Row(
            children: [
              HugeIcon(icon: AppIcons.add, color: kTextDark, size: 18),
              const SizedBox(width: 10),
              const Text('Impor CSV', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}
