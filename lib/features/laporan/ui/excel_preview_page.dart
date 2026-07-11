import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../transactions/domain/sale.dart';
import '../data/export_service.dart';

/// Halaman preview data yang akan diekspor ke Excel (.xlsx).
/// Menampilkan tabel ringkas (dapat di-scroll horizontal) per seksi
/// sehingga pengguna dapat memeriksa isinya sebelum membagikan file.
class ExcelPreviewPage extends ConsumerStatefulWidget {
  final ReportSummary summary;
  const ExcelPreviewPage({super.key, required this.summary});

  @override
  ConsumerState<ExcelPreviewPage> createState() => _ExcelPreviewPageState();
}

class _ExcelPreviewPageState extends ConsumerState<ExcelPreviewPage> {
  bool _loading = false;

  Future<void> _share() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await ExportService().exportExcel(widget.summary);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.summary;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard,
        surfaceTintColor: Colors.transparent,
        foregroundColor: kTextDark,
        elevation: 0,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Preview ${ref.t('report.export_excel')}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kTextDark,
                ),
              ),
              Text(
                r.periodLabel,
                style: TextStyle(fontSize: 11, color: kTextMid),
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: kSuccess,
                      strokeWidth: 2.5,
                    ),
                  )
                : TextButton.icon(
                    onPressed: _share,
                    icon: const HugeIcon(
                      icon: AppIcons.share,
                      color: kSuccess,
                      size: 16,
                    ),
                    label: Text(
                      ref.t('report.export_excel'),
                      style: const TextStyle(
                        color: kSuccess,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Ringkasan statistik ───────────────────────────────────────
            _SummaryChips(summary: r),
            const Gap(20),

            // ── Rincian transaksi ─────────────────────────────────────────
            if (r.sales.isNotEmpty) ...[
              _SectionHeader(
                label: 'Rincian Transaksi',
                count: r.transactions,
              ),
              const Gap(8),
              _TransactionsTable(sales: r.sales),
              const Gap(20),
            ],

            // ── Kinerja kasir ─────────────────────────────────────────────
            if (r.cashierSummaries.isNotEmpty) ...[
              _SectionHeader(label: 'Kinerja Kasir'),
              const Gap(8),
              _CashierTable(cashiers: r.cashierSummaries),
              const Gap(20),
            ],

            // ── Produk terlaris ───────────────────────────────────────────
            if (r.topProducts.isNotEmpty) ...[
              _SectionHeader(label: 'Produk Terlaris'),
              const Gap(8),
              _TopProductsTable(products: r.topProducts),
              const Gap(24),
            ],

            // ── Tombol bagikan utama ──────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _share,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const HugeIcon(
                        icon: AppIcons.excel,
                        color: Colors.white,
                        size: 20,
                      ),
                label: Text(
                  _loading ? 'Menyiapkan…' : 'Bagikan CSV',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kSuccess,
                  disabledBackgroundColor: kSuccess.withValues(alpha: 0.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Komponen internal
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryChips extends StatelessWidget {
  final ReportSummary summary;
  const _SummaryChips({required this.summary});

  @override
  Widget build(BuildContext context) {
    final stats = [
      (label: 'Pendapatan', value: formatRupiah(summary.revenue), color: kSuccess),
      (label: 'Transaksi', value: '${summary.transactions}', color: kPrimary),
      (label: 'Produk Terjual', value: '${summary.itemsSold}', color: kAccent),
      (
        label: 'Rata-rata',
        value: formatRupiah(summary.average),
        color: const Color(0xFF8B5CF6),
      ),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final s in stats)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: s.color.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.label,
                  style: TextStyle(fontSize: 10, color: kTextMid),
                ),
                const Gap(2),
                Text(
                  s.value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: s.color,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int? count;
  const _SectionHeader({required this.label, this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: kTextDark,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: kPrimary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Tabel bertipe DataTable yang dapat di-scroll ke kanan jika kolom terlalu lebar.
Widget _scrollableTable({
  required List<DataColumn> columns,
  required List<DataRow> rows,
}) {
  return Container(
    decoration: BoxDecoration(
      color: kCard,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: kDivider),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 38,
        dataRowMinHeight: 38,
        dataRowMaxHeight: 46,
        horizontalMargin: 14,
        columnSpacing: 20,
        headingTextStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: kTextDark,
        ),
        dataTextStyle: TextStyle(fontSize: 11, color: kTextDark),
        headingRowColor: WidgetStateProperty.all(kBg),
        columns: columns,
        rows: rows,
      ),
    ),
  );
}

class _TransactionsTable extends StatelessWidget {
  final List<Sale> sales;
  const _TransactionsTable({required this.sales});

  @override
  Widget build(BuildContext context) {
    return _scrollableTable(
      columns: const [
        DataColumn(label: Text('ID')),
        DataColumn(label: Text('Tanggal')),
        DataColumn(label: Text('Kasir')),
        DataColumn(label: Text('Metode')),
        DataColumn(label: Text('Qty'), numeric: true),
        DataColumn(label: Text('Total'), numeric: true),
      ],
      rows: [
        for (final s in sales)
          DataRow(cells: [
            DataCell(Text('#${s.id.toString().padLeft(3, '0')}')),
            DataCell(Text(formatDateTime(s.createdAt))),
            DataCell(
              SizedBox(
                width: 90,
                child: Text(
                  s.cashierName.isEmpty ? '-' : s.cashierName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            DataCell(Text(s.paymentMethod)),
            DataCell(Text('${s.totalQty}')),
            DataCell(Text(formatRupiah(s.total))),
          ]),
      ],
    );
  }
}

class _CashierTable extends StatelessWidget {
  final List<CashierSummary> cashiers;
  const _CashierTable({required this.cashiers});

  @override
  Widget build(BuildContext context) {
    return _scrollableTable(
      columns: const [
        DataColumn(label: Text('#')),
        DataColumn(label: Text('Kasir')),
        DataColumn(label: Text('Transaksi'), numeric: true),
        DataColumn(label: Text('Qty'), numeric: true),
        DataColumn(label: Text('Rata-rata'), numeric: true),
        DataColumn(label: Text('Omzet'), numeric: true),
      ],
      rows: [
        for (var i = 0; i < cashiers.length; i++)
          DataRow(cells: [
            DataCell(Text('${i + 1}')),
            DataCell(
              SizedBox(
                width: 100,
                child: Text(
                  cashiers[i].cashierName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            DataCell(Text('${cashiers[i].transactions}')),
            DataCell(Text('${cashiers[i].itemsSold}')),
            DataCell(Text(formatRupiah(cashiers[i].average))),
            DataCell(Text(formatRupiah(cashiers[i].revenue))),
          ]),
      ],
    );
  }
}

class _TopProductsTable extends StatelessWidget {
  final List<TopProduct> products;
  const _TopProductsTable({required this.products});

  @override
  Widget build(BuildContext context) {
    return _scrollableTable(
      columns: const [
        DataColumn(label: Text('#')),
        DataColumn(label: Text('Nama')),
        DataColumn(label: Text('SKU')),
        DataColumn(label: Text('Harga'), numeric: true),
        DataColumn(label: Text('Terjual'), numeric: true),
        DataColumn(label: Text('Omzet'), numeric: true),
      ],
      rows: [
        for (var i = 0; i < products.length; i++)
          DataRow(cells: [
            DataCell(Text('${i + 1}')),
            DataCell(
              SizedBox(
                width: 120,
                child: Text(
                  products[i].name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            DataCell(Text(products[i].sku)),
            DataCell(
              Text(
                formatRupiah(
                  products[i].qty > 0
                      ? products[i].revenue / products[i].qty
                      : 0,
                ),
              ),
            ),
            DataCell(Text('${products[i].qty}')),
            DataCell(Text(formatRupiah(products[i].revenue))),
          ]),
      ],
    );
  }
}
