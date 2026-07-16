import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../../app/theme.dart';
import '../../../../core/format.dart';
import '../../../../core/outlet_scope.dart';
import '../../../settings/data/app_settings.dart';
import '../../../kasir/providers.dart';
import '../../../order_types/data/order_type_repository.dart';
import '../../../shifts/data/shift_repository.dart';
import '../../../transactions/data/transaction_repository.dart';
import '../../../transactions/domain/sale.dart';
import '../../../transactions/ui/widgets/mini_payment_sheet.dart';
import '../../data/table_repository.dart';
import '../../domain/pos_table.dart';

/// Dialog detail meja: tampilkan status, durasi live, dan rincian
/// pesanan yang sedang berjalan kalau meja sedang occupied.
///
/// Dipakai HookConsumerWidget supaya bisa pakai `useState`+`useEffect`
/// untuk timer detik-an tanpa repaint seluruh dialog tiap rebuild.
class TableStatusDialog extends HookConsumerWidget {
  final PosTable table;
  const TableStatusDialog({super.key, required this.table});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeOutletId = ref.watch(activeOutletIdProvider);
    final isOccupied = table.status == TableStatus.occupied;

    // Active sales hanya di-fetch kalau meja occupied — meja kosong
    // pasti tidak punya transaksi unpaid, jadi hindari API call sia-sia.
    final salesAsync = isOccupied
        ? ref.watch(activeTableTransactionsProvider(table.id))
        : const AsyncValue<List<Sale>>.data([]);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              table: table,
              isOccupied: isOccupied,
              salesAsync: salesAsync,
              onClose: () => Navigator.pop(context),
            ),
            const Gap(16),
            // Picker status: tombol segmented untuk override manual
            // (mis. set "Reserved" untuk booking, atau set "Available"
            // setelah tamu lunas via channel lain).
            _StatusPicker(table: table, salesAsync: salesAsync),
            const Gap(16),
            // Body bertingkat: header sudah, lalu rincian + total + tombol.
            // Pakai Flexible supaya isi panjang scroll tanpa overflow.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isOccupied)
                      salesAsync.when(
                        data: (sales) =>
                            _OrderSection(sales: sales, tableId: table.id),
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (e, _) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Gagal memuat pesanan: $e',
                            style: const TextStyle(color: kDanger),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Gap(20),
            _Actions(
              table: table,
              isOccupied: isOccupied,
              activeOutletId: activeOutletId,
              salesAsync: salesAsync,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Header ────────────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  final PosTable table;
  final bool isOccupied;
  final AsyncValue<List<Sale>> salesAsync;
  final VoidCallback onClose;
  const _Header({
    required this.table,
    required this.isOccupied,
    required this.salesAsync,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isOccupied
                ? kDanger.withValues(alpha: 0.1)
                : kSuccess.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.table_restaurant,
            color: isOccupied ? kDanger : kSuccess,
          ),
        ),
        const Gap(16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                table.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Gap(2),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (isOccupied ? kDanger : kSuccess).withValues(
                        alpha: 0.1,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isOccupied ? 'TERISI' : 'TERSEDIA',
                      style: TextStyle(
                        color: isOccupied ? kDanger : kSuccess,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Gap(8),
                  Text(
                    '${table.capacity} kursi',
                    style: TextStyle(color: kTextMid, fontSize: 12),
                  ),
                  // Live duration: di-build hanya kalau ada sales aktif.
                  ...salesAsync.maybeWhen(
                    data: (sales) {
                      if (sales.isEmpty) return const <Widget>[];
                      return [
                        const Gap(8),
                        _Dot(),
                        const Gap(8),
                        _LiveDuration(start: sales.first.createdAt),
                      ];
                    },
                    orElse: () => const <Widget>[],
                  ),
                ],
              ),
            ],
          ),
        ),
        // Tombol refresh manual — invalidate provider supaya fetch ulang
        // dari backend. Berguna kalau staff baru saja mengubah pesanan
        // dari device lain & ingin lihat data terbaru tanpa tutup-buka
        // dialog.
        if (isOccupied)
          IconButton(
            tooltip: 'Refresh',
            onPressed: () =>
                ref.invalidate(activeTableTransactionsProvider(table.id)),
            icon: Icon(Icons.refresh, color: kTextMid),
          ),
        IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(color: kTextMid, shape: BoxShape.circle),
    );
  }
}

