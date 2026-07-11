import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../../core/outlet_scope.dart';
import '../../access_rights/data/access_rights_repository.dart';
import '../../access_rights/domain/permission.dart';
import '../data/laporan_report_service.dart';

/// Laporan Pajak (PPN/PB1) keluaran per masa — untuk pelaporan SPT.
/// Owner memilih rentang tanggal, lalu backend mengagregasi pajak/service
/// per bulan (masa). Hanya transaksi LUNAS yang dihitung. DPP = bruto − pajak
/// − service.
class TaxReportPage extends HookConsumerWidget {
  const TaxReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ── Permission gate (owner-facing) ──
    if (!ref.hasPermission(Permission.viewReports)) {
      return Scaffold(
        backgroundColor: kBg,
        appBar: _appBar(context),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HugeIcon(
                  icon: AppIcons.accessRights,
                  color: kDanger,
                  size: 32,
                ),
                const Gap(12),
                Text(
                  ref.t('access_rights.no_access'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: kTextDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final now = DateTime.now();
    // Default: awal tahun berjalan sampai hari ini (mencakup semua masa
    // tahun ini). Konsisten dengan cara laporan lain memakai rentang tanggal.
    final range = useState<DateTimeRange>(
      DateTimeRange(start: DateTime(now.year, 1, 1), end: now),
    );

    final outletId = ref.watch(activeOutletIdProvider) ?? '';
    final from = formatIsoDate(range.value.start);
    final to = formatIsoDate(range.value.end);
    final reportAsync = ref.watch(
      taxPeriodProvider((outletId: outletId, from: from, to: to)),
    );

    Future<void> pickRange() async {
      final picked = await showDateRangePicker(
        context: context,
        initialDateRange: range.value,
        firstDate: DateTime(2024),
        lastDate: DateTime(now.year + 1, 12, 31),
        helpText: 'Pilih Rentang Masa Pajak',
        saveText: 'Terapkan',
      );
      if (picked != null) range.value = picked;
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: _appBar(context),
      body: SafeArea(
        child: RefreshIndicator(
          color: kPrimary,
          onRefresh: () async {
            ref.invalidate(
              taxPeriodProvider((outletId: outletId, from: from, to: to)),
            );
            await Future.delayed(const Duration(milliseconds: 400));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              // ── Rentang tanggal ──
              _RangePill(
                label: '${formatShortDate(range.value.start)} — '
                    '${formatShortDate(range.value.end)}',
                onTap: pickRange,
              ),
              const Gap(8),
              // Catatan halus: dasar penghitungan hanya transaksi LUNAS.
              Row(
                children: [
                  HugeIcon(
                    icon: AppIcons.alertCircle,
                    color: kTextMid,
                    size: 13,
                  ),
                  const Gap(6),
                  Expanded(
                    child: Text(
                      'Hanya transaksi LUNAS yang dihitung. '
                      'DPP = Bruto − Pajak − Service.',
                      style: TextStyle(
                        fontSize: 11,
                        color: kTextMid,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(16),
              reportAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const HugeIcon(
                          icon: AppIcons.alertCircle,
                          color: kDanger,
                          size: 36,
                        ),
                        const Gap(12),
                        Text(
                          'Gagal memuat laporan pajak',
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
                          onPressed: () => ref.invalidate(
                            taxPeriodProvider(
                              (outletId: outletId, from: from, to: to),
                            ),
                          ),
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (report) => report.rows.isEmpty
                    ? const _EmptyState()
                    : _TaxTable(report: report),
              ),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _appBar(BuildContext context) {
    return AppBar(
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
            'Laporan Pajak (PPN/PB1)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: kTextDark,
            ),
          ),
          Text(
            'Keluaran per masa untuk SPT',
            style: TextStyle(
              fontSize: 11,
              color: kTextMid,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ubah "YYYY-MM" menjadi label bulan berlokal, mis. "Mei 2026".
String _periodLabel(String period) {
  final parts = period.split('-');
  if (parts.length >= 2) {
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y != null && m != null && m >= 1 && m <= 12) {
      return formatMonthYear(DateTime(y, m));
    }
  }
  return period;
}

class _RangePill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _RangePill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kDivider),
        ),
        child: Row(
          children: [
            const HugeIcon(icon: AppIcons.event, color: kPrimary, size: 18),
            const Gap(10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: kTextDark,
                ),
              ),
            ),
            HugeIcon(icon: AppIcons.chevronRight, color: kTextMid, size: 16),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: HugeIcon(
                  icon: AppIcons.percent,
                  color: kTextMid,
                  size: 28,
                ),
              ),
            ),
            const Gap(12),
            Text(
              'Belum ada data pajak\npada rentang ini.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kTextMid, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tabel masa pajak (scroll horizontal di layar sempit) + baris total.
class _TaxTable extends StatelessWidget {
  final TaxPeriodReport report;
  const _TaxTable({required this.report});

  static const double _wMasa = 96;
  static const double _wMoney = 118;
  static const double _wTrx = 56;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              color: kPrimary.withValues(alpha: 0.06),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: const [
                  _HeadCell('Masa', width: _wMasa, alignEnd: false),
                  _HeadCell('DPP', width: _wMoney),
                  _HeadCell('Pajak', width: _wMoney),
                  _HeadCell('Service', width: _wMoney),
                  _HeadCell('Bruto', width: _wMoney),
                  _HeadCell('Trx', width: _wTrx),
                ],
              ),
            ),
            Divider(height: 1, color: kDivider),
            // Baris data
            for (int i = 0; i < report.rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: kDivider),
              _DataRow(row: report.rows[i]),
            ],
            Divider(height: 1, color: kDivider),
            // Baris total
            Container(
              color: kPrimary.withValues(alpha: 0.04),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                children: [
                  const _BodyCell(
                    'TOTAL',
                    width: _wMasa,
                    alignEnd: false,
                    bold: true,
                  ),
                  _BodyCell(
                    formatRupiah(report.totalDpp),
                    width: _wMoney,
                    bold: true,
                  ),
                  _BodyCell(
                    formatRupiah(report.totalTax),
                    width: _wMoney,
                    bold: true,
                  ),
                  _BodyCell(
                    formatRupiah(report.totalService),
                    width: _wMoney,
                    bold: true,
                  ),
                  _BodyCell(
                    formatRupiah(report.totalGross),
                    width: _wMoney,
                    bold: true,
                  ),
                  _BodyCell(
                    '${report.totalTx}',
                    width: _wTrx,
                    bold: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final TaxPeriodRow row;
  const _DataRow({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          _BodyCell(
            _periodLabel(row.period),
            width: _TaxTable._wMasa,
            alignEnd: false,
            bold: true,
          ),
          _BodyCell(formatRupiah(row.dpp), width: _TaxTable._wMoney),
          _BodyCell(formatRupiah(row.tax), width: _TaxTable._wMoney),
          _BodyCell(formatRupiah(row.service), width: _TaxTable._wMoney),
          _BodyCell(formatRupiah(row.gross), width: _TaxTable._wMoney),
          _BodyCell('${row.txCount}', width: _TaxTable._wTrx),
        ],
      ),
    );
  }
}

class _HeadCell extends StatelessWidget {
  final String label;
  final double width;
  final bool alignEnd;
  const _HeadCell(this.label, {required this.width, this.alignEnd = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: kTextMid,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  final String text;
  final double width;
  final bool alignEnd;
  final bool bold;
  const _BodyCell(
    this.text, {
    required this.width,
    this.alignEnd = true,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: kTextDark,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
