import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:sizer/sizer.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../app/app_routes.dart';
import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/beep_service.dart';
import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../../core/offline/product_cache.dart';
import '../../../core/offline/sale_outbox.dart';
import '../../../core/outlet_scope.dart';
import '../../../core/responsive.dart';
import '../../drafts/providers.dart';
import '../../drafts/ui/draft_list_sheet.dart';
import '../../outlet/data/outlet_service.dart';
import '../../printer/data/printer_service.dart';
import '../../products/domain/product.dart';
import '../../products/ui/barcode_scanner_page.dart';
import '../../shifts/data/shift_repository.dart';
import '../../shifts/ui/shift_management_dialog.dart';
import '../../tables/ui/table_management_page.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/sale.dart';
import '../providers.dart';
import '../scan_trigger.dart';
import 'widgets/cart_panel.dart';
import 'widgets/cart_sheet.dart';
import 'widgets/empty_states.dart';
import 'widgets/inline_barcode_scanner.dart';
import 'widgets/payment_sheet.dart';
import 'widgets/product_card.dart';

class KasirPage extends HookConsumerWidget {
  const KasirPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(selectedMainCategoryProvider);
    final scanMode = useState(false);
    final dynamicCats = ref.watch(categoryNamesProvider);
    // Chip kiri: 'Terlaris' + 'Favorit' + 'Semua' + kategori asli outlet.
    // Urutan terbaik di paling kiri supaya kasir cepat akses item populer.
    final categories = <String>['Terlaris', 'Favorit', 'Semua', ...dynamicCats];
    final isCheckingShift = useState(false);

    final totalItems = ref.watch(totalItemsProvider);
    final total = ref.watch(totalProvider);
    final favCount = ref.watch(favoritesCountProvider);
    final activeShift = ref.watch(activeShiftProvider).value;

    // ── Collapsible cart panel state (tablet only) ──
    final cartVisible = useState(true);
    final prevTotalItems = useRef(totalItems);

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
          final outletId = ref.read(activeOutletIdProvider);
          if (outletId == null) return [];

          // Selalu baca state terbaru di dalam closure agar perubahan tab
          // (Terlaris / Favorit / Semua / kategori lain) langsung
          // ter-refleksi setelah pagingController.refresh() dipicu.
          final currentCategory = ref.read(selectedMainCategoryProvider);
          final isFav = currentCategory == 'Favorit';
          final isBestSeller = currentCategory == 'Terlaris';
          final query = ref.read(productSearchQueryProvider);

          // Endpoint best-sellers tidak punya pagination — return semua
          // sekaligus di page pertama saja. Halaman berikutnya kosong
          // supaya PagingController menutup pagination dgn benar.
          if (isBestSeller) {
            if (pageKey > 1) return <Product>[];
            try {
              final all = await ref
                  .read(outletServiceProvider)
                  .getBestSellerProducts(outletId);
              if (query.isEmpty) return all;
              final q = query.toLowerCase();
              return all
                  .where((p) => p.name.toLowerCase().contains(q))
                  .toList();
            } catch (e) {
              // Offline: endpoint best-seller (server-computed) tak tersedia →
              // degradasi ke katalog cache supaya tab tidak crash. Urutan
              // "terlaris" tidak akurat offline, tapi produk tetap bisa dipilih.
              if (isOfflineError(e)) {
                final cached = await ref
                    .read(productCacheProvider)
                    .getAll(outletId);
                if (query.isEmpty) return cached;
                final q = query.toLowerCase();
                return cached
                    .where((p) => p.name.toLowerCase().contains(q))
                    .toList();
              }
              rethrow;
            }
          }

