import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';
import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/format.dart';
import '../data/shift_repository.dart';

class ShiftManagementDialog extends HookConsumerWidget {
  final bool isClosing;
  const ShiftManagementDialog({super.key, this.isClosing = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Force refresh saat dialog dibuka supaya total penjualan tunai
    // mencerminkan transaksi paling baru, bukan cache lama.
    useEffect(() {
      if (isClosing) {
        Future.microtask(() => ref.invalidate(activeShiftProvider));
      }
      return null;
    }, const []);

    final activeShiftAsync = ref.watch(activeShiftProvider);
    final activeShift = activeShiftAsync.value;
    final amountCtrl = useTextEditingController();
    final noteCtrl = useTextEditingController();

    // Saat closing, ambil total penjualan & expected langsung dari backend
    // (sudah dihitung di SQL subquery shift_repository.go).
    final totalSales = activeShift?.totalSales ?? 0.0;
    // Kas masuk/keluar (petty cash) shift ini — dimasukkan ke preview expected
    // supaya konsisten dengan hitungan backend saat close (B7).
    final cashMovements = (isClosing && activeShift?.remoteId != null)
        ? (ref.watch(cashMovementsProvider(activeShift!.remoteId!)).value ??
              const <Map<String, dynamic>>[])
        : const <Map<String, dynamic>>[];
    final cashIn = cashMovements
        .where((m) => m['type'] == 'in')
        .fold<double>(0, (s, m) => s + ((m['amount'] as num?)?.toDouble() ?? 0));
    final cashOut = cashMovements
        .where((m) => m['type'] == 'out')
        .fold<double>(0, (s, m) => s + ((m['amount'] as num?)?.toDouble() ?? 0));
    final expected = isClosing && activeShift != null
        ? (activeShift.startingCash + totalSales + cashIn - cashOut)
        : null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: (isClosing ? kDanger : kSuccess).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: HugeIcon(
                    icon: isClosing ? AppIcons.logout : AppIcons.login,
                    color: isClosing ? kDanger : kSuccess,
                    size: 32,
                  ),
                ),
              ),
              const Gap(16),
              Text(
                isClosing ? 'Tutup Kasir' : 'Buka Kasir',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: kTextDark,
                ),
              ),
              const Gap(8),
              Text(
                isClosing
                    ? 'Masukkan jumlah uang tunai di laci'
                    : 'Masukkan saldo awal uang tunai',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextMid, fontSize: 14),
              ),
              const Gap(24),
              if (isClosing && expected != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _SummaryRow(
                        label: 'Saldo Awal',
                        value: activeShift!.startingCash,
                      ),
                      _SummaryRow(
                        label: 'Total Penjualan (Tunai)',
                        value: totalSales,
                      ),
                      if (cashIn > 0)
                        _SummaryRow(label: 'Kas Masuk', value: cashIn, valueColor: kSuccess),
                      if (cashOut > 0)
                        _SummaryRow(label: 'Kas Keluar', value: -cashOut, valueColor: kDanger),
                      Divider(height: 24, color: kDivider),
                      _SummaryRow(
                        label: 'Ekspektasi Kas',
                        value: expected,
                        isBold: true,
                        valueColor: kPrimary,
                      ),
                    ],
                  ),
                ),
                const Gap(20),
              ],
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: kTextDark,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'Rp 0',
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: kDivider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: kDivider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: kPrimary, width: 2.0),
                  ),
                ),
                onChanged: (v) {
                  final s = formatRupiah(parseRupiahInput(v));
                  amountCtrl.value = amountCtrl.value.copyWith(
                    text: s,
                    selection: TextSelection.collapsed(offset: s.length),
                  );
                },
              ),
              const Gap(16),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: isClosing
                      ? 'Catatan (opsional)'
                      : 'Keterangan Modal (Uang receh, dll) *Wajib',
                  filled: true,
                  fillColor: kBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Colors.transparent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Colors.transparent),
                  ),
                ),
              ),
              const Gap(24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Batal',
                        style: TextStyle(color: kTextMid),
                      ),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          final val = parseRupiahInput(
                            amountCtrl.text,
                          ).toDouble();

                          if (!isClosing && noteCtrl.text.trim().isEmpty) {
                            throw 'Keterangan modal wajib diisi';
                          }

                          if (isClosing) {
                            await ref
                                .read(activeShiftProvider.notifier)
                                .close(val, noteCtrl.text);
                            if (context.mounted) {
                              Navigator.pop(context);
                              _showShiftSummary(context, expected!, val);
                            }
                          } else {
                            await ref
                                .read(activeShiftProvider.notifier)
                                .open(val, noteCtrl.text);
                            if (context.mounted) Navigator.pop(context);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.toString().replaceAll('Exception: ', ''),
                                ),
                                backgroundColor: kDanger,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isClosing ? kDanger : kSuccess,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        isClosing ? 'Tutup Kasir' : 'Buka Kasir',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showShiftSummary(BuildContext context, double expected, double actual) {
    // Selisih = aktual − ekspektasi. Positif → kas lebih (over),
    // negatif → kas kurang (short), nol → pas.
    final diff = actual - expected;
    final isExact = diff.abs() < 0.5; // toleransi pembulatan rupiah
    final isOver = diff > 0;
    final Color diffColor = isExact
        ? kSuccess
        : isOver
        ? kPrimary
        : kDanger;
    final String diffLabel = isExact
        ? 'Kas Sesuai'
        : isOver
        ? 'Selisih Lebih (Over)'
        : 'Selisih Kurang (Short)';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isExact
                  ? Icons.check_circle_rounded
                  : Icons.info_outline_rounded,
              color: diffColor,
            ),
            const Gap(8),
            const Expanded(
              child: Text(
                'Ringkasan Tutup Kasir',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SummaryRow(label: 'Kas Diharapkan', value: expected),
            const Gap(8),
            _SummaryRow(label: 'Kas Aktual (dihitung)', value: actual),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
            _SummaryRow(
              label: diffLabel,
              value: diff.abs(),
              valueColor: diffColor,
              isBold: true,
            ),
            if (!isExact) ...[
              const Gap(10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: diffColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isOver
                      ? 'Kas fisik lebih besar dari yang diharapkan. Pastikan tidak ada transaksi yang belum tercatat.'
                      : 'Kas fisik lebih kecil dari yang diharapkan. Periksa kembali pengeluaran atau kembalian.',
                  style: TextStyle(fontSize: 12, color: kTextMid, height: 1.4),
                ),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final Color? valueColor;
  final bool isBold;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: kTextMid)),
          Text(
            formatRupiah(value),
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? kTextDark,
            ),
          ),
        ],
      ),
    );
  }
}
