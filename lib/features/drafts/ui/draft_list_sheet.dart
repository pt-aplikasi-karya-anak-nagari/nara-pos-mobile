import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/format.dart';
import '../../kasir/providers.dart';
import '../domain/draft_order.dart';
import '../providers.dart';

class DraftListSheet extends ConsumerWidget {
  const DraftListSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(draftsProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
                const Gap(16),
                Row(
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
                          icon: AppIcons.task,
                          color: kPrimary,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Draft Pesanan',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: kTextDark,
                        ),
                      ),
                    ),
                    Text(
                      '${drafts.length} draft',
                      style: TextStyle(
                        fontSize: 12,
                        color: kTextMid,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Gap(12),
              ],
            ),
          ),
          Divider(color: kDivider, height: 1),
          Expanded(
            child: drafts.isEmpty
                ? const _EmptyDrafts()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: drafts.length,
                    separatorBuilder: (_, _) => const Gap(10),
                    itemBuilder: (_, i) => _DraftTile(draft: drafts[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DraftTile extends ConsumerWidget {
  final DraftOrder draft;
  const _DraftTile({required this.draft});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);

    Future<void> handleRestore() async {
      if (cart.isNotEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ganti keranjang?'),
            content: const Text(
              'Keranjang saat ini akan diganti dengan isi draft. Lanjutkan?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Lanjutkan'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }

      restoreDraftToCart(ref, draft);
      await ref.read(draftsProvider.notifier).delete(draft.id);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft berhasil dimuat ke keranjang')),
      );
    }

    Future<void> handleDelete() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hapus draft?'),
          content: Text('Draft "${draft.name}" akan dihapus permanen.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus', style: TextStyle(color: kDanger)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await ref.read(draftsProvider.notifier).delete(draft.id);
    }

    final meta = <String>[
      if (draft.customerName != null && draft.customerName!.isNotEmpty)
        draft.customerName!,
      if (draft.tableName != null && draft.tableName!.isNotEmpty)
        '${draft.tableName}',
      if (draft.orderTypeName != null && draft.orderTypeName!.isNotEmpty)
        draft.orderTypeName!,
    ];

    return InkWell(
      onTap: handleRestore,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kDivider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    draft.name,
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
                    _formatRelativeTime(draft.updatedAt),
                    style: TextStyle(fontSize: 11, color: kTextMid),
                  ),
                  if (meta.isNotEmpty) ...[
                    const Gap(6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: meta
                          .map(
                            (m) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: kPrimary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                m,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: kPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const Gap(8),
                  Row(
                    children: [
                      Text(
                        '${draft.totalItems} item',
                        style: TextStyle(
                          fontSize: 11,
                          color: kTextMid,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '  •  ',
                        style: TextStyle(color: kTextLight, fontSize: 11),
                      ),
                      Text(
                        formatRupiah(draft.totalAmount),
                        style: const TextStyle(
                          fontSize: 13,
                          color: kPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                _IconAction(
                  icon: AppIcons.refresh,
                  color: kPrimary,
                  onTap: handleRestore,
                  tooltip: 'Muat ke keranjang',
                ),
                const Gap(6),
                _IconAction(
                  icon: AppIcons.delete,
                  color: kDanger,
                  onTap: handleDelete,
                  tooltip: 'Hapus draft',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconAsset icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;
  const _IconAction({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: HugeIcon(icon: icon, color: color, size: 16),
          ),
        ),
      ),
    );
  }
}

class _EmptyDrafts extends StatelessWidget {
  const _EmptyDrafts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Center(
              child: HugeIcon(icon: AppIcons.task, color: kPrimary, size: 36),
            ),
          ),
          const Gap(16),
          Text(
            'Belum ada draft',
            style: TextStyle(fontWeight: FontWeight.w700, color: kTextDark),
          ),
          const Gap(6),
          Text(
            'Simpan keranjang ke draft untuk\nmelanjutkan transaksi nanti',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: kTextMid),
          ),
        ],
      ),
    );
  }
}

String _formatRelativeTime(DateTime t) {
  final now = DateTime.now();
  final diff = now.difference(t);
  if (diff.inSeconds < 60) return 'Baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam lalu';
  if (diff.inDays < 7) return '${diff.inDays} hari lalu';
  return '${t.day.toString().padLeft(2, '0')}/'
      '${t.month.toString().padLeft(2, '0')}/${t.year} '
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}