          final catId = isFav || currentCategory == 'Semua'
              ? null
              : ref.read(selectedCategoryIdProvider);
          try {
            final products = await ref
                .read(outletServiceProvider)
                .getProducts(
                  outletId,
                  categoryId: catId,
                  search: query,
                  isFavorite: isFav,
                  page: pageKey,
                  limit: 10,
                );
            return products;
          } catch (e) {
            // Offline: layani halaman pertama dari cache lokal dengan filter
            // kategori/cari/favorit dilakukan di sisi klien. Halaman > 1
            // dikosongkan supaya infinite-scroll berhenti rapi.
            if (isOfflineError(e)) {
              if (pageKey > 1) return <Product>[];
              final cached = await ref
                  .read(productCacheProvider)
                  .getAll(outletId);
              final q = query.toLowerCase();
              return cached.where((p) {
                if (catId != null && p.categoryId != catId) return false;
                if (isFav && !p.isFavorite) return false;
                if (q.isNotEmpty && !p.name.toLowerCase().contains(q)) {
                  return false;
                }
                return true;
              }).toList();
            }
            rethrow;
          }
        },
        getNextPageKey: (state) {
          final lastPage = state.pages?.lastOrNull;
          if (lastPage != null && lastPage.length < 10) {
            return null;
          }
          return (state.keys?.lastOrNull ?? 0) + 1;
        },
      ),
    );

    // Refresh pagination when filters change
    useEffect(
      () {
        pagingController.refresh();
        return null;
      },
      [
        ref.watch(selectedCategoryIdProvider),
        ref.watch(productSearchQueryProvider),
        ref.watch(favoritesUpdateTriggerProvider),
        category,
      ],
    );

    // Auto-show cart panel when a new product is added.
    if (totalItems > prevTotalItems.value && totalItems > 0) {
      cartVisible.value = true;
    }
    prevTotalItems.value = totalItems;

    Future<void> showPaymentSuccess(String saleId) async {
      // getById() lokal sebelumnya selalu null (stub), jadi dialog tidak
      // pernah muncul. Sekarang fetch dari backend lewat getDetail.
      final Sale sale;
      try {
        sale = await ref.read(transactionRepositoryProvider).getDetail(saleId);
      } catch (_) {
        // Kalau gagal fetch detail, biarkan saja — transaksi sudah tersimpan,
        // user bisa lihat di Riwayat.
        return;
      }
      if (!context.mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Gap(12),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: kSuccess.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: HugeIcon(
                    icon: AppIcons.checkCircle,
                    color: kSuccess,
                    size: 38,
                  ),
                ),
              ),
              const Gap(20),
              Text(
                'Pembayaran Berhasil',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w800,
                  color: kTextDark,
                ),
              ),
              const Gap(8),
              Text(
                'Transaksi #${sale.invoiceId} telah selesai.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: kTextMid),
              ),
              const Gap(24),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: kBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Pembayaran',
                          style: TextStyle(
                            fontSize: 13,
                            color: kTextMid,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          formatRupiah(sale.total),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: kTextDark,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(color: kDivider, height: 1),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Metode',
                          style: TextStyle(
                            fontSize: 13,
                            color: kTextMid,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          sale.paymentMethod,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: kTextDark,
                          ),
                        ),
                      ],
                    ),
                    if (sale.cashAmount > 0) ...[
                      const Gap(12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Dibayar',
                            style: TextStyle(
                              fontSize: 13,
                              color: kTextMid,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            formatRupiah(sale.cashAmount),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: kTextDark,
                            ),
                          ),
                        ],
                      ),
                      const Gap(8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Kembalian',
                            style: TextStyle(
                              fontSize: 13,
                              color: kTextMid,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            formatRupiah(sale.changeAmount),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: kSuccess,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          actions: [
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      ref.read(printerServiceProvider).printReceipt(sale);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        HugeIcon(
                          icon: AppIcons.printer,
                          color: Colors.white,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Cetak Struk',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Gap(8),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Tutup',
                      style: TextStyle(
                        color: kTextMid,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    Future<void> handleScannedCode(String code) async {
      if (code.isEmpty) return;

      // ── Handle Receipt/Invoice Scan ──
      if (code.startsWith('resi:')) {
        final invoiceId = code.substring(5);
        final outletId = ref.read(activeOutletIdProvider);
        if (outletId != null) {
          final sale = await ref
              .read(transactionRepositoryProvider)
              .findByInvoiceId(outletId, invoiceId);

          if (sale != null && context.mounted) {
            BeepService.instance.beep();
            HapticFeedback.mediumImpact();
            scanMode.value = false;
            context.push(
              AppRoutes.riwayatDetail.replaceAll(':id', sale.id.toString()),
            );
            return;
          }
        }
      }

      final productsAsync = ref.read(productsStreamProvider);
      final product = productsAsync.value?.firstWhereOrNull(
        (p) => p.barcode == code || p.sku == code,
      );

      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (product == null) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('${ref.t('scanner.not_found')}: $code'),
            backgroundColor: kDanger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        return;
      }
      final cartQty = ref.read(qtyProvider(product.remoteId));
      if (product.trackStock && cartQty >= product.stock) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('${product.name} — ${ref.t('product.out_of_stock')}'),
            backgroundColor: kDanger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        return;
      }
      ref.read(cartProvider.notifier).add(product);
      BeepService.instance.beep();
      HapticFeedback.heavyImpact();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1500),
          content: Row(
            children: [
              const HugeIcon(icon: AppIcons.checkCircle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${product.name} ${ref.t('scanner.added')}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: kSuccess,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    Future<void> openScanner() async {
      // Pada tablet: ganti panel produk menjadi scanner inline (tanpa
      // pindah halaman). Pengguna dapat memindai berturut-turut sementara
      // panel keranjang di kanan tetap terlihat dan ikut terupdate.
      if (context.isTablet) {
        scanMode.value = true;
        return;
      }
      // Pada mobile: tidak ada ruang untuk split view, pakai full-screen.
      final code = await Navigator.of(context, rootNavigator: true)
          .push<String>(
            MaterialPageRoute(
              builder: (_) => const BarcodeScannerPage(),
              fullscreenDialog: true,
            ),
          );
      if (code == null || code.isEmpty) return;
      handleScannedCode(code);
    }

    // ── Listen scan trigger from navbar ──
    final scanTrigger = ref.watch(scanTriggerProvider);
    final prevScanTrigger = useRef(scanTrigger);
    if (scanTrigger != prevScanTrigger.value) {
      prevScanTrigger.value = scanTrigger;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openScanner();
      });
    }

    // ── Cart / Payment ────────────────────────────────────────────────────────

    void openCart() {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        builder: (cartCtx) => CartSheet(
          onCheckout: () {
            Navigator.pop(cartCtx);
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useRootNavigator: true,
              backgroundColor: Colors.transparent,
              builder: (payCtx) => PaymentSheet(
                onPaid: (id) async {
                  Navigator.pop(payCtx);
                  await Future.delayed(const Duration(milliseconds: 300));
                  showPaymentSuccess(id);
                },
              ),
            );
          },
        ),
      );
    }

    void openPayment() {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        builder: (payCtx) => PaymentSheet(
          onPaid: (id) async {
            Navigator.pop(payCtx);
            await Future.delayed(const Duration(milliseconds: 300));
            showPaymentSuccess(id);
          },
        ),
      );
    }

    final isTablet = context.isTablet;
    final density = ref.watch(gridDensityProvider);
    final gridCols = (context.productGridColumns + density).clamp(1, 8);
    final horizontalPad = context.responsive<double>(
      compact: 16,
      medium: 16,
      expanded: 16,
      large: 16,
    );
    // Pada tablet, panel kasir di kanan memakan ruang sehingga kartu produk
    // lebih sempit → butuh aspect ratio lebih kecil agar kolom konten di
    // bawah gambar cukup tinggi dan tidak overflow.
    // Pada tablet, panel kasir di kanan memakan ruang sehingga kartu produk
    // lebih sempit → butuh aspect ratio lebih kecil agar kolom konten di
    // bawah gambar cukup tinggi dan tidak overflow.
    // Disesuaikan dengan density (makin banyak kolom, makin sempit).
    final baseAspect = context.responsive<double>(
      compact: 0.64,
      medium: 0.58,
      expanded: 0.60,
      large: 0.62,
    );
    // Adjust aspect slightly based on density to prevent overflow
    final gridAspect = baseAspect - (density * 0.03);

    final productArea = RefreshIndicator(
      color: kPrimary,
      onRefresh: () async {
        final outletId = ref.read(activeOutletIdProvider);
        // Refresh tab kategori (yang sebelumnya tetap memakai cache lama
        // sehingga kategori baru/edit/hapus tidak muncul tanpa restart).
        if (outletId != null) {
          ref.invalidate(outletCategoriesProvider(outletId));
        }
        // Refresh stream produk umum yang dipakai layar lain (mis. form
        // produk) supaya data di sana ikut konsisten.
        ref.invalidate(productsStreamProvider);
        // Refresh grid pagination — fetch ulang halaman pertama produk.
        pagingController.refresh();
        // Tahan indikator refresh sampai data kategori baru tiba supaya
        // user mendapat feedback visual yang jelas.
        if (outletId != null) {
          await ref.read(outletCategoriesProvider(outletId).future);
        }
      },
      child: PagingListener<int, Product>(
        controller: pagingController,
        builder: (context, state, fetchNextPage) => PagedGridView<int, Product>(
          state: state,
          fetchNextPage: fetchNextPage,
          scrollController: scrollController,
          // AlwaysScrollable supaya RefreshIndicator (tarik ke bawah) tetap
          // bisa dipakai walaupun grid kosong / hanya 1 baris.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            horizontalPad,
            16,
            horizontalPad,
            isTablet ? 24 : 100,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridCols,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
            childAspectRatio: gridAspect,
          ),
          builderDelegate: PagedChildBuilderDelegate<Product>(
            itemBuilder: (context, item, index) => ProductCard(product: item),
            firstPageErrorIndicatorBuilder: (context) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const HugeIcon(
                    icon: AppIcons.alertCircle,
                    color: kDanger,
                    size: 48,
                  ),
                  const Gap(16),
                  Text('Gagal memuat produk'),
                  const Gap(8),
                  ElevatedButton(
                    onPressed: () => pagingController.refresh(),
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            ),
            noItemsFoundIndicatorBuilder: (context) {
              // Bungkus tunggal dengan SizedBox (bukan ListView) supaya
              // tidak menumpuk viewport di dalam sliver PagedGridView —
              // viewport bertingkat memicu "RenderViewport does not
              // support returning intrinsic dimensions" + null-check error.
              final emptyHeight = MediaQuery.of(context).size.height * 0.6;
              if (category == 'Favorit') {
                return SizedBox(
                  height: emptyHeight,
                  child: const EmptyFavorites(),
                );
              }
              final query = ref.read(productSearchQueryProvider);
              final isSearching = query.trim().isNotEmpty;
              return SizedBox(
                height: emptyHeight,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: kBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: HugeIcon(
                            icon: AppIcons.inventory,
                            size: 32,
                            color: kTextMid,
                          ),
                        ),
                        const Gap(16),
                        Text(
                          isSearching
                              ? 'Produk tidak ditemukan'
                              : 'Belum ada produk',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: kTextDark,
                          ),
                        ),
                        const Gap(4),
                        Text(
                          isSearching
                              ? 'Coba kata kunci lain'
                              : 'Tambahkan produk dulu untuk mulai berjualan',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: kTextMid),
                        ),
                        if (!isSearching) ...[
                          const Gap(20),
                          ElevatedButton.icon(
                            onPressed: () =>
                                context.pushNamed(AppRoutes.productsName),
                            icon: const HugeIcon(
                              icon: AppIcons.inventory,
                              color: Colors.white,
                              size: 18,
                            ),
                            label: const Text('Kelola Produk'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
            firstPageProgressIndicatorBuilder: (context) {
              // Skeleton grid yang meniru layout produk asli supaya transisi
              // loading → data tidak menggeser ukuran kartu di mata user.
              // Pakai dummy Product dengan harga & nama generik — Skeletonizer
              // akan mengubah teks/box menjadi shimmer placeholder.
              final dummy = Product(name: 'Nama Produk', price: 10000);
              // WAJIB dibungkus SizedBox bertinggi tetap: infinite_scroll_pagination
              // menaruh indicator ini di dalam SliverFillRemaining yang MENGUKUR
              // tinggi INTRINSIK anaknya. Kalau langsung GridView(shrinkWrap:true)
              // (sebuah viewport lazy), pengukuran intrinsik masuk ke viewport →
              // crash "RenderShrinkWrappingViewport does not support returning
              // intrinsic dimensions". SizedBox menghentikan pengukuran intrinsik
              // (pola sama dgn noItemsFoundIndicatorBuilder).
              return SizedBox(
                height: MediaQuery.of(context).size.height,
                child: Skeletonizer(
                  enabled: true,
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      horizontalPad,
                      16,
                      horizontalPad,
                      isTablet ? 24 : 100,
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridCols,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: gridAspect,
                    ),
                    itemCount: gridCols * 2,
                    itemBuilder: (_, _) => ProductCard(product: dummy),
                  ),
                ),
              );
            },
            newPageProgressIndicatorBuilder: (context) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Skeletonizer(
                enabled: true,
                child: SizedBox(
                  height: 24,
                  child: Center(
                    child: Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: kBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (activeShift == null) {
      return Scaffold(
        backgroundColor: kBg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: HugeIcon(
                    icon: AppIcons.lock,
                    color: kPrimary,
                    size: 64,
                  ),
                ),
              ),
              const Gap(24),
              Text(
                'Kasir Masih Tertutup',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: kTextDark,
                ),
              ),
              const Gap(8),
              Text(
                'Silakan buka kasir terlebih dahulu\nuntuk mulai memproses transaksi.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextMid, fontSize: 16),
              ),
              const Gap(32),
              ValueListenableBuilder<bool>(
                valueListenable: isCheckingShift,
                builder: (context, loading, _) {
                  return SizedBox(
                    width: 240,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: loading
                          ? null
                          : () async {
                              isCheckingShift.value = true;
                              try {
                                final notifier = ref.read(
                                  activeShiftProvider.notifier,
                                );
                                final shift = await notifier.checkAndRefresh();

                                if (shift == null && context.mounted) {
                                  showDialog(
                                    context: context,
                                    builder: (_) =>
                                        const ShiftManagementDialog(),
                                  );
                                }
                              } finally {
                                isCheckingShift.value = false;
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                HugeIcon(
                                  icon: AppIcons.login,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Buka Kasir Sekarang',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    if (isTablet) {
      final cartPanelWidth = context.responsive<double>(
        compact: 320 + 40,
        medium: 340 + 40,
        expanded: 360 + 40,
        large: 400 + 40,
      );

      return Scaffold(
        backgroundColor: kBg,
        floatingActionButton: showBackToTop.value
            ? FloatingActionButton.small(
                heroTag: 'kasir_scroll_top_tablet',
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
        body: Stack(
          children: [
            // ── Product area (full width) ──
            Row(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: scanMode.value
                        ? InlineBarcodeScanner(
                            key: const ValueKey('scan'),
                            onDetected: handleScannedCode,
                            onClose: () => scanMode.value = false,
                          )
                        : Column(
                            key: const ValueKey('products'),
                            children: [
                              _Header(
                                category: category,
                                favCount: favCount,
                                categories: categories,
                              ),
                              Expanded(child: productArea),
                            ],
                          ),
                  ),
                ),
                // Spacer agar produk tidak tertutup panel cart saat terbuka
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  width: cartVisible.value ? cartPanelWidth : 0,
                ),
              ],
            ),

            // ── Cart toggle button ──
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              right: cartVisible.value ? cartPanelWidth : 0,
              top: MediaQuery.of(context).padding.top + 12,
              child: GestureDetector(
                onTap: () => cartVisible.value = !cartVisible.value,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: totalItems > 0 ? kPrimary : kCard,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(14),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(-2, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HugeIcon(
                        icon: cartVisible.value
                            ? AppIcons.chevronRight
                            : AppIcons.receiptLong,
                        color: totalItems > 0 ? Colors.white : kTextDark,
                        size: 18,
                      ),
                      if (totalItems > 0 && !cartVisible.value) ...[
                        const Gap(6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$totalItems',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // ── Sliding cart panel ──
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              right: cartVisible.value ? 0 : -cartPanelWidth,
              top: 0,
              bottom: 0,
              width: cartPanelWidth,
              child: Material(
                elevation: 8,
                shadowColor: Colors.black.withValues(alpha: 0.15),
                child: CartPanel(onCheckout: openPayment),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: kBg,
      body: Column(
        children: [
          _Header(
            category: category,
            favCount: favCount,
            categories: categories,
          ),
          Expanded(child: productArea),
        ],
      ),
      floatingActionButton: (totalItems > 0 || showBackToTop.value)
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (showBackToTop.value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FloatingActionButton.small(
                      heroTag: 'kasir_scroll_top',
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
                if (totalItems > 0)
                  GestureDetector(
                    onTap: openCart,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: kPrimary,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: kPrimary.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '$totalItems',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            ref.t('kasir.view_order'),
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.sp,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            formatRupiah(total),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }
}

class _Header extends HookConsumerWidget {
  final String category;
  final int favCount;
  final List<String> categories;

  const _Header({
    required this.category,
    required this.favCount,
    required this.categories,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: kPrimary,
        image: DecorationImage(
          image: AssetImage('assets/images/bg.jpg'),
          fit: BoxFit.cover,
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 60,
                    height: 60,

                    decoration: BoxDecoration(
                      image: const DecorationImage(
                        alignment: Alignment.topRight,
                        image: AssetImage('assets/images/logo.png'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NARA',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        "Take control of your business, right in your hand.",
                        style: const TextStyle(
                          fontSize: 8,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Builder(
                    builder: (_) {
                      final label = ref.watch(activeOutletLabelProvider);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const HugeIcon(
                              icon: AppIcons.storefront,
                              color: Colors.white,
                              size: 13,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              label.isNotEmpty ? label : 'Outlet',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Gap(16),
                  Row(
                    children: [
                      // Scan Button
                      GestureDetector(
                        onTap: () {
                          ref.read(scanTriggerProvider.notifier).trigger();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Row(
                            children: [
                              HugeIcon(
                                icon: AppIcons.scan,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Scan',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Gap(8),
                      GestureDetector(
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const _CustomOrderSheet(),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Row(
                            children: [
                              HugeIcon(
                                icon: AppIcons.add,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Custom Order',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Gap(8),
                      // Table Management Button
                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => Dialog(
                              insetPadding: const EdgeInsets.all(16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: context.isTablet ? 1100 : 500,
                                  maxHeight:
                                      MediaQuery.of(context).size.height * 0.85,
                                ),
                                child: const TableManagementPage(
                                  isReadOnly: true,
                                ),
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Row(
                            children: [
                              HugeIcon(
                                icon: HugeIcons.strokeRoundedTable02,
                                color: Colors.white,
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Meja',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Gap(8),
                      // Draft Orders Button
                      GestureDetector(
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const DraftListSheet(),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              const HugeIcon(
                                icon: AppIcons.task,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'Draft',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Consumer(
                                builder: (_, ref, _) {
                                  final count = ref.watch(draftsCountProvider);
                                  if (count == 0) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '$count',
                                        style: const TextStyle(
                                          color: kPrimary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Custom Order Button
                ],
              ),
            ),
            Gap(16),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: kBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        onChanged: (v) =>
                            ref
                                    .read(productSearchQueryProvider.notifier)
                                    .state =
                                v,
                        style: TextStyle(fontSize: 13, color: kTextDark),
                        decoration: InputDecoration(
                          hintText: ref.t('kasir.search'),
                          hintStyle: TextStyle(color: kTextMid, fontSize: 13),
                          prefixIcon: Padding(
                            padding: EdgeInsets.all(10),
                            child: HugeIcon(
                              icon: AppIcons.search,
                              color: kTextMid,
                              size: 18,
                            ),
                          ),
                          suffixIcon:
                              ref.watch(productSearchQueryProvider).isNotEmpty
                              ? GestureDetector(
                                  onTap: () {
                                    ref
                                            .read(
                                              productSearchQueryProvider
                                                  .notifier,
                                            )
                                            .state =
                                        "";
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: HugeIcon(
                                      icon: HugeIcons.strokeRoundedCancel01,
                                      color: kTextMid,
                                      size: 18,
                                    ),
                                  ),
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
                  Gap(16),
                  _GridDensityControl(),
                ],
              ),
            ),
            Gap(16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              child: SizedBox(
                height: 34,
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final c = categories[i];
                    final active = c == category;
                    final isFavChip = c == 'Favorit';
                    final isBestSellerChip = c == 'Terlaris';
                    // Warna aktif khusus: fav=pink, terlaris=oranye, else=putih.
                    final activeColor = isFavChip
                        ? kFav
                        : isBestSellerChip
                        ? const Color(0xFFFF8A1F)
                        : Colors.white;
                    return GestureDetector(
                      onTap: () {
                        ref.read(selectedMainCategoryProvider.notifier).state =
                            c;
                        if (c == 'Semua' || c == 'Favorit' || c == 'Terlaris') {
                          ref.read(selectedCategoryIdProvider.notifier).state =
                              null;
                        } else {
                          final cats = ref.read(categoriesStreamProvider).value;
                          final target = cats?.firstWhereOrNull(
                            (cat) => cat.name == c,
                          );
                          ref.read(selectedCategoryIdProvider.notifier).state =
                              target?.remoteId;
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: active ? activeColor : Colors.transparent,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: active ? activeColor : Colors.white24,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (isFavChip)
                              HugeIcon(
                                icon: AppIcons.favorite,
                                size: 12,
                                color: Colors.white,
                              )
                            else if (isBestSellerChip) ...[
                              HugeIcon(
                                icon: AppIcons.fire,
                                size: 12,
                                color: active ? Colors.white : Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                c,
                                style: TextStyle(
                                  color: active ? Colors.white : Colors.white,
                                  fontSize: 12,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ] else
                              Text(
                                c,
                                style: TextStyle(
                                  color: active ? kPrimary : Colors.white,
                                  fontSize: 12,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Gap(16),
          ],
        ),
      ),
    );
  }
}

class _GridDensityControl extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final density = ref.watch(gridDensityProvider);
    final notifier = ref.read(gridDensityProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DensityBtn(
            icon: Icons.grid_view_rounded,
            active: density == -1,
            onTap: () => notifier.set(-1),
            tooltip: 'Besar',
          ),
          _DensityBtn(
            icon: Icons.grid_on_rounded,
            active: density == 0,
            onTap: () => notifier.set(0),
            tooltip: 'Normal',
          ),
          _DensityBtn(
            icon: Icons.apps_rounded,
            active: density == 1,
            onTap: () => notifier.set(1),
            tooltip: 'Kecil',
          ),
        ],
      ),
    );
  }
}

class _DensityBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;

  const _DensityBtn({
    required this.icon,
    required this.active,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 32,
        height: 28,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: active ? kPrimary : Colors.white),
      ),
    );
  }
}

class _CustomOrderSheet extends HookConsumerWidget {
  const _CustomOrderSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameCtrl = useTextEditingController();
    final priceCtrl = useTextEditingController();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const HugeIcon(
                    icon: AppIcons.add,
                    color: kAccent,
                    size: 20,
                  ),
                ),
                const Gap(12),
                Text(
                  'Pesanan Custom',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: kTextDark,
                  ),
                ),
              ],
            ),
            const Gap(20),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Nama Produk / Pesanan',
                hintText: 'Misal: Nasi Goreng Spesial',
                filled: true,
                fillColor: kBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const Gap(16),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Harga Satuan',
                hintText: 'Rp 0',
                filled: true,
                fillColor: kBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const Gap(24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final price = parseRupiahInput(priceCtrl.text).toDouble();
                  if (name.isNotEmpty && price > 0) {
                    ref
                        .read(cartProvider.notifier)
                        .add(Product.custom(name: name, price: price));
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Tambah ke Keranjang',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
