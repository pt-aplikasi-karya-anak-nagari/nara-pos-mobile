import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';
import '../../../../core/i18n.dart';
import 'package:sizer/sizer.dart';
import '../../../../app/theme.dart';
import '../../../../core/app_icons.dart';
import '../../../../core/format.dart';
import '../../../../core/product_image.dart';
import '../../../products/domain/product.dart';
import '../../../products/domain/modifier_group.dart';
import '../../../products/data/modifier_repository.dart';
import '../../domain/cart_item.dart';
import '../../providers.dart';
import 'size_picker_sheet.dart';
import 'modifier_sheet.dart';
import 'qty_button.dart';
import '../../../../core/outlet_scope.dart';
import '../../../outlet/data/outlet_service.dart';

// Ambang "menipis" auto-86: bila sisa porsi (dihitung backend dari stok bahan)
// berada di rentang (0, threshold] tampilkan badge "sisa N".
const int kAuto86LowThreshold = 5;

class ProductCard extends HookConsumerWidget {
  final Product product;
  const ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qty = ref.watch(qtyProvider(product.remoteId));
    final isFavLocal = useState(product.isFavorite);
    final isFav = isFavLocal.value;
    final mainCategory = ref.watch(selectedMainCategoryProvider);
    final density = ref.watch(gridDensityProvider);
    final isCompact = density == 1; // High density (small cards)
    final cart = ref.read(cartProvider.notifier);
    final inCart = qty > 0;
    // Produk tanpa "kelola stok" tidak menggunakan sistem stok: tidak pernah
    // dianggap habis dan tidak punya batas kuantitas.
    final tracksStock = product.trackStock;
    final stockOut = tracksStock && product.stock <= 0;
    // Auto-86: bahan resep habis menurut backend. Fail-open — isInStock default
    // true saat field absen (backend lama / produk tanpa resep) → tak pernah
    // dianggap habis di sini.
    final ingredientOut = !product.isInStock;
    // "Habis" bila kehabisan stok fisik ATAU kehabisan bahan resep. Layer
    // auto-86 di ATAS logika stok fisik yang lama (bukan menggantikan).
    final outOfStock = stockOut || ingredientOut;
    // availablePortions: null = tak dibatasi (produk tanpa resep). Badge
    // "sisa N" hanya saat masih ada porsi tapi menipis (0 < n <= threshold)
    // dan produk belum habis.
    final portions = product.availablePortions;
    final lowPortions = !outOfStock &&
        portions != null &&
        portions > 0 &&
        portions <= kAuto86LowThreshold;
    final canAddMore = !outOfStock && (!tracksStock || qty < product.stock);
    final hasVariants = product.variants.isNotEmpty;

    // Auto-86: saat add diblokir karena bahan habis, beri feedback jelas ke
    // kasir (bukan sekadar diam) sesuai spesifikasi UX.
    void showBahanHabis() {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1500),
          content: Text('${product.name} — ${ref.t('product.ingredient_out')}'),
          backgroundColor: kDanger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    final titleSize = isCompact ? 10.sp : 12.sp;
    final priceSize = isCompact ? 10.sp : 12.sp;

