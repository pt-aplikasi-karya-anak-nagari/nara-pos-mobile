import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/format.dart';
import '../data/shift_repository.dart';
import '../domain/z_report.dart';

/// Halaman Z-Report (Laporan Tutup Shift) untuk sebuah shift.
/// Menampilkan info shift, rincian pembayaran per metode, dan total
/// penjualan bruto/refund/neto/pajak/service/diskon. Angka diagregasi di
/// backend (GET /shifts/:id/z-report) supaya konsisten dengan web.
class ZReportPage extends ConsumerWidget {
  final String shiftId;
  const ZReportPage({super.key, required this.shiftId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(shiftZReportProvider(shiftId));

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        iconTheme: IconThemeData(color: kTextDark),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Z-Report',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kTextDark,
              ),
            ),
            Text(
              'Laporan Tutup Shift',
              style: TextStyle(
                fontSize: 11,
                color: kTextMid,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: kPrimary,
          onRefresh: () async {
            ref.invalidate(shiftZReportProvider(shiftId));
            await Future.delayed(const Duration(milliseconds: 400));
          },
          child: reportAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ListView(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const HugeIcon(
                            icon: AppIcons.alertCircle,
                            color: kDanger,
                            size: 40,
                          ),
                          const Gap(12),
                          Text(
                            'Gagal memuat Z-Report',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: kTextDark,
                            ),
                          ),
                          const Gap(4),
                          Text(
                            '$e',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: kTextMid),
                          ),
                          const Gap(16),
                          OutlinedButton(
                            onPressed: () =>
                                ref.invalidate(shiftZReportProvider(shiftId)),
                            child: const Text('Coba Lagi'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            data: (report) => _ZReportBody(report: report),
          ),
        ),
      ),
    );
  }
}

class _ZReportBody extends StatelessWidget {
  final ZReport report;
  const _ZReportBody({required this.report});

