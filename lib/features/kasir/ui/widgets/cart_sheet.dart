import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';
import '../../../settings/data/tax_settings.dart';
import '../../../../app/theme.dart';
import '../../../../core/app_icons.dart';
import '../../../../core/format.dart';
import '../../../../core/product_image.dart';
import '../../domain/cart_item.dart';
import '../../../drafts/providers.dart';
import '../../providers.dart';
import 'empty_states.dart';
import 'customer_selector.dart';
import 'line_discount_sheet.dart';
import 'menu_orders_tab.dart';

class CartSheet extends HookConsumerWidget {
  final VoidCallback onCheckout;
  const CartSheet({super.key, required this.onCheckout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final subtotal = ref.watch(subtotalProvider);
    final tax = ref.watch(taxProvider);
    final total = ref.watch(totalProvider);
    final taxSettings = ref.watch(taxSettingsProvider);
    final notifier = ref.read(cartProvider.notifier);

    // Auto-hide breakdown (subtotal/diskon/PPN) saat scroll ke bawah,
    // muncul kembali saat scroll ke atas atau di posisi paling atas.
    //
    // Pakai delta posisi (bukan userScrollDirection) supaya deteksi tetap
    // reliable saat scroll dengan momentum/fling — userScrollDirection
    // sering "stuck" di reverse setelah finger lepas, bikin breakdown
    // tidak balik muncul ("gak bisa rewind").
    final scrollController = useScrollController();
    final showBreakdown = useState(true);
    final lastOffset = useRef(0.0);
    useEffect(() {
      void listener() {
        if (!scrollController.hasClients) return;
        final pixels = scrollController.position.pixels;

        // Selalu tampil saat berada dekat ujung atas listing.
        if (pixels <= 32) {
          if (!showBreakdown.value) showBreakdown.value = true;
          lastOffset.value = pixels;
          return;
        }

        final delta = pixels - lastOffset.value;
        // Threshold kecil (8px) supaya tidak flicker karena over-scroll/jitter.
        if (delta > 8 && showBreakdown.value) {
          showBreakdown.value = false;
        } else if (delta < -8 && !showBreakdown.value) {
          showBreakdown.value = true;
        }
        lastOffset.value = pixels;
      }

      scrollController.addListener(listener);
      return () => scrollController.removeListener(listener);
    }, [scrollController]);

    final mq = MediaQuery.of(context);
    // Full-height modal. Status bar di-handle SafeArea (top), bottom inset
    // di-handle padding footer. Height dikurangi viewInsets.bottom supaya
    // saat keyboard muncul (mis. ketik catatan), footer ikut naik dan tidak
    // ter-clip di balik keyboard.
    final sheetHeight = mq.size.height - mq.viewInsets.bottom;
    return DefaultTabController(
      length: 2,
      child: Container(
        height: sheetHeight,
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: true,
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: kDivider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const Gap(12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Pesanan',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: kTextDark,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Tutup',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: Icon(
                            Icons.close_rounded,
                            color: kTextMid,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const Gap(8),
                  ],
                ),
              ),
              // ── TabBar ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: kBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    indicator: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    labelColor: kPrimary,
                    unselectedLabelColor: kTextMid,
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    padding: const EdgeInsets.all(4),
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'Langsung'),
                      Tab(text: 'Meja'),
                    ],
                  ),
                ),
              ),
              const Gap(12),
              Divider(color: kDivider, height: 1),
              Expanded(
                child: TabBarView(
                  children: [
                    // Tab 1: Pesanan Langsung
                    Column(
                      children: [
                        if (cart.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      _CartStatChip(
                                        icon: AppIcons.inventory,
                                        label: '${cart.length} Produk',
                                      ),
                                      _CartStatChip(
                                        icon: AppIcons.receiptLong,
                                        label:
                                            '${ref.watch(totalItemsProvider)} Item',
                                      ),
                                    ],
                                  ),
                                ),
                                const Gap(8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () async {
                                        final ok = await saveCurrentCartAsDraft(
                                          ref,
                                        );
                                        if (!context.mounted) return;
                                        Navigator.of(context).pop();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              ok
                                                  ? 'Pesanan disimpan ke draft'
                                                  : 'Gagal menyimpan draft',
                                            ),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: kPrimary.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Row(
                                          children: [
                                            HugeIcon(
                                              icon: AppIcons.task,
                                              color: kPrimary,
                                              size: 14,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'Simpan Draft',
                                              style: TextStyle(
                                                color: kPrimary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const Gap(8),
                                    GestureDetector(
                                      onTap: notifier.clear,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF0EE),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Row(
                                          children: [
                                            HugeIcon(
                                              icon: AppIcons.delete,
                                              color: kDanger,
                                              size: 14,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'Hapus Semua',
                                              style: TextStyle(
                                                color: kDanger,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const CustomerSelector(),
                        ),
                        const Gap(12),
                        Divider(color: kDivider, height: 1),
                        Expanded(
                          child: cart.isEmpty
                              ? const EmptyCart()
                              : ListView.separated(
                                  controller: scrollController,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  itemCount: cart.length,
                                  separatorBuilder: (_, _) => Divider(
                                    color: kDivider,
                                    height: 20,
                                  ),
                                  itemBuilder: (_, i) =>
                                      _CartRow(index: i, item: cart[i]),
                                ),
                        ),
                        if (cart.isNotEmpty)
                          _CartFooter(
                            subtotal: subtotal,
                            tax: tax,
                            total: total,
                            showBreakdown: showBreakdown.value,
                            taxEnabled: taxSettings.enabled,
                            taxPercent: taxSettings.percent,
                            discountTotal: ref.watch(discountTotalProvider),
                            serviceCharge: ref.watch(serviceChargeProvider),
                            serviceChargeName: taxSettings.serviceChargeName,
                            serviceChargePercent:
                                taxSettings.serviceChargePercent,
                            onCheckout: onCheckout,
                          ),
                      ],
                    ),
                    // Tab 2: Pesanan dari QR menu (source=menu_qr, unpaid).
                    const MenuOrdersTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineDiscountButton extends StatelessWidget {
  final bool hasDiscount;
  final VoidCallback onTap;
  const _LineDiscountButton({required this.hasDiscount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: hasDiscount
              ? kAccent.withValues(alpha: 0.12)
              : kPrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: hasDiscount ? kAccent : kPrimary,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasDiscount ? Icons.edit_rounded : Icons.add_rounded,
              size: 11,
              color: hasDiscount ? kAccent : kPrimary,
            ),
            const SizedBox(width: 2),
            Text(
              hasDiscount ? 'Edit Diskon' : 'Beri Diskon',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: hasDiscount ? kAccent : kPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartStatChip extends StatelessWidget {
  final IconAsset icon;
  final String label;
  const _CartStatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kDivider, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(icon: icon, color: kTextMid, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: kTextDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartFooter extends StatelessWidget {
  final double subtotal;
  final double tax;
  final double total;
  final bool showBreakdown;
  final bool taxEnabled;
  final double taxPercent;
  final double discountTotal;
  final double serviceCharge;
  final String serviceChargeName;
  final double serviceChargePercent;
  final VoidCallback onCheckout;

  const _CartFooter({
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.showBreakdown,
    required this.taxEnabled,
    required this.taxPercent,
    required this.discountTotal,
    required this.serviceCharge,
    required this.serviceChargeName,
    required this.serviceChargePercent,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final breakdown = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BreakdownRow(label: 'Subtotal', value: formatRupiah(subtotal)),
        if (discountTotal > 0) ...[
          const Gap(4),
          _BreakdownRow(
            label: 'Diskon',
            value: '- ${formatRupiah(discountTotal)}',
            color: kSuccess,
          ),
        ],
        if (serviceCharge > 0) ...[
          const Gap(4),
          _BreakdownRow(
            label: '$serviceChargeName (${_fmtPct(serviceChargePercent)}%)',
            value: formatRupiah(serviceCharge),
            color: kTextMid,
          ),
        ],
        if (taxEnabled) ...[
          const Gap(4),
          _BreakdownRow(
            label: 'PPN (${_fmtPct(taxPercent)}%)',
            value: formatRupiah(tax),
            color: kTextMid,
          ),
        ],
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(color: kDivider, height: 1),
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: kCard,
        border: Border(top: BorderSide(color: kDivider)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Breakdown auto-hide saat scroll: animasi tinggi (collapse) +
          // opacity (fade) supaya transisi halus.
          ClipRect(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              heightFactor: showBreakdown ? 1 : 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                opacity: showBreakdown ? 1 : 0,
                child: breakdown,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: kTextDark,
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: Text(
                  formatRupiah(total),
                  key: ValueKey(total),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: kPrimary,
                  ),
                ),
              ),
            ],
          ),
          const Gap(12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const HugeIcon(
                    icon: AppIcons.payment,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Bayar ${formatRupiah(total)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartRow extends ConsumerWidget {
  final int index;
  final CartItem item;
  const _CartRow({required this.index, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);
    final totalQtyForProduct = ref.watch(qtyProvider(item.product.remoteId));
    final canAddMore =
        !item.product.trackStock || totalQtyForProduct < item.product.stock;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ProductImage(
              name: item.product.name,
              imageUrl: item.product.imageUrl,
              size: 46,
              radius: 12,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.product.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: kTextDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.variantName.isNotEmpty) ...[
                    const Gap(2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.variantName,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: kPrimary,
                        ),
                      ),
                    ),
                  ],
                  const Gap(2),
                  Row(
                    children: [
                      if (item.lineDiscount > 0) ...[
                        Text(
                          formatRupiah(item.basePrice),
                          style: TextStyle(
                            fontSize: 10,
                            color: kTextLight,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        formatRupiah(item.effectivePrice),
                        style: TextStyle(fontSize: 12, color: kTextMid),
                      ),
                    ],
                  ),
                  Builder(
                    builder: (rowCtx) {
                      // Diskon otomatis (produk untuk Regular, atau diskon
                      // bawaan varian) menutup tombol manual supaya tidak
                      // dobel diskon di satu baris.
                      final canApplyManual = !item.hasAutoDiscount;
                      if (item.lineDiscount <= 0 && !canApplyManual) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (item.lineDiscount > 0) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: kAccent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'DISKON ${item.discountLabel}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Text(
                                'Hemat ${formatRupiah(item.lineDiscount)}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: kAccent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            if (canApplyManual)
                              _LineDiscountButton(
                                hasDiscount: item.hasManualDiscount,
                                onTap: () => showModalBottomSheet(
                                  context: rowCtx,
                                  isScrollControlled: true,
                                  useRootNavigator: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => LineDiscountSheet(
                                    index: index,
                                    item: item,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            _MiniQtyBtn(
              icon: AppIcons.remove,
              // C4: turunkan baris ini (by index) — jangan salah target baris
              // modifier.
              onTap: () => notifier.decrementAt(index),
              primary: false,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                '${item.qty}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: kTextDark,
                ),
              ),
            ),
            _MiniQtyBtn(
              icon: AppIcons.add,
              // C4: naikkan baris ini (by index) — pertahankan modifier baris.
              onTap: canAddMore ? () => notifier.incrementAt(index) : null,
              primary: true,
            ),
          ],
        ),
        const Gap(8),
        _NoteField(index: index, initial: item.note),
      ],
    );
  }
}

class _NoteField extends StatefulWidget {
  final int index;
  final String initial;
  const _NoteField({required this.index, required this.initial});

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void didUpdateWidget(covariant _NoteField old) {
    super.didUpdateWidget(old);
    if (widget.initial != _controller.text) {
      _controller.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        return TextField(
          controller: _controller,
          onChanged: (v) =>
              ref.read(cartProvider.notifier).setNote(widget.index, v),
          textInputAction: TextInputAction.done,
          maxLines: 1,
          style: TextStyle(fontSize: 12, color: kTextDark),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Catatan (mis. tanpa es, extra pedas)',
            hintStyle: TextStyle(fontSize: 11, color: kTextLight),
            prefixIcon: Padding(
              padding: EdgeInsets.only(left: 10, right: 6),
              child: HugeIcon(icon: AppIcons.notes, color: kTextMid, size: 14),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 28,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
            filled: true,
            fillColor: kBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        );
      },
    );
  }
}

class _MiniQtyBtn extends StatelessWidget {
  final IconAsset icon;
  final VoidCallback? onTap;
  final bool primary;
  const _MiniQtyBtn({
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
          color: primary ? Colors.white : (enabled ? kTextDark : kTextMid),
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _BreakdownRow({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: color ?? kTextMid,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: color ?? kTextDark,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

String _fmtPct(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}
