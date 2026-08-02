import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/offline/offline_sync_service.dart';
import '../../core/offline/sale_outbox.dart';
import '../../core/offline/shift_outbox.dart';
import 'sheet_bawah.dart';

/// Sheet pemulihan transaksi offline yang gagal sinkron permanen (dead-letter).
/// Mencegah kehilangan diam-diam: owner bisa lihat detail + alasan gagal, lalu
/// pilih "Coba Lagi" (re-queue) atau "Buang" (hapus permanen).
Future<void> showDeadLetterRecoverySheet(BuildContext context, WidgetRef ref) {
  return tampilkanSheetBawah<void>(
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
                    // TIDAK boleh berhenti di sini saat daftar penjualan kosong.
                    //
                    // Sheet ini kini juga memuat seksi shift, dan keduanya
                    // punya sumber sendiri. Berhenti pada penjualan yang kosong
                    // membuat sheet berkata "Tidak ada transaksi gagal 🎉"
                    // sementara bannernya baru saja berkata ada catatan shift
                    // yang gagal — dua pernyataan yang bertentangan, di layar
                    // yang sama, tentang uang laci yang hilang.
                    //
                    // Keadaan benar-benar kosong ditangani _SeksiShiftGagal:
                    // ia yang tahu apakah masih ada sisa.
                    return ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final ps in items) ...[
                          _DeadLetterCard(
                            sale: ps,
                            onRetry: () => _retry(ps),
                            onDiscard: () => _discard(ps),
                          ),
                          const Gap(10),
                        ],
                        // Seksi kedua: buka/tutup shift yang gagal permanen.
                        // Sebelum ini tak punya permukaan UI sama sekali, jadi
                        // catatan uang laci hilang tanpa ada yang tahu.
                        _SeksiShiftGagal(
                          onSelesai: _reload,
                          adaPenjualanGagal: items.isNotEmpty,
                        ),
                      ],
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

/// Buka/tutup shift yang ditolak permanen, DIKELOMPOKKAN PER SHIFT.
///
/// # KENAPA PER SHIFT
///
/// markDeadCascade menandai open DAN close turunannya mati bersamaan: close tak
/// berarti apa-apa tanpa open yang berhasil, karena server_shift_id-nya datang
/// dari respons open.
///
/// Menampilkannya sebagai baris terpisah akan mengundang kasir menekan "Coba
/// lagi" pada baris CLOSE — baris yang memuat uang laci, jadi yang paling
/// menarik perhatiannya. Close itu lalu dikirim untuk shift yang di server tak
/// pernah ada, gagal lagi, dan kasirnya menyangka aplikasinya rusak.
class _SeksiShiftGagal extends ConsumerStatefulWidget {
  const _SeksiShiftGagal({required this.onSelesai, required this.adaPenjualanGagal});
  final VoidCallback onSelesai;

  /// Dipakai memutuskan siapa yang menampilkan pesan "tidak ada apa-apa".
  /// Hanya satu yang boleh menampilkannya, kalau tidak layarnya berkata dua
  /// kali hal yang sama.
  final bool adaPenjualanGagal;

  @override
  ConsumerState<_SeksiShiftGagal> createState() => _SeksiShiftGagalState();
}

class _SeksiShiftGagalState extends ConsumerState<_SeksiShiftGagal> {
  late Future<List<PendingOp>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(shiftOutboxProvider).deadLetters();
  }

  void _muatUlang() {
    setState(() => _future = ref.read(shiftOutboxProvider).deadLetters());
    ref.read(shiftDeadLetterCountProvider.notifier).refresh();
    widget.onSelesai();
  }

  Future<void> _coba(String localShiftId) async {
    await ref.read(shiftOutboxProvider).retryShift(localShiftId);
    if (!mounted) return;
    _muatUlang();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dikembalikan ke antrean — akan dikirim saat online.')),
    );
  }

  Future<void> _buang(String localShiftId) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Buang catatan shift ini?'),
        content: const Text(
          'Catatan buka & tutup shift ini akan dihapus permanen dan TIDAK '
          'terkirim ke server. Z-Report untuk shift itu tidak akan pernah '
          'terbit, dan rekonsiliasi kasnya tak bisa diselesaikan.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: kDanger),
            child: const Text('Buang'),
          ),
        ],
      ),
    );
    if (ya != true) return;
    await ref.read(shiftOutboxProvider).discardShift(localShiftId);
    if (!mounted) return;
    _muatUlang();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PendingOp>>(
      future: _future,
      builder: (context, snap) {
        final ops = snap.data ?? const <PendingOp>[];
        if (ops.isEmpty) {
          if (widget.adaPenjualanGagal) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Tidak ada yang gagal terkirim. 🎉',
                style: TextStyle(color: kTextMid),
              ),
            ),
          );
        }

        // Kelompokkan per shift, dengan urutan kemunculan dipertahankan.
        final perShift = <String, List<PendingOp>>{};
        for (final op in ops) {
          perShift.putIfAbsent(op.localShiftId ?? op.localId, () => []).add(op);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Gap(8),
            Text(
              'BUKA/TUTUP SHIFT GAGAL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: kTextMid,
                letterSpacing: 0.5,
              ),
            ),
            const Gap(8),
            for (final e in perShift.entries) ...[
              _KartuShiftGagal(
                ops: e.value,
                onCoba: () => _coba(e.key),
                onBuang: () => _buang(e.key),
              ),
              const Gap(10),
            ],
          ],
        );
      },
    );
  }
}

class _KartuShiftGagal extends StatelessWidget {
  const _KartuShiftGagal({
    required this.ops,
    required this.onCoba,
    required this.onBuang,
  });

  final List<PendingOp> ops;
  final VoidCallback onCoba;
  final VoidCallback onBuang;

  @override
  Widget build(BuildContext context) {
    final jenis = ops.map((o) => o.opType).toSet().toList()..sort();
    final galat = ops
        .map((o) => o.lastError)
        .whereType<String>()
        .where((e) => e.trim().isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kDanger.withValues(alpha: 0.06),
        border: Border.all(color: kDanger.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            jenis.join(' + '),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const Gap(4),
          Text(
            '${ops.length} operasi dalam satu shift — dipulihkan bersamaan '
            'supaya urutannya tetap benar.',
            style: TextStyle(color: kTextMid, fontSize: 12, height: 1.4),
          ),
          if (galat.isNotEmpty) ...[
            const Gap(6),
            Text(
              galat.first,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: kDanger, fontSize: 11),
            ),
          ],
          const Gap(12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onBuang,
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Buang'),
                ),
              ),
              const Gap(8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onCoba,
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