/// Widget terpisah supaya rebuild tiap detik hanya menyentuh teks durasi —
/// rincian items, header, dan tombol tidak ikut repaint.
class _LiveDuration extends HookWidget {
  final DateTime start;
  const _LiveDuration({required this.start});

  @override
  Widget build(BuildContext context) {
    final now = useState(DateTime.now());

    useEffect(() {
      final timer = Timer.periodic(const Duration(seconds: 1), (_) {
        now.value = DateTime.now();
      });
      return timer.cancel;
    }, const []);

    final diff = now.value.difference(start);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;

    String label;
    if (hours > 0) {
      label = '${hours}j ${minutes}m';
    } else if (minutes > 0) {
      label = '${minutes}m ${seconds}d';
    } else {
      label = '${seconds}d';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 12, color: kTextMid),
        const Gap(4),
        Text(
          label,
          style: TextStyle(
            color: kTextMid,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Order section ─────────────────────────────────────────────────────────

class _OrderSection extends StatelessWidget {
  final List<Sale> sales;
  final String tableId;
  const _OrderSection({required this.sales, required this.tableId});

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'Meja terisi namun tidak ada pesanan aktif.',
            style: TextStyle(color: kTextMid, fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final totalQty = sales.fold<int>(
      0,
      (s, sale) => s + sale.items.fold<int>(0, (a, it) => a + it.qty),
    );
    final totalAmount = sales.fold<double>(0, (s, sale) => s + sale.total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Rincian Pesanan',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${sales.length} pesanan · $totalQty item',
                style: const TextStyle(
                  color: kPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const Gap(12),
        for (int i = 0; i < sales.length; i++) ...[
          _SaleCard(index: i + 1, sale: sales[i], tableId: tableId),
          const Gap(8),
        ],
        const Gap(8),
        // Summary total
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kPrimary.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Tagihan Meja',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                formatRupiah(totalAmount),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: kPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SaleCard extends ConsumerWidget {
  final int index;
  final Sale sale;
  final String tableId;
  const _SaleCard({
    required this.index,
    required this.sale,
    required this.tableId,
  });

  Future<void> _payNow(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<
      ({String method, double cash, String proofUrl})
    >(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MiniPaymentSheet(total: sale.total),
    );
    if (result == null) return;

    try {
      final cashAmount = result.method == 'Tunai' ? result.cash : 0.0;
      final changeAmount =
          (result.method == 'Tunai' && result.cash > sale.total)
          ? result.cash - sale.total
          : 0.0;

      await ref
          .read(transactionRepositoryProvider)
          .markAsPaid(
            sale.id,
            paymentMethod: result.method,
            cashAmount: cashAmount,
            changeAmount: changeAmount,
            paymentProofUrl: result.proofUrl.isEmpty ? null : result.proofUrl,
          );

      // Invalidate caches yang terdampak supaya UI sinkron:
      //  - active-transactions meja ini → tx jadi paid, badge berubah
      //  - tablesFutureProvider / groups → kalau ini tx unpaid terakhir,
      //    backend auto-free meja (status_index=0), list harus ikut update
      //  - sales/shift → laporan & total kas terupdate
      ref.invalidate(activeTableTransactionsProvider(tableId));
      ref.invalidate(tablesFutureProvider);
      ref.invalidate(tableGroupsFutureProvider);
      ref.invalidate(salesFutureProvider);
      ref.invalidate(activeShiftProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transaksi ${sale.invoiceId} berhasil dilunasi'),
            backgroundColor: kSuccess,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal melunasi: $e'),
            backgroundColor: kDanger,
          ),
        );
      }
    }
  }

  Future<void> _void(BuildContext context, WidgetRef ref) async {
    // Apakah outlet mewajibkan PIN otorisasi manajer untuk void? Fetch
    // on-demand (di-cache provider); bila gagal (mis. offline) fallback false
    // lalu andalkan penanganan 403 dari backend.
    bool requirePin = false;
    try {
      requirePin =
          (await ref.read(outletAppSettingsProvider.future)).requirePinVoid;
    } catch (_) {
      requirePin = false;
    }
    if (!context.mounted) return;

    // Loop retry: bila submit gagal (mis. 403 PIN salah), dialog dibuka ulang
    // dengan pesan backend + PIN sebelumnya sehingga user bisa perbaiki.
    String pinInit = '';
    String? errorText;
    while (true) {
      if (!context.mounted) return;
      final input = await _askVoidConfirm(
        context,
        requirePin: requirePin,
        pinInit: pinInit,
        errorText: errorText,
      );
      if (input == null) return; // dibatalkan

      try {
        await ref.read(transactionRepositoryProvider).voidSale(
              sale.id,
              overridePin: input.pin.isEmpty ? null : input.pin,
            );
        ref.invalidate(activeTableTransactionsProvider(tableId));
        ref.invalidate(tablesFutureProvider);
        ref.invalidate(tableGroupsFutureProvider);
        ref.invalidate(salesFutureProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Pesanan ${sale.invoiceId} dibatalkan'),
              backgroundColor: kSuccess,
            ),
          );
        }
        return;
      } catch (e) {
        if (!context.mounted) return;
        // Pertahankan PIN & tampilkan pesan backend di dialog ulang.
        pinInit = input.pin;
        errorText = e.toString();
      }
    }
  }

  /// Dialog konfirmasi void. Bila [requirePin] atau percobaan sebelumnya
  /// ditolak backend ([errorText] != null), tampilkan input PIN otorisasi
  /// manajer (numeric, obscure, 4-6 digit). Mengembalikan (pin) bila
  /// dikonfirmasi — pin bisa string kosong bila tidak diminta — atau null bila
  /// dibatalkan.
  Future<({String pin})?> _askVoidConfirm(
    BuildContext context, {
    required bool requirePin,
    String pinInit = '',
    String? errorText,
  }) async {
    final pinController = TextEditingController(text: pinInit);
    final showPin = requirePin || errorText != null;
    final result = await showDialog<({String pin})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final pin = pinController.text.trim();
          final pinValid = pin.length >= 4 && pin.length <= 6;
          // PIN wajib bila outlet mensyaratkan. Bila hanya muncul akibat 403
          // (bukan requirePin), PIN opsional tapi format tetap divalidasi.
          final pinOk = requirePin ? pinValid : (pin.isEmpty || pinValid);
          return AlertDialog(
            title: const Text('Batalkan pesanan ini?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (errorText != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kDanger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      errorText,
                      style: const TextStyle(
                        color: kDanger,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Gap(12),
                ],
                Text(
                  'Pesanan ${sale.invoiceId} (${formatRupiah(sale.total)}) akan '
                  'dibatalkan dan stok dikembalikan. Tindakan ini tidak bisa diurungkan.',
                ),
                if (showPin) ...[
                  const Gap(12),
                  TextField(
                    controller: pinController,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setLocal(() {}),
                    decoration: InputDecoration(
                      labelText: requirePin
                          ? 'PIN Otorisasi Manajer'
                          : 'PIN Otorisasi Manajer (bila diminta)',
                      hintText: '4-6 digit',
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: pinOk ? () => Navigator.pop(ctx, (pin: pin)) : null,
                style: TextButton.styleFrom(foregroundColor: kDanger),
                child: const Text('Ya, Batalkan'),
              ),
            ],
          );
        },
      ),
    );
    pinController.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeStr = _formatTimeOnly(sale.createdAt);
    return Container(
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          initiallyExpanded: index == 1,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '#$index',
                  style: const TextStyle(
                    color: kPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              const Gap(8),
              Expanded(
                child: Text(
                  sale.customerName.isEmpty ? 'Umum' : sale.customerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                formatRupiah(sale.total),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: kTextDark,
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.access_time, size: 11, color: kTextMid),
                const Gap(4),
                Text(
                  timeStr,
                  style: TextStyle(color: kTextMid, fontSize: 10),
                ),
                const Gap(8),
                Text(
                  sale.invoiceId,
                  style: TextStyle(color: kTextMid, fontSize: 10),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: sale.isPaid
                        ? kSuccess.withValues(alpha: 0.1)
                        : kWarning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    sale.isPaid ? 'LUNAS' : 'BELUM BAYAR',
                    style: TextStyle(
                      color: sale.isPaid ? kSuccess : kWarning,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          children: [
            const Divider(height: 16),
            ...sale.items.map(
              (it) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          margin: const EdgeInsets.only(top: 1),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: kDivider),
                          ),
                          child: Text(
                            '${it.qty}x',
                            style: TextStyle(
                              color: kTextDark,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Gap(8),
                        Expanded(
                          child: Text(
                            it.productName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          formatRupiah(it.price * it.qty),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (it.note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 30, top: 2),
                        child: Text(
                          '* ${it.note}',
                          style: TextStyle(
                            fontSize: 11,
                            color: kTextMid,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 16),
            // Per-sale summary baris kecil
            _SummaryRow(label: 'Subtotal', value: sale.subtotal),
            if (sale.discountTotal > 0)
              _SummaryRow(
                label: 'Diskon',
                value: -sale.discountTotal,
                color: kAccent,
              ),
            if (sale.tax > 0) _SummaryRow(label: 'PPN', value: sale.tax),
            const Gap(4),
            _SummaryRow(
              label: 'Total',
              value: sale.total,
              bold: true,
              color: kPrimary,
            ),
            // Tombol "Bayar" hanya muncul untuk transaksi yang masih
            // berstatus belum lunas (unpaid/pending). Tx yang sudah lunas
            // (mis. cash dine-in) ditampilkan info-only.
            if (!sale.isPaid) ...[
              const Gap(12),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () => _payNow(context, ref),
                  icon: const Icon(Icons.payments_outlined, size: 16),
                  label: Text(
                    'Bayar ${formatRupiah(sale.total)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kSuccess,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const Gap(8),
              SizedBox(
                width: double.infinity,
                height: 36,
                child: OutlinedButton.icon(
                  onPressed: () => _void(context, ref),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text(
                    'Batalkan pesanan',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kDanger,
                    side: BorderSide(color: kDanger.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimeOnly(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final bool bold;
  final Color? color;
  const _SummaryRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: bold ? kTextDark : kTextMid,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            formatRupiah(value),
            style: TextStyle(
              fontSize: bold ? 13 : 12,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              color: color ?? (bold ? kTextDark : kTextDark),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Actions ───────────────────────────────────────────────────────────────

class _Actions extends ConsumerWidget {
  final PosTable table;
  final bool isOccupied;
  final String? activeOutletId;
  final AsyncValue<List<Sale>> salesAsync;
  const _Actions({
    required this.table,
    required this.isOccupied,
    required this.activeOutletId,
    required this.salesAsync,
  });

  // Pindah / gabung bill: pilih meja tujuan, lalu reassign semua pesanan
  // aktif meja ini ke sana. Kalau tujuan sudah terisi → gabung bill.
  Future<void> _move(BuildContext context, WidgetRef ref) async {
    final outletId = activeOutletId;
    if (outletId == null) return;
    final allTables =
        ref.read(tablesFutureProvider).value ?? const <PosTable>[];
    final candidates = allTables.where((t) => t.id != table.id).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada meja lain untuk dituju.')),
      );
      return;
    }

    final target = await showDialog<PosTable>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pindahkan pesanan ke meja'),
        children: candidates
            .map(
              (t) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, t),
                child: Row(
                  children: [
                    Icon(
                      t.status == TableStatus.occupied
                          ? Icons.event_seat
                          : Icons.check_circle,
                      size: 18,
                      color: t.status == TableStatus.occupied
                          ? kDanger
                          : kSuccess,
                    ),
                    const Gap(10),
                    Text(t.name),
                    if (t.status == TableStatus.occupied) ...[
                      const Gap(6),
                      Text(
                        '(gabung bill)',
                        style: TextStyle(color: kTextMid, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (target == null) return;

    try {
      final moved = await ref
          .read(transactionRepositoryProvider)
          .moveTableSales(outletId, table.id, target.id);
      ref.invalidate(tablesFutureProvider);
      ref.invalidate(tableGroupsFutureProvider);
      ref.invalidate(activeTableTransactionsProvider(table.id));
      ref.invalidate(activeTableTransactionsProvider(target.id));
      if (context.mounted) {
        Navigator.of(context).pop(); // tutup dialog detail meja (kini stale)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$moved pesanan dipindah ke ${target.name}'),
            backgroundColor: kSuccess,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memindahkan: $e'),
            backgroundColor: kDanger,
          ),
        );
      }
    }
  }

  // Open bill: tutup meja sekali bayar. Satu MiniPaymentSheet untuk total tab
  // (ronde yang benar-benar dilunasi backend), satu panggilan settleTable
  // (atomik), lalu invalidate provider yang sama dengan _payNow + tutup dialog.
  Future<void> _settleAll(
    BuildContext context,
    WidgetRef ref,
    List<Sale> settleable,
  ) async {
    final outletId = activeOutletId;
    if (outletId == null || settleable.isEmpty) return;
    final tabTotal = settleable.fold<double>(0, (s, x) => s + x.total);

    final result =
        await showModalBottomSheet<({String method, double cash, String proofUrl})>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => MiniPaymentSheet(total: tabTotal),
        );
    if (result == null) return;

    try {
      final cashAmount = result.method == 'Tunai' ? result.cash : 0.0;
      final changeAmount = (result.method == 'Tunai' && result.cash > tabTotal)
          ? result.cash - tabTotal
          : 0.0;

      final settled = await ref
          .read(transactionRepositoryProvider)
          .settleTable(
            outletId,
            table.id,
            paymentMethod: result.method,
            cashAmount: cashAmount,
            changeAmount: changeAmount,
            paymentProofUrl: result.proofUrl.isEmpty ? null : result.proofUrl,
          );

      ref.invalidate(activeTableTransactionsProvider(table.id));
      ref.invalidate(tablesFutureProvider);
      ref.invalidate(tableGroupsFutureProvider);
      ref.invalidate(salesFutureProvider);
      ref.invalidate(activeShiftProvider);

      if (context.mounted) {
        Navigator.of(context).pop(); // meja sudah lunas & bebas → tutup dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Meja ${table.name} ditutup — $settled pesanan dilunasi',
            ),
            backgroundColor: kSuccess,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menutup meja: $e'),
            backgroundColor: kDanger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ronde yang boleh ditutup lewat "Bayar Semua" = TEPAT yang dilunasi backend:
    // belum lunas, bukan refund, dan (kasir ATAU pesanan QR yang SUDAH
    // dikonfirmasi). Pesanan QR yang masih menunggu konfirmasi/QRIS TIDAK ikut
    // (diselesaikan per-pesanan) supaya total yang ditagih = yang benar ditutup.
    final settleable = salesAsync.maybeWhen(
      data: (s) => s
          .where(
            (x) =>
                !x.isPaid &&
                !x.isRefunded &&
                !x.isPartiallyRefunded &&
                (x.source == 'kasir' || (x.isFromMenuQr && x.isConfirmed)),
          )
          .toList(),
      orElse: () => const <Sale>[],
    );
    final settleTotal = settleable.fold<double>(0, (s, x) => s + x.total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isOccupied && settleable.isNotEmpty) ...[
          ElevatedButton.icon(
            onPressed: () => _settleAll(context, ref, settleable),
            icon: const Icon(Icons.done_all, size: 18),
            label: Text(
              'Bayar Semua • ${formatRupiah(settleTotal)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kSuccess,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
          const Gap(12),
        ],
        if (isOccupied)
          ElevatedButton.icon(
            onPressed: () {
              // Pilih meja ini di kasir → user bisa lanjut menambah pesanan
              // baru pada meja yang sama.
              ref.read(activeTableProvider.notifier).set(table);
              if (activeOutletId != null) {
                final dineIn = ref
                    .read(orderTypeRepositoryProvider)
                    .getByName('Dine In');
                if (dineIn != null) {
                  ref.read(activeOrderTypeProvider.notifier).set(dineIn);
                }
              }
              salesAsync.whenData((sales) {
                if (sales.isEmpty) return;
                final last = sales.last;
                if (last.customer != null) {
                  ref.read(activeCustomerProvider.notifier).set(last.customer);
                }
              });
              // Pop semua dialog yang menumpuk (TableStatusDialog +
              // mungkin TableManagementPage / TableSelectorSheet di
              // belakangnya) sampai user kembali ke halaman kasir.
              // Tanpa ini, user terjebak di dialog parent dan tidak bisa
              // langsung tambah pesanan di kasir.
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            icon: const Icon(Icons.add_shopping_cart, size: 18),
            label: const Text(
              'Tambah Pesanan Baru',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          )
        else
          ElevatedButton.icon(
            onPressed: () {
              ref.read(activeTableProvider.notifier).set(table);
              if (activeOutletId != null) {
                final dineIn = ref
                    .read(orderTypeRepositoryProvider)
                    .getByName('Dine In');
                if (dineIn != null) {
                  ref.read(activeOrderTypeProvider.notifier).set(dineIn);
                }
              }
              // Sama seperti "Tambah Pesanan Baru": pop sampai ke kasir.
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text(
              'Pilih Meja',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kSuccess,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
        if (isOccupied) ...[
          const Gap(12),
          OutlinedButton.icon(
            onPressed: () => _move(context, ref),
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text(
              'Pindah / Gabung Meja',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              foregroundColor: kPrimary,
              side: BorderSide(color: kPrimary.withValues(alpha: 0.4)),
            ),
          ),
        ],
        const Gap(12),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            foregroundColor: kTextDark,
            side: BorderSide(color: kDivider),
          ),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}

// ─── Status picker (segmented) ────────────────────────────────────────────

/// Tombol segmented untuk override status meja secara manual.
/// Kalau staff men-set "Tersedia" sementara ada transaksi unpaid, kita
/// tampilkan dialog konfirmasi dulu — supaya tidak ada data finansial
/// yang "menggantung" tanpa disengaja.
class _StatusPicker extends ConsumerWidget {
  final PosTable table;
  final AsyncValue<List<Sale>> salesAsync;
  const _StatusPicker({required this.table, required this.salesAsync});

  // Status meja yang dipakai operasional kasir cuma dua: Tersedia / Terisi.
  // Backend masih menerima index 2 (reserved) — disimpan untuk kemungkinan
  // pemakaian feature reservasi di masa depan tanpa migration ulang.
  static const _options = <_StatusOption>[
    _StatusOption(
      index: 0,
      label: 'Tersedia',
      icon: Icons.check_circle,
      color: kSuccess,
    ),
    _StatusOption(
      index: 1,
      label: 'Terisi',
      icon: Icons.event_seat,
      color: kDanger,
    ),
  ];

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    int newStatus,
  ) async {
    if (newStatus == table.statusIndex) return;

    // Set ke Tersedia = sesi tamu di meja ini selesai. Backend akan
    // me-reset rincian pesanan (clear association table_id di semua tx
    // yang nempel ke meja). Minta konfirmasi eksplisit supaya staff
    // sadar tindakannya.
    if (newStatus == 0) {
      final activeCount = salesAsync.maybeWhen(
        data: (sales) => sales.length,
        orElse: () => 0,
      );
      if (activeCount > 0) {
        final unpaidCount = salesAsync.maybeWhen(
          data: (sales) => sales.where((s) => !s.isPaid).length,
          orElse: () => 0,
        );
        final unpaidNote = unpaidCount > 0
            ? '\n\n⚠ Ada $unpaidCount pesanan belum lunas. '
                  'Pesanan tetap tersimpan di Riwayat dan masih bisa '
                  'dilunasi dari sana, hanya saja tidak akan muncul lagi '
                  'di detail meja ini.'
            : '';
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Selesaikan sesi meja ini?'),
            content: Text(
              'Rincian $activeCount pesanan di meja ini akan di-reset '
              '(dilepas dari meja). Lanjutkan?$unpaidNote',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: kDanger),
                child: const Text('Ya, Reset'),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }
    }

    try {
      await ref
          .read(tableRepositoryProvider)
          .updateTableStatus(table.id, newStatus);
      // Invalidate listing meja & active-transactions supaya UI refresh.
      ref.invalidate(tablesFutureProvider);
      ref.invalidate(tableGroupsFutureProvider);
      ref.invalidate(activeTableTransactionsProvider(table.id));
      if (context.mounted) {
        // Tutup dialog detail meja — informasi yang ditampilkan dialog
        // sekarang stale (status, items kalau berubah jadi available).
        // User akan langsung lihat status terbaru di list meja.
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Status ${table.name} diubah ke "${_options.firstWhere((o) => o.index == newStatus).label}"',
            ),
            backgroundColor: kSuccess,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengubah status: $e'),
            backgroundColor: kDanger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ubah Status Meja',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        const Gap(8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kDivider),
          ),
          child: Row(
            children: _options
                .map(
                  (opt) => Expanded(
                    child: _StatusButton(
                      option: opt,
                      isActive: opt.index == table.statusIndex,
                      onTap: () => _apply(context, ref, opt.index),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _StatusOption {
  final int index;
  final String label;
  final IconData icon;
  final Color color;
  const _StatusOption({
    required this.index,
    required this.label,
    required this.icon,
    required this.color,
  });
}

class _StatusButton extends StatelessWidget {
  final _StatusOption option;
  final bool isActive;
  final VoidCallback onTap;
  const _StatusButton({
    required this.option,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? option.color : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                option.icon,
                size: 18,
                color: isActive ? Colors.white : option.color,
              ),
              const Gap(4),
              Text(
                option.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isActive ? Colors.white : kTextDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
