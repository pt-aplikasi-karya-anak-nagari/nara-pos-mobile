import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/offline/offline_sync_service.dart';
import '../../core/offline/sale_outbox.dart';

/// Sheet pemulihan transaksi offline yang gagal sinkron permanen (dead-letter).
/// Mencegah kehilangan diam-diam: owner bisa lihat detail + alasan gagal, lalu
/// pilih "Coba Lagi" (re-queue) atau "Buang" (hapus permanen).
Future<void> showDeadLetterRecoverySheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _DeadLetterRecoverySheet(),
  );
}

class _DeadLetterRecoverySheet extends ConsumerStatefulWidget {
  const _DeadLetterRecoverySheet();

  @override
  ConsumerState<_DeadLetterRecoverySheet> createState() =>
      _DeadLetterRecoverySheetState();
}

class _DeadLetterRecoverySheetState
    extends ConsumerState<_DeadLetterRecoverySheet> {
  late Future<List<PendingSale>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(saleOutboxProvider).deadLetters();
  }

  void _reload() {
    setState(() => _future = ref.read(saleOutboxProvider).deadLetters());
  }

  Future<void> _refreshCounts() async {
    await ref.read(pendingSyncCountProvider.notifier).refresh();
    await ref.read(deadLetterCountProvider.notifier).refresh();
  }

  Future<void> _retry(PendingSale ps) async {
    await ref.read(saleOutboxProvider).retry(ps.localId);
    await _refreshCounts();
    if (mounted) {
      _reload();
      _snack('Transaksi dimasukkan antrian — akan dicoba kirim ulang.');
    }
    // Picu satu kali sync (kalau online) tanpa blok UI.
    unawaited(
      ref.read(offlineSyncServiceProvider).sync().whenComplete(_refreshCounts),
    );
  }

  Future<void> _discard(PendingSale ps) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Buang transaksi?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: Text(
          'Transaksi ini akan dihapus permanen dan TIDAK terkirim ke server. '
          'Pastikan kamu sudah mencatatnya manual bila perlu.',
          style: TextStyle(color: kTextMid, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kDanger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Buang'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(saleOutboxProvider).remove(ps.localId);
    await _refreshCounts();
    if (mounted) {
      _reload();
      _snack('Transaksi dibuang.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              const Gap(10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kDivider,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: kDanger, size: 22),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        'Transaksi gagal terkirim',
                        style: TextStyle(
                          color: kTextDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Transaksi ini sudah dicoba beberapa kali tapi ditolak server '
                  '(mis. produk dihapus / data tidak valid). Coba kirim ulang, '
                  'atau buang kalau memang tidak perlu.',
                  style: TextStyle(color: kTextMid, fontSize: 12, height: 1.4),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<List<PendingSale>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final items = snap.data ?? const [];
                    if (items.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Tidak ada transaksi gagal. 🎉',
                            style: TextStyle(color: kTextMid),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Gap(10),
                      itemBuilder: (_, i) => _DeadLetterCard(
                        sale: items[i],
                        onRetry: () => _retry(items[i]),
                        onDiscard: () => _discard(items[i]),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DeadLetterCard extends StatelessWidget {
  final PendingSale sale;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  const _DeadLetterCard({
    required this.sale,
    required this.onRetry,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final total = (sale.payload['final_amount'] as num?)?.toInt() ?? 0;
    final itemCount = (sale.payload['items'] as List?)?.length ?? 0;
    final method = sale.payload['payment_method']?.toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kDanger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatRupiah(total),
                  style: TextStyle(
                    color: kTextDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$itemCount item${method != null ? ' • $method' : ''}',
                style: TextStyle(color: kTextMid, fontSize: 12),
              ),
            ],
          ),
          const Gap(4),
          Text(
            'Dibuat ${formatDateTime(sale.createdAt)}',
            style: TextStyle(color: kTextMid, fontSize: 11),
          ),
          if ((sale.lastError ?? '').isNotEmpty) ...[
            const Gap(8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kDanger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                sale.lastError!,
                style: TextStyle(color: kDanger, fontSize: 11, height: 1.35),
              ),
            ),
          ],
          const Gap(10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDiscard,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kDanger,
                    side: BorderSide(color: kDanger.withValues(alpha: 0.4)),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Buang'),
                ),
              ),
              const Gap(8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(backgroundColor: kPrimary),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Coba Lagi'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
