import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:sizer/sizer.dart';
import '../../../../app/theme.dart';
import '../../../../core/app_icons.dart';
import '../../../../core/format.dart';
import '../../../../core/product_image.dart';
import '../../domain/cart_item.dart';
import '../../../drafts/providers.dart';
import '../../../settings/data/tax_settings.dart';
import '../../providers.dart';
import 'empty_states.dart';
import 'customer_selector.dart';
import 'line_discount_sheet.dart';
import 'menu_orders_tab.dart';

/// Panel keranjang permanen yang ditampilkan di sisi kanan layar
/// pada mode tablet/landscape, mirip POS profesional.
class CartPanel extends ConsumerWidget {
  final VoidCallback onCheckout;
  const CartPanel({super.key, required this.onCheckout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final subtotal = ref.watch(subtotalProvider);
    final tax = ref.watch(taxProvider);
    final total = ref.watch(totalProvider);
    final totalItems = ref.watch(totalItemsProvider);
    final taxSettings = ref.watch(taxSettingsProvider);
    final notifier = ref.read(cartProvider.notifier);

    return DefaultTabController(
      length: 2,
      child: Container(
        color: kCard,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: HugeIcon(
                          icon: AppIcons.receiptLong,
                          color: kPrimary,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pesanan',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w700,
                          color: kTextDark,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _CartStatChip(
                          icon: AppIcons.inventory,
                          label: '${cart.length} Produk',
                        ),
                        _CartStatChip(
                          icon: AppIcons.receiptLong,
                          label: '$totalItems Qty',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Gap(16),
              // ── TabBar ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: kBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TabBar(
                    indicator: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
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
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    padding: const EdgeInsets.all(4),
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'Langsung di Kasir'),
                      Tab(text: 'Pesanan dari Scan Meja'),
                    ],
                  ),
                ),
              ),
              const Gap(8),
              Expanded(
                child: TabBarView(
                  children: [
                    // Tab 1: Pesanan Langsung
                    Column(
                      children: [
                        if (cart.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Expanded(child: const CustomerSelector()),
                                Gap(8),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () async {
                                        final ok = await saveCurrentCartAsDraft(
                                          ref,
                                        );
                                        if (!context.mounted) return;
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
                                          horizontal: 10,
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
                                              'Draft',
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
                                      onTap: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Konfirmasi'),
                                            content: const Text(
                                              'Anda yakin ingin menghapus semua pesanan?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const Text('Tidak'),
                                              ),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: kDanger,
                                                  foregroundColor: Colors.white,
                                                ),
                                                onPressed: () {
                                                  Navigator.pop(context);
                                                  return notifier.clear();
                                                },
                                                child: const Text('Hapus'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
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
                                              'Semua',
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

                        const Gap(8),
                        Divider(color: kDivider, height: 1),
                        Expanded(
                          child: cart.isEmpty
                              ? const EmptyCart()
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
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
                          Container(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              16,
                              16,
                              MediaQuery.of(context).padding.bottom + 16,
                            ),
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: kDivider)),
                            ),
                            child: Column(
                              children: [
                                // ── Breakdown Transparan ──
                                _BreakdownRow(
                                  label: 'Subtotal',
                                  value: formatRupiah(subtotal),
                                ),
                                if (ref.watch(discountTotalProvider) > 0) ...[
                                  const Gap(4),
                                  _BreakdownRow(
                                    label: 'Diskon',
                                    value:
                                        '- ${formatRupiah(ref.watch(discountTotalProvider))}',
                                    color: kSuccess,
                                  ),
                                ],
                                if (ref.watch(serviceChargeProvider) > 0) ...[
                                  const Gap(4),
                                  _BreakdownRow(
                                    label:
                                        '${taxSettings.serviceChargeName} (${_fmtPct(taxSettings.serviceChargePercent)}%)',
                                    value: formatRupiah(
                                      ref.watch(serviceChargeProvider),
                                    ),
                                    color: kTextMid,
                                  ),
                                ],
                                if (taxSettings.enabled) ...[
                                  const Gap(4),
                                  _BreakdownRow(
                                    label:
                                        'PPN (${_fmtPct(taxSettings.percent)}%)',
                                    value: formatRupiah(tax),
                                    color: kTextMid,
                                  ),
                                ],
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Divider(color: kDivider, height: 1),
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Total',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: kTextDark,
                                      ),
                                    ),
                                    Text(
                                      formatRupiah(total),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: kPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                const Gap(16),
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
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const HugeIcon(
                                          icon: AppIcons.payment,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Bayar ${formatRupiah(total)}',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.sp,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
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

/// Penanda halus untuk baris item yang bebas pajak (is_taxable=false).
class _TaxFreeBadge extends StatelessWidget {
  const _TaxFreeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: kTextMid.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Bebas pajak',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: kTextMid,
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
              size: 44,
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
                  if (item.modifiers.isNotEmpty) ...[
                    const Gap(2),
                    Text(
                      item.modifiersLabel,
                      style: TextStyle(fontSize: 10, color: kTextMid),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
                      if (!item.isTaxable) ...[
                        const SizedBox(width: 6),
                        const _TaxFreeBadge(),
                      ],
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
              // C4: turunkan BARIS ini (by index), bukan cari by product —
              // baris modifier berbeda tak boleh salah target.
              onTap: () => notifier.decrementAt(index),
              primary: false,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
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
              // C4: naikkan BARIS ini (by index) — pertahankan modifier baris.
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
        padding: const EdgeInsets.all(6),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: primary
              ? (enabled ? kPrimary : kTextMid.withValues(alpha: 0.3))
              : kBg,
          borderRadius: BorderRadius.circular(8),
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
            fontSize: 12,
            color: color ?? kTextMid,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
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
