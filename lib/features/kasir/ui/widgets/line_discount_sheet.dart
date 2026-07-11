import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../app/theme.dart';
import '../../../../core/app_icons.dart';
import '../../../../core/format.dart';
import '../../domain/cart_item.dart';
import '../../providers.dart';

/// Bottom sheet untuk memberikan / mengedit diskon manual pada satu baris cart.
///
/// Tampilkan via:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   useRootNavigator: true,
///   backgroundColor: Colors.transparent,
///   builder: (_) => LineDiscountSheet(index: i, item: item),
/// );
/// ```
class LineDiscountSheet extends HookConsumerWidget {
  final int index;
  final CartItem item;

  const LineDiscountSheet({super.key, required this.index, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = useState<String>(
      item.hasManualDiscount ? item.manualDiscountType : 'percent',
    );
    final initialText = item.hasManualDiscount
        ? (item.manualDiscountType == 'percent'
              ? item.manualDiscountValue.toInt().toString()
              : 'Rp ${formatThousand(item.manualDiscountValue.toInt())}')
        : '';
    final valueCtrl = useTextEditingController(text: initialText);
    final error = useState<String?>(null);

    void save() {
      error.value = null;
      double parsed;
      if (type.value == 'percent') {
        parsed = double.tryParse(valueCtrl.text.trim()) ?? 0;
        if (parsed <= 0 || parsed > 100) {
          error.value = 'Persentase harus 0–100';
          return;
        }
      } else {
        parsed = parseRupiahInput(valueCtrl.text).toDouble();
        if (parsed <= 0) {
          error.value = 'Nilai diskon wajib > 0';
          return;
        }
        if (parsed > item.basePrice) {
          error.value =
              'Diskon melebihi harga (${formatRupiah(item.basePrice)})';
          return;
        }
      }
      ref
          .read(cartProvider.notifier)
          .setLineDiscount(index, type.value, parsed);
      Navigator.of(context).pop();
    }

    void clear() {
      ref.read(cartProvider.notifier).clearLineDiscount(index);
      Navigator.of(context).pop();
    }

    final mq = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, mq.padding.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const Gap(16),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: kAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: HugeIcon(
                      icon: AppIcons.discount,
                      color: kAccent,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Diskon untuk ${item.displayName}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kTextDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Gap(2),
                      Text(
                        'Harga ${formatRupiah(item.basePrice)}',
                        style: TextStyle(fontSize: 11, color: kTextMid),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Gap(20),
            Text(
              'Tipe Diskon',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kTextMid,
              ),
            ),
            const Gap(8),
            Row(
              children: [
                Expanded(
                  child: _TypeChip(
                    label: 'Persentase (%)',
                    active: type.value == 'percent',
                    onTap: () {
                      type.value = 'percent';
                      valueCtrl.clear();
                      error.value = null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TypeChip(
                    label: 'Nominal (Rp)',
                    active: type.value == 'fixed',
                    onTap: () {
                      type.value = 'fixed';
                      valueCtrl.clear();
                      error.value = null;
                    },
                  ),
                ),
              ],
            ),
            const Gap(16),
            Text(
              type.value == 'percent' ? 'Nilai (%)' : 'Nilai (Rp)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kTextMid,
              ),
            ),
            const Gap(8),
            Container(
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: error.value != null ? kDanger : kDivider,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: valueCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                inputFormatters: type.value == 'fixed'
                    ? [RupiahInputFormatter()]
                    : null,
                onSubmitted: (_) => save(),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kTextDark,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: type.value == 'percent' ? '0' : 'Rp 0',
                  hintStyle: TextStyle(color: kTextLight),
                  suffixText: type.value == 'percent' ? '%' : null,
                  suffixStyle: TextStyle(
                    color: kTextMid,
                    fontWeight: FontWeight.w700,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (error.value != null) ...[
              const Gap(6),
              Text(
                error.value!,
                style: const TextStyle(fontSize: 11, color: kDanger),
              ),
            ],
            const Gap(20),
            Row(
              children: [
                if (item.hasManualDiscount)
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: clear,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kDanger,
                          side: const BorderSide(color: kDanger),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Hapus Diskon',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                if (item.hasManualDiscount) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Simpan',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TypeChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? kPrimary.withValues(alpha: 0.1) : kBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? kPrimary : kDivider),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: active ? kPrimary : kTextMid,
            ),
          ),
        ),
      ),
    );
  }
}