    // C4: ambil grup modifier untuk produk ini; bila ada, tampilkan sheet
    // pemilihan. Return: daftar modifier terpilih (bisa kosong), atau null bila
    // kasir membatalkan sheet. Offline/gagal/tanpa modifier → kosong (add biasa).
    Future<List<CartModifier>?> pickModifiers(ProductVariant? variant) async {
      final outletId = ref.read(activeOutletIdProvider);
      final pid = product.remoteId;
      if (outletId == null || outletId.isEmpty || pid == null) {
        return const <CartModifier>[];
      }
      List<ModifierGroup> groups;
      try {
        groups = await ref.read(
          productModifierGroupsProvider((outletId: outletId, productId: pid))
              .future,
        );
      } catch (_) {
        return const <CartModifier>[];
      }
      if (groups.isEmpty || !context.mounted) return const <CartModifier>[];
      final basePrice = variant?.price ?? product.price;
      final title = variant == null
          ? product.name
          : '${product.name} (${variant.name})';
      return showModalBottomSheet<List<CartModifier>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ModifierSheet(
          productName: title,
          basePrice: basePrice,
          groups: groups,
        ),
      );
    }

    Future<void> addWithVariant() async {
      final picked = await showModalBottomSheet<ProductVariant>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SizePickerSheet(product: product),
      );
      if (picked == null) return;
      final mods = await pickModifiers(picked);
      if (mods == null) return; // sheet modifier dibatalkan
      cart.add(product, variant: picked, modifiers: mods);
    }

    Future<void> addDirect() async {
      if (hasVariants) {
        await addWithVariant();
      } else {
        final mods = await pickModifiers(null);
        if (mods == null) return;
        cart.add(product, modifiers: mods);
      }
    }

    return GestureDetector(
      // Habis-bahan (auto-86): tap tampilkan snackbar "Bahan habis" alih-alih
      // diam. Habis stok fisik biasa tetap no-op seperti sebelumnya.
      onTap: canAddMore
          ? addDirect
          : (ingredientOut ? showBahanHabis : null),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: inCart ? kPrimary : Colors.transparent,
            width: 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ColorFiltered(
                      colorFilter: outOfStock
                          ? const ColorFilter.matrix(<double>[
                              0.2126,
                              0.7152,
                              0.0722,
                              0,
                              0,
                              0.2126,
                              0.7152,
                              0.0722,
                              0,
                              0,
                              0.2126,
                              0.7152,
                              0.0722,
                              0,
                              0,
                              0,
                              0,
                              0,
                              1,
                              0,
                            ])
                          : const ColorFilter.mode(
                              Colors.transparent,
                              BlendMode.dst,
                            ),
                      child: Stack(
                        children: [
                          ProductImage(
                            name: product.name,
                            imageUrl: product.imageUrl,
                            fill: true,
                            radius: 0,
                          ),
                          // Badge "Terjual: N" — opt-in lewat outlet.showSoldCount.
                          // Hanya muncul kalau produk pernah laku (>0) supaya
                          // produk baru tidak terlihat "0 terjual".
                          if (product.sold > 0 &&
                              (ref.watch(activeOutletProvider)?.showSoldCount ??
                                  false))
                            Align(
                              alignment: Alignment.bottomLeft,
                              child: Container(
                                padding: const EdgeInsets.only(
                                  left: 8,
                                  right: 12,
                                  bottom: 2,
                                  top: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.5),
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(99),
                                  ),
                                ),
                                child: Flexible(
                                  child: Text(
                                    '🔥 ${ref.t('product.sold')} ${product.sold}',
                                    style: TextStyle(
                                      fontSize: isCompact ? 8 : 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),

                          if (outOfStock)
                            Positioned(
                              left: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: kDanger,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  ref.t('product.out_of_stock'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            )
                          // Auto-86 menipis: sisa porsi (dari stok bahan) sudah
                          // sedikit tapi belum habis → badge amber "sisa N".
                          else if (lowPortions)
                            Positioned(
                              left: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: kWarning,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${ref.t('product.portions_left')} $portions',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            )
                          else if (tracksStock)
                            Positioned(
                              left: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${ref.t('product.stock')}: ${product.stock}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          if (product.hasDiscount)
                            Positioned(
                              left: 8,
                              // Geser turun bila ada badge Habis / "sisa N" di
                              // slot kiri-atas supaya tidak bertumpuk.
                              top: (outOfStock || lowPortions) ? 36 : 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: kAccent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'DISKON ${product.discountValue.toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 6,
                                        fontWeight: FontWeight.w800,
                                        height: 1,
                                      ),
                                    ),
                                    const Gap(2),
                                    Text(
                                      formatRupiah(product.price),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 7,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.lineThrough,
                                        height: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () async {
                                // Optimistic UI: toggle state instantly and animate
                                isFavLocal.value = !isFavLocal.value;
                                product.isFavorite = isFavLocal.value;

                                // Fire and forget API call
                                await ref
                                    .read(outletServiceProvider)
                                    .toggleFavorite(product.remoteId ?? '');

                                // Invalidate provider favorit agar daftar Favorit ter-refresh.
                                final outletId = ref.read(
                                  activeOutletIdProvider,
                                );
                                if (outletId != null) {
                                  ref.invalidate(
                                    outletFavoriteProductsProvider(outletId),
                                  );
                                }

                                ref
                                    .read(
                                      favoritesUpdateTriggerProvider.notifier,
                                    )
                                    .update((s) => s + 1);
                              },
                              child: TweenAnimationBuilder<double>(
                                key: ValueKey(
                                  isFav,
                                ), // Restart animation on change
                                duration: const Duration(milliseconds: 150),
                                curve: Curves.easeOutBack,
                                tween: Tween(begin: 0.8, end: 1.0),
                                builder: (context, scale, child) =>
                                    Transform.scale(scale: scale, child: child),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: isFav ? Colors.red : Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.1,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: isFav
                                        ? const Icon(
                                            Icons.favorite,
                                            color: Colors.white,
                                            size: 10,
                                          )
                                        : HugeIcon(
                                            icon: AppIcons.favorite,
                                            color: Colors.red.withValues(
                                              alpha: 0.7,
                                            ),
                                            size: 10,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isCompact ? 8 : 10,
                  isCompact ? 6 : 8,
                  isCompact ? 8 : 10,
                  isCompact ? 6 : 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Text(
                      product.name,
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w600,
                        color: kTextDark,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((mainCategory == 'Semua' ||
                            mainCategory == 'Favorit') &&
                        product.categoryName != null) ...[
                      const Gap(1),
                      Text(
                        product.categoryName!.toUpperCase(),
                        style: TextStyle(
                          fontSize: isCompact ? 7 : 9,
                          color: kPrimary.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const Gap(2),
                    Text(
                      formatRupiah(product.discountedPrice),
                      style: TextStyle(
                        fontSize: priceSize,
                        fontWeight: FontWeight.w700,
                        color: kPrimary,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Spacer mengambil sisa ruang antara harga & tombol; gap
                    // eksplisit sebelumnya redundan & menyebabkan overflow di
                    // card yang sempit (mis. setelah side rail mengurangi
                    // lebar layar).
                    const Spacer(),
                    if (!inCart || hasVariants)
                      SizedBox(
                        width: double.infinity,
                        height: 30,
                        child: ElevatedButton(
                          onPressed: canAddMore ? addDirect : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            disabledBackgroundColor: kTextMid.withValues(
                              alpha: 0.3,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: EdgeInsets.zero,
                            elevation: 0,
                          ),
                          child: HugeIcon(
                            icon: AppIcons.add,
                            color: canAddMore
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.7),
                            size: 18,
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 30,
                        child: Row(
                          children: [
                            QtyButton(
                              icon: AppIcons.remove,
                              // C4: kurangi baris terakhir produk ini (kontrol
                              // kasar di grid; presisi di panel keranjang).
                              onTap: () => cart.decrementLastOf(product),
                              primary: false,
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  '$qty',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: isCompact ? 10.sp : 12.sp,
                                    color: kPrimary,
                                  ),
                                ),
                              ),
                            ),
                            QtyButton(
                              icon: AppIcons.add,
                              // C4: lewat addDirect → produk bermodifier membuka
                              // sheet (bukan menambah baris polos hantu).
                              onTap: canAddMore ? () => addDirect() : null,
                              primary: true,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
