import 'package:fl_chart/fl_chart.dart';
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
import '../../../core/responsive.dart';
import '../../access_rights/data/access_rights_repository.dart';
import '../../access_rights/domain/permission.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/sale.dart';
import '../data/export_service.dart';
import '../data/laporan_report_service.dart';
import 'excel_preview_page.dart';
import 'pdf_preview_page.dart';
import 'tax_report_page.dart';

enum _Period { harian, bulanan, tahunan }

const _monthNames = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

class LaporanPage extends HookConsumerWidget {
  const LaporanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTablet = context.isTablet;
    // ── Permission gate ──
    if (!ref.hasPermission(Permission.viewReports)) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: kDanger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: HugeIcon(
                      icon: AppIcons.accessRights,
                      color: kDanger,
                      size: 32,
                    ),
                  ),
                ),
                const Gap(16),
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

    final salesAsync = ref.watch(salesFutureProvider);
    final period = useState(_Period.bulanan);
    final anchor = useState(DateTime.now());

    // Angka headline (revenue/transaksi/item) dari agregasi SERVER supaya
    // konsisten dengan web (C3). Null saat loading/offline → fallback ke
    // agregasi klien di bawah. Daftar transaksi tetap dari klien untuk export.
    final reportRange = _rangeFor(period.value, anchor.value);
    final reportOutletId = ref.watch(activeOutletIdProvider);
    final serverSummary = ref
        .watch(serverSummaryProvider((
          outletId: reportOutletId ?? '',
          from: reportRange.from,
          to: reportRange.to,
        )))
        .value;

    void shift(int delta) {
      final d = anchor.value;
      switch (period.value) {
        case _Period.harian:
          anchor.value = d.add(Duration(days: delta));
        case _Period.bulanan:
          anchor.value = DateTime(d.year, d.month + delta, 1);
        case _Period.tahunan:
          anchor.value = DateTime(d.year + delta, 1, 1);
      }
    }

    // Mobile: hilangkan shell rounded (sama dengan RiwayatPage di mobile,
    // background transparan dari gradient ShellPage). Tablet: bungkus
    // rounded white container — pola yang sama dengan riwayat & notifikasi.
    final shellMargin = isTablet
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 16)
        : EdgeInsets.zero;
    final shellRadius = isTablet ? 16.0 : 0.0;
    final clipRadius = isTablet ? 32.0 : 0.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Container(
          margin: shellMargin,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(shellRadius),
            color: isTablet ? Colors.white : Colors.transparent,
          ),
          child: RefreshIndicator(
            color: kPrimary,
            onRefresh: () async {
              ref.invalidate(salesFutureProvider);
              await Future.delayed(const Duration(milliseconds: 400));
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(clipRadius),
              child: salesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (sales) {
                  final filtered = _filter(
                    sales,
                    period.value,
                    anchor.value,
                  ).where((s) => !s.isRefunded).toList();
                  // Agregasi klien (fallback offline / detail export).
                  final clientRevenue = filtered.fold(0.0, (s, x) => s + x.total);
                  final clientCount = filtered.length;
                  final clientItems = filtered.fold(0, (s, x) => s + x.totalQty);
                  final clientDiscounts = filtered.fold(
                    0.0,
                    (s, x) => s + x.discountTotal,
                  );
                  // Prioritaskan angka server (konsisten dgn web); fallback klien.
                  final revenue = serverSummary?.revenue ?? clientRevenue;
                  final count = serverSummary?.transactions ?? clientCount;
                  final items = serverSummary?.itemsSold ?? clientItems;
                  final discounts = serverSummary?.discountTotal ?? clientDiscounts;
                  final avg = serverSummary?.average ??
                      (clientCount > 0 ? clientRevenue / clientCount : 0.0);

                  final discountMap = <String, DiscountBreakdown>{};
                  for (final s in filtered) {
                    for (final it in s.items) {
                      if (it.discountAmount > 0) {
                        final key = '${it.discountName}|${it.discountLabel}';
                        final prev = discountMap[key];
                        if (prev == null) {
                          discountMap[key] = DiscountBreakdown(
                            name: it.discountName.isEmpty
                                ? 'Diskon Tanpa Nama'
                                : it.discountName,
                            label: it.discountLabel,
                            amount: it.discountAmount,
                          );
                        } else {
                          discountMap[key] = DiscountBreakdown(
                            name: prev.name,
                            label: prev.label,
                            amount: prev.amount + it.discountAmount,
                          );
                        }
                      }
                    }
                  }

                  Future<void> openExport() async {
                    final summary = ReportSummary(
                      periodLabel: _labelFor(period.value, anchor.value),
                      revenue: revenue,
                      transactions: count,
                      itemsSold: items,
                      average: avg,
                      discountTotal: discounts,
                      discountBreakdown: discountMap,
                      sales: filtered,
                    );
                    await _showExportSheet(context, ref, summary);
                  }

                  final statCards = [
                    _StatCard(
                      ref.t('report.revenue'),
                      formatRupiah(revenue),
                      AppIcons.trendingUp,
                      kSuccess,
                    ),
                    _StatCard(
                      ref.t('report.transactions'),
                      '$count',
                      AppIcons.receipt,
                      kPrimary,
                    ),
                    _StatCard(
                      ref.t('report.items_sold'),
                      '$items',
                      AppIcons.inventory,
                      kAccent,
                    ),
                    _StatCard(
                      ref.t('report.average'),
                      formatRupiah(avg),
                      AppIcons.barChart,
                      const Color(0xFF8B5CF6),
                    ),
                    _StatCard(
                      'Total Diskon',
                      formatRupiah(discounts),
                      AppIcons.discount,
                      kDanger,
                    ),
                  ];
                  final statColumns = context.responsive<int>(
                    compact: 2,
                    medium: 3,
                    expanded: 6,
                    large: 6,
                  );
                  final horizontalPad = context.responsive<double>(
                    compact: 20,
                    medium: 24,
                    expanded: 28,
                    large: 32,
                  );

                  if (isTablet) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left Panel: Controls & Filters
                        Expanded(
                          flex: 1,
                          child: Container(
                            color: kBg,
                            child: ListView(
                              children: [
                                Gap(24),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32.0,
                                  ),
                                  child: Text(
                                    ref.t('report.title'),
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: kTextDark,
                                    ),
                                  ),
                                ),
                                const Gap(16),
                                const Gap(16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32.0,
                                  ),
                                  child: Text(
                                    'Periode Laporan',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: kTextMid,
                                    ),
                                  ),
                                ),
                                const Gap(8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32.0,
                                  ),
                                  child: _PeriodTabs(
                                    value: period.value,
                                    labels: {
                                      _Period.harian: ref.t('report.daily'),
                                      _Period.bulanan: ref.t('report.monthly'),
                                      _Period.tahunan: ref.t('report.yearly'),
                                    },
                                    onChanged: (p) {
                                      period.value = p;
                                      anchor.value = DateTime.now();
                                    },
                                  ),
                                ),
                                const Gap(8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32.0,
                                  ),
                                  child: _DateNavigator(
                                    label: _labelFor(
                                      period.value,
                                      anchor.value,
                                    ),
                                    onPrev: () => shift(-1),
                                    onNext: () => shift(1),
                                  ),
                                ),
                                const Gap(16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32.0,
                                  ),
                                  child: GestureDetector(
                                    onTap: openExport,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: kPrimary,
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: [
                                          BoxShadow(
                                            color: kPrimary.withValues(
                                              alpha: 0.3,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const HugeIcon(
                                            icon: AppIcons.download,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const Gap(8),
                                          Text(
                                            ref.t('report.export'),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const Gap(12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32.0,
                                  ),
                                  child: _TaxReportTile(
                                    onTap: () => _openTaxReport(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        VerticalDivider(width: 1, color: kDivider),
                        // Right Panel: Data & Charts
                        Expanded(
                          flex: 2,
                          child: Container(
                            color: Colors.white,
                            child: count == 0
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(24),
                                          decoration: BoxDecoration(
                                            color: kBg,
                                            shape: BoxShape.circle,
                                          ),
                                          child: HugeIcon(
                                            icon: AppIcons.barChart,
                                            color: kTextLight,
                                            size: 48,
                                          ),
                                        ),
                                        const Gap(20),
                                        Text(
                                          'Belum ada data transaksi\npada periode ini.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: kTextMid,
                                            fontSize: 15,
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView(
                                    padding: const EdgeInsets.all(32),
                                    children: [
                                      _StatGrid(
                                        columns: statColumns,
                                        children: statCards,
                                      ),
                                      const Gap(32),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: _TopProductsSection(
                                              title: ref.t(
                                                'report.top_products',
                                              ),
                                              qtyLabel: ref.t(
                                                'report.qty_sold',
                                              ),
                                              products: computeTopProducts(
                                                filtered,
                                                limit: 5,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 24),
                                          Expanded(
                                            child: _CashierSection(
                                              title: ref.t(
                                                'report.cashier_performance',
                                              ),
                                              trxLabel: ref.t(
                                                'report.cashier_trx',
                                              ),
                                              emptyLabel: ref.t(
                                                'report.cashier_empty',
                                              ),
                                              cashiers: computeCashierSummaries(
                                                filtered,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Gap(32),
                                      _DiscountSection(discounts: discountMap),
                                      const Gap(32),
                                      _Breakdown(
                                        period: period.value,
                                        sales: filtered,
                                        anchor: anchor.value,
                                        titles: {
                                          _Period.harian: ref.t(
                                            'report.per_hour',
                                          ),
                                          _Period.bulanan: ref.t(
                                            'report.per_day',
                                          ),
                                          _Period.tahunan: ref.t(
                                            'report.per_month',
                                          ),
                                        },
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    );
                  }

                  // Mobile: header card putih (title + tombol export) di
                  // atas, lalu konten scrollable di bawah. Pola sama dengan
                  // RiwayatPage di mobile (header tetap di atas, list scroll
                  // di bawahnya).
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                ref.t('report.title'),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: kTextDark,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: openExport,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: kPrimary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const HugeIcon(
                                      icon: AppIcons.download,
                                      color: kPrimary,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      ref.t('report.export'),
                                      style: const TextStyle(
                                        color: kPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Gap(8),
                      Expanded(
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            horizontalPad,
                            8,
                            horizontalPad,
                            20,
                          ),
                          children: [
                            ContentConstrained(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _PeriodTabs(
                              value: period.value,
                              labels: {
                                _Period.harian: ref.t('report.daily'),
                                _Period.bulanan: ref.t('report.monthly'),
                                _Period.tahunan: ref.t('report.yearly'),
                              },
                              onChanged: (p) {
                                period.value = p;
                                anchor.value = DateTime.now();
                              },
                            ),
                            const Gap(8),
                            _DateNavigator(
                              label: _labelFor(period.value, anchor.value),
                              onPrev: () => shift(-1),
                              onNext: () => shift(1),
                            ),
                            const Gap(16),
                            _TaxReportTile(
                              onTap: () => _openTaxReport(context),
                            ),
                            const Gap(16),
                            _StatGrid(
                              columns: statColumns,
                              children: statCards,
                            ),
                            const Gap(16),
                            if (count > 0) ...[
                              if (context.isWide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _TopProductsSection(
                                        title: ref.t('report.top_products'),
                                        qtyLabel: ref.t('report.qty_sold'),
                                        products: computeTopProducts(
                                          filtered,
                                          limit: 5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _CashierSection(
                                        title: ref.t(
                                          'report.cashier_performance',
                                        ),
                                        trxLabel: ref.t('report.cashier_trx'),
                                        emptyLabel: ref.t(
                                          'report.cashier_empty',
                                        ),
                                        cashiers: computeCashierSummaries(
                                          filtered,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              else ...[
                                _TopProductsSection(
                                  title: ref.t('report.top_products'),
                                  qtyLabel: ref.t('report.qty_sold'),
                                  products: computeTopProducts(
                                    filtered,
                                    limit: 5,
                                  ),
                                ),
                                const Gap(16),
                                _CashierSection(
                                  title: ref.t('report.cashier_performance'),
                                  trxLabel: ref.t('report.cashier_trx'),
                                  emptyLabel: ref.t('report.cashier_empty'),
                                  cashiers: computeCashierSummaries(filtered),
                                ),
                              ],
                              const Gap(16),
                              _DiscountSection(discounts: discountMap),
                              const Gap(16),
                            ],
                            if (count > 0)
                              _Breakdown(
                                period: period.value,
                                sales: filtered,
                                anchor: anchor.value,
                                titles: {
                                  _Period.harian: ref.t('report.per_hour'),
                                  _Period.bulanan: ref.t('report.per_day'),
                                  _Period.tahunan: ref.t('report.per_month'),
                                },
                              ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static List<Sale> _filter(List<Sale> sales, _Period p, DateTime a) {
    return sales.where((s) {
      final d = s.createdAt;
      switch (p) {
        case _Period.harian:
          return d.year == a.year && d.month == a.month && d.day == a.day;
        case _Period.bulanan:
          return d.year == a.year && d.month == a.month;
        case _Period.tahunan:
          return d.year == a.year;
      }
    }).toList();
  }

  // Rentang tanggal (YYYY-MM-DD) untuk query agregasi server (C3).
  static ({String from, String to}) _rangeFor(_Period p, DateTime a) {
    String d(DateTime x) =>
        '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    switch (p) {
      case _Period.harian:
        return (from: d(a), to: d(a));
      case _Period.bulanan:
        return (from: d(DateTime(a.year, a.month, 1)), to: d(DateTime(a.year, a.month + 1, 0)));
      case _Period.tahunan:
        return (from: d(DateTime(a.year, 1, 1)), to: d(DateTime(a.year, 12, 31)));
    }
  }

  static String _labelFor(_Period p, DateTime d) {
    switch (p) {
      case _Period.harian:
        return '${d.day} ${_monthNames[d.month - 1]} ${d.year}';
      case _Period.bulanan:
        return '${_monthNames[d.month - 1]} ${d.year}';
      case _Period.tahunan:
        return '${d.year}';
    }
  }
}

void _openTaxReport(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(builder: (_) => const TaxReportPage()),
  );
}

/// Tombol menuju layar Laporan Pajak (PPN/PB1). Dipakai di panel tablet
/// maupun konten mobile pada Laporan.
class _TaxReportTile extends StatelessWidget {
  final VoidCallback onTap;
  const _TaxReportTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kDivider),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: HugeIcon(
                  icon: AppIcons.percent,
                  color: kPrimary,
                  size: 18,
                ),
              ),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Laporan Pajak (PPN/PB1)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kTextDark,
                    ),
                  ),
                  Text(
                    'Keluaran per masa untuk SPT',
                    style: TextStyle(fontSize: 11, color: kTextMid),
                  ),
                ],
              ),
            ),
            HugeIcon(icon: AppIcons.chevronRight, color: kTextMid, size: 16),
          ],
        ),
      ),
    );
  }
}

Future<void> _showExportSheet(
  BuildContext context,
  WidgetRef ref,
  ReportSummary summary,
) async {
  final hasData = summary.sales.isNotEmpty;
  // Simpan navigator sebelum sheet mungkin menutup context.
  final nav = Navigator.of(context, rootNavigator: true);

  await showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(ctx).padding.bottom + 16,
      ),
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
          Text(
            ref.t('report.export_title'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: kTextDark,
            ),
          ),
          const Gap(4),
          Text(
            summary.periodLabel,
            style: TextStyle(fontSize: 12, color: kTextMid),
          ),
          const Gap(8),
          // Keterangan alur: pilih format → preview → bagikan
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const HugeIcon(
                  icon: AppIcons.receipt,
                  color: kPrimary,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Text(
                  'Pilih format → preview → bagikan',
                  style: const TextStyle(
                    fontSize: 11,
                    color: kPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Gap(16),
          if (!hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                ref.t('report.empty'),
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextMid, fontSize: 13),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _ExportOption(
                    icon: AppIcons.pdf,
                    label: ref.t('report.export_pdf'),
                    sublabel: 'Preview lalu bagikan',
                    color: kDanger,
                    onTap: () {
                      Navigator.pop(ctx);
                      nav.push(
                        MaterialPageRoute(
                          builder: (_) => PdfPreviewPage(summary: summary),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ExportOption(
                    icon: AppIcons.excel,
                    label: ref.t('report.export_excel'),
                    sublabel: 'Preview lalu bagikan',
                    color: kSuccess,
                    onTap: () {
                      Navigator.pop(ctx);
                      nav.push(
                        MaterialPageRoute(
                          builder: (_) => ExcelPreviewPage(summary: summary),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

// ReportSummary is now used from export_service.dart

class _ExportOption extends StatelessWidget {
  final IconAsset icon;
  final String label;
  final String? sublabel;
  final Color color;
  final VoidCallback onTap;
  const _ExportOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            HugeIcon(icon: icon, color: color, size: 28),
            const Gap(8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color,
                fontSize: 13,
              ),
            ),
            if (sublabel != null) ...[
              const Gap(3),
              Text(
                sublabel!,
                style: TextStyle(fontSize: 10, color: kTextMid),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PeriodTabs extends StatelessWidget {
  final _Period value;
  final Map<_Period, String> labels;
  final ValueChanged<_Period> onChanged;

  const _PeriodTabs({
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = _Period.values;
    final index = items.indexOf(value);

    return Container(
      height: 50,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / items.length;

          return Stack(
            children: [
              /// 🔥 Sliding Indicator
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                left: index * width,
                top: 0,
                bottom: 0,
                width: width,
                child: Container(
                  decoration: BoxDecoration(
                    color: kPrimary,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),

              /// 🔹 Tabs
              Row(
                children: items.map((p) {
                  final selected = p == value;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onChanged(p),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            color: selected ? Colors.white : kTextMid,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          child: Text(labels[p]!),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DateNavigator extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _DateNavigator({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrev,
            icon: HugeIcon(icon: AppIcons.chevronLeft, color: kTextDark),
          ),
          Expanded(
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: kTextDark,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: HugeIcon(icon: AppIcons.chevronRight, color: kTextDark),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconAsset icon;
  final Color color;
  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$label: $value',
      triggerMode: TooltipTriggerMode.longPress,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: HugeIcon(icon: icon, color: color, size: 18),
              ),
            ),
            const Gap(10),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: kTextDark,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: kTextMid),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Responsive grid for stat cards: 2 columns on phone, 4 on tablet.
class _DiscountSection extends StatelessWidget {
  final Map<String, DiscountBreakdown> discounts;
  const _DiscountSection({required this.discounts});

  @override
  Widget build(BuildContext context) {
    if (discounts.isEmpty) return const SizedBox.shrink();
    final items = discounts.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rincian Diskon',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: kTextDark,
          ),
        ),
        const Gap(12),
        Container(
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kDivider),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: kDivider),
            itemBuilder: (context, index) {
              final d = items[index];
              return Tooltip(
                message:
                    '${d.name} (Potongan ${d.label}): -${formatRupiah(d.amount)}',
                triggerMode: TooltipTriggerMode.longPress,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: kDanger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: HugeIcon(
                            icon: AppIcons.discount,
                            color: kDanger,
                            size: 18,
                          ),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kTextDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Potongan ${d.label}',
                              style: TextStyle(fontSize: 11, color: kTextMid),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '-${formatRupiah(d.amount)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kDanger,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatGrid extends StatelessWidget {
  final int columns;
  final List<Widget> children;
  const _StatGrid({required this.columns, required this.children});

  @override
  Widget build(BuildContext context) {
    const spacing = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final c in children) SizedBox(width: cellWidth, child: c),
          ],
        );
      },
    );
  }
}

// ReportSummary and DiscountBreakdown are now used from export_service.dart

class _Breakdown extends StatelessWidget {
  final _Period period;
  final List<Sale> sales;
  final DateTime anchor;
  final Map<_Period, String> titles;
  const _Breakdown({
    required this.period,
    required this.sales,
    required this.anchor,
    required this.titles,
  });

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    if (rows.isEmpty) return const SizedBox.shrink();
    final maxRevenue = rows.fold(0.0, (m, r) => r.revenue > m ? r.revenue : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titles[period] ?? '',
          style: TextStyle(fontWeight: FontWeight.w700, color: kTextDark),
        ),
        const Gap(10),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 10),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(14),
          ),
          child: SizedBox(
            height: 200,
            child: _RevenueBarChart(rows: rows, maxRevenue: maxRevenue),
          ),
        ),
        const Gap(12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                if (i > 0) const Gap(10),
                _BreakdownRow(
                  label: rows[i].label,
                  revenue: rows[i].revenue,
                  maxRevenue: maxRevenue,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<({String label, double revenue})> _rows() {
    switch (period) {
      case _Period.harian:
        final buckets = <int, double>{};
        for (final s in sales) {
          buckets.update(
            s.createdAt.hour,
            (v) => v + s.total,
            ifAbsent: () => s.total,
          );
        }
        final keys = buckets.keys.toList()..sort();
        return [
          for (final h in keys)
            (label: '${h.toString().padLeft(2, '0')}:00', revenue: buckets[h]!),
        ];
      case _Period.bulanan:
        final buckets = <int, double>{};
        for (final s in sales) {
          buckets.update(
            s.createdAt.day,
            (v) => v + s.total,
            ifAbsent: () => s.total,
          );
        }
        final keys = buckets.keys.toList()..sort();
        return [
          for (final d in keys)
            (
              label: '$d ${_monthNames[anchor.month - 1].substring(0, 3)}',
              revenue: buckets[d]!,
            ),
        ];
      case _Period.tahunan:
        final buckets = <int, double>{};
        for (final s in sales) {
          buckets.update(
            s.createdAt.month,
            (v) => v + s.total,
            ifAbsent: () => s.total,
          );
        }
        final keys = buckets.keys.toList()..sort();
        return [
          for (final m in keys)
            (label: _monthNames[m - 1], revenue: buckets[m]!),
        ];
    }
  }
}

class _RevenueBarChart extends StatelessWidget {
  final List<({String label, double revenue})> rows;
  final double maxRevenue;
  const _RevenueBarChart({required this.rows, required this.maxRevenue});

  @override
  Widget build(BuildContext context) {
    final maxY = maxRevenue <= 0 ? 1.0 : maxRevenue * 1.15;
    final step = rows.length > 8 ? (rows.length / 6).ceil() : 1;
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => kTextDark,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${rows[group.x].label}\n${formatRupiah(rod.toY)}',
              const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: kDivider, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= rows.length) {
                  return const SizedBox.shrink();
                }
                if (i % step != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    rows[i].label.split(' ').first,
                    style: TextStyle(
                      fontSize: 10,
                      color: kTextMid,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (int i = 0; i < rows.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: rows[i].revenue,
                  color: kPrimary,
                  width: 14,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TopProductsSection extends StatelessWidget {
  final String title;
  final String qtyLabel;
  final List<TopProduct> products;
  const _TopProductsSection({
    required this.title,
    required this.qtyLabel,
    required this.products,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();
    final maxQty = products.fold(0, (m, p) => p.qty > m ? p.qty : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w700, color: kTextDark),
        ),
        const Gap(10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              for (int i = 0; i < products.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1, color: kDivider),
                  ),
                _TopProductRow(
                  rank: i + 1,
                  product: products[i],
                  maxQty: maxQty,
                  qtyLabel: qtyLabel,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TopProductRow extends StatelessWidget {
  final int rank;
  final TopProduct product;
  final int maxQty;
  final String qtyLabel;
  const _TopProductRow({
    required this.rank,
    required this.product,
    required this.maxQty,
    required this.qtyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxQty > 0 ? product.qty / maxQty : 0.0;
    final rankColor = rank == 1
        ? const Color(0xFFF59E0B)
        : rank == 2
        ? const Color(0xFF94A3B8)
        : rank == 3
        ? const Color(0xFFB45309)
        : kTextMid;
    final unit = product.qty > 0 ? product.revenue / product.qty : 0.0;
    final detailText = [
      if (product.sku.isNotEmpty) product.sku,
      '@ ${formatRupiah(unit)}',
      formatRupiah(product.revenue),
    ].join(' · ');

    return Tooltip(
      message: '${product.name}\n$detailText\nTotal: ${product.qty} $qtyLabel',
      triggerMode: TooltipTriggerMode.longPress,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: rankColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: rankColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kTextDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap(2),
                Text(
                  detailText,
                  style: TextStyle(fontSize: 11, color: kTextMid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap(6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 5,
                    backgroundColor: kBg,
                    valueColor: const AlwaysStoppedAnimation<Color>(kPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${product.qty}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kTextDark,
                ),
              ),
              Text(qtyLabel, style: TextStyle(fontSize: 10, color: kTextMid)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CashierSection extends StatelessWidget {
  final String title;
  final String trxLabel;
  final String emptyLabel;
  final List<CashierSummary> cashiers;
  const _CashierSection({
    required this.title,
    required this.trxLabel,
    required this.emptyLabel,
    required this.cashiers,
  });

  @override
  Widget build(BuildContext context) {
    final maxRevenue = cashiers.fold(
      0.0,
      (m, c) => c.revenue > m ? c.revenue : m,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w700, color: kTextDark),
        ),
        const Gap(10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(14),
          ),
          child: cashiers.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      emptyLabel,
                      style: TextStyle(fontSize: 12, color: kTextMid),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (int i = 0; i < cashiers.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(height: 1, color: kDivider),
                        ),
                      _CashierRow(
                        rank: i + 1,
                        cashier: cashiers[i],
                        maxRevenue: maxRevenue,
                        trxLabel: trxLabel,
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _CashierRow extends StatelessWidget {
  final int rank;
  final CashierSummary cashier;
  final double maxRevenue;
  final String trxLabel;
  const _CashierRow({
    required this.rank,
    required this.cashier,
    required this.maxRevenue,
    required this.trxLabel,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxRevenue > 0 ? cashier.revenue / maxRevenue : 0.0;
    final rankColor = rank == 1
        ? const Color(0xFFF59E0B)
        : rank == 2
        ? const Color(0xFF94A3B8)
        : rank == 3
        ? const Color(0xFFB45309)
        : kTextMid;
    final initial = cashier.cashierName.isNotEmpty
        ? cashier.cashierName.characters.first.toUpperCase()
        : '?';
    final detailText =
        '${cashier.transactions} $trxLabel · ${cashier.itemsSold} pcs · Avg ${formatRupiah(cashier.average)}';

    return Tooltip(
      message:
          '${cashier.cashierName}\n$detailText\nTotal: ${formatRupiah(cashier.revenue)}',
      triggerMode: TooltipTriggerMode.longPress,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: rankColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: rankColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: kPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cashier.cashierName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kTextDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap(2),
                Text(
                  detailText,
                  style: TextStyle(fontSize: 11, color: kTextMid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap(6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 5,
                    backgroundColor: kBg,
                    valueColor: const AlwaysStoppedAnimation<Color>(kPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 86,
            child: Text(
              formatRupiah(cashier.revenue),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: kTextDark,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final double revenue;
  final double maxRevenue;
  const _BreakdownRow({
    required this.label,
    required this.revenue,
    required this.maxRevenue,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxRevenue > 0 ? revenue / maxRevenue : 0.0;
    return Tooltip(
      message: '$label: ${formatRupiah(revenue)}',
      triggerMode: TooltipTriggerMode.longPress,
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: kTextMid,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: kBg,
                valueColor: const AlwaysStoppedAnimation<Color>(kPrimary),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(
              formatRupiah(revenue),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: kTextDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