  @override
  Widget build(BuildContext context) {
    final s = report.shift;

    String duration = '-';
    if (s.endTime != null) {
      final diff = s.endTime!.difference(s.startTime);
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      duration = h > 0 ? '${h}j ${m}m' : '${m}m';
    }

    final paymentTotal =
        report.paymentBreakdown.fold<double>(0, (sum, p) => sum + p.amount);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header shift ──
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: kPrimary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: HugeIcon(
                          icon: AppIcons.receipt,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    const Gap(14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.cashierName.isEmpty ? 'Kasir' : s.cashierName,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: kTextDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Shift #${s.remoteId ?? '-'} • ${s.outletRemoteId ?? '-'}',
                            style: TextStyle(fontSize: 12, color: kTextMid),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    _StatusChip(isOpen: s.isOpen),
                  ],
                ),
                const Gap(24),

                // ── Waktu operasional ──
                const _SubHeader(label: 'WAKTU OPERASIONAL'),
                _Card(
                  child: Row(
                    children: [
                      _InfoItem(
                        label: 'Mulai',
                        value: formatDateTime(s.startTime),
                        icon: AppIcons.login,
                      ),
                      const VerticalDivider(),
                      _InfoItem(
                        label: 'Selesai',
                        value: s.endTime != null
                            ? formatDateTime(s.endTime!)
                            : '-',
                        icon: AppIcons.logout,
                      ),
                      const VerticalDivider(),
                      _InfoItem(
                        label: 'Durasi',
                        value: duration,
                        icon: AppIcons.time,
                      ),
                    ],
                  ),
                ),
                const Gap(24),

                // ── Rincian pembayaran ──
                const _SubHeader(label: 'RINCIAN PEMBAYARAN'),
                _Card(
                  child: Column(
                    children: [
                      if (report.paymentBreakdown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Belum ada pembayaran pada shift ini.',
                            style: TextStyle(
                              color: kTextMid,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        )
                      else ...[
                        for (int i = 0;
                            i < report.paymentBreakdown.length;
                            i++) ...[
                          if (i > 0) const Gap(12),
                          _AmountRow(
                            label: _methodLabel(
                              report.paymentBreakdown[i].method,
                            ),
                            value: report.paymentBreakdown[i].amount,
                            icon: _methodIcon(
                              report.paymentBreakdown[i].method,
                            ),
                          ),
                        ],
                        const Divider(height: 32),
                        _AmountRow(
                          label: 'Total Pembayaran',
                          value: paymentTotal,
                          isPrimary: true,
                        ),
                      ],
                    ],
                  ),
                ),
                const Gap(24),

                // ── Ringkasan penjualan ──
                const _SubHeader(label: 'RINGKASAN PENJUALAN'),
                _Card(
                  child: Column(
                    children: [
                      _AmountRow(
                        label: 'Penjualan Bruto',
                        value: report.grossSales,
                      ),
                      const Gap(12),
                      _AmountRow(
                        label: 'Refund',
                        value: report.refundTotal,
                        valueColor: report.refundTotal > 0 ? kDanger : null,
                      ),
                      const Divider(height: 32),
                      _AmountRow(
                        label: 'Penjualan Neto',
                        value: report.netSales,
                        isPrimary: true,
                      ),
                      const Divider(height: 32),
                      _AmountRow(label: 'Pajak', value: report.taxTotal),
                      const Gap(12),
                      _AmountRow(label: 'Service', value: report.serviceTotal),
                      const Gap(12),
                      _AmountRow(label: 'Diskon', value: report.discountTotal),
                      const Divider(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Jumlah Transaksi',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: kTextDark,
                            ),
                          ),
                          Text(
                            '${report.transactionCount}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: kTextDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Gap(24),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Label metode pembayaran (backend kirim lowercase). "lainnya" = other.
String _methodLabel(String method) {
  switch (method.toLowerCase()) {
    case 'tunai':
    case 'cash':
      return 'Tunai';
    case 'qris':
      return 'QRIS';
    case 'kartu':
    case 'card':
    case 'debit':
    case 'credit':
      return 'Kartu';
    case 'transfer':
      return 'Transfer';
    case 'lainnya':
    case 'other':
      return 'Lainnya';
    default:
      if (method.isEmpty) return 'Lainnya';
      return method[0].toUpperCase() + method.substring(1);
  }
}

IconAsset _methodIcon(String method) {
  switch (method.toLowerCase()) {
    case 'tunai':
    case 'cash':
      return AppIcons.money;
    case 'qris':
      return AppIcons.qrCode;
    case 'kartu':
    case 'card':
    case 'debit':
    case 'credit':
      return AppIcons.creditCard;
    case 'transfer':
      return AppIcons.payment;
    default:
      return AppIcons.payment;
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider),
      ),
      child: child,
    );
  }
}

class _SubHeader extends StatelessWidget {
  final String label;
  const _SubHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: kTextMid,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  final IconAsset icon;

  const _InfoItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(icon: icon, color: kTextMid, size: 14),
              const Gap(6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: kTextMid,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const Gap(4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: kTextDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final double value;
  final bool isPrimary;
  final Color? valueColor;
  final IconAsset? icon;

  const _AmountRow({
    required this.label,
    required this.value,
    this.isPrimary = false,
    this.valueColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              HugeIcon(icon: icon!, color: kTextMid, size: 14),
              const Gap(8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: isPrimary ? 15 : 14,
                fontWeight: isPrimary ? FontWeight.w700 : FontWeight.w500,
                color: isPrimary ? kTextDark : kTextMid,
              ),
            ),
          ],
        ),
        Text(
          formatRupiah(value),
          style: TextStyle(
            fontSize: isPrimary ? 16 : 14,
            fontWeight: isPrimary ? FontWeight.w800 : FontWeight.w700,
            color: valueColor ?? kTextDark,
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool isOpen;
  const _StatusChip({required this.isOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isOpen
            ? kSuccess.withValues(alpha: 0.1)
            : kTextMid.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        isOpen ? 'SHIFT AKTIF' : 'SHIFT SELESAI',
        style: TextStyle(
          color: isOpen ? kSuccess : kTextMid,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
