import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/format.dart';
import '../../transactions/domain/sale.dart';

class TopProduct {
  final String productRemoteId;
  final String name;
  final String sku;
  final int qty;
  final double revenue;
  const TopProduct({
    required this.productRemoteId,
    required this.name,
    required this.sku,
    required this.qty,
    required this.revenue,
  });
}

List<TopProduct> computeTopProducts(List<Sale> sales, {int limit = 10}) {
  final agg = <String, TopProduct>{};
  for (final s in sales) {
    for (final it in s.items) {
      final key = it.productRemoteId.isNotEmpty
          ? 'id:${it.productRemoteId}'
          : 'name:${it.productName}';
      final prev = agg[key];
      if (prev == null) {
        agg[key] = TopProduct(
          productRemoteId: it.productRemoteId,
          name: it.productName,
          sku: it.productSku,
          qty: it.qty,
          revenue: it.subtotal,
        );
      } else {
        agg[key] = TopProduct(
          productRemoteId: prev.productRemoteId,
          name: prev.name,
          sku: prev.sku.isEmpty ? it.productSku : prev.sku,
          qty: prev.qty + it.qty,
          revenue: prev.revenue + it.subtotal,
        );
      }
    }
  }
  final list = agg.values.toList()..sort((a, b) => b.qty.compareTo(a.qty));
  return list.take(limit).toList();
}

class CashierSummary {
  final String cashierId;
  final String cashierName;
  final int transactions;
  final int itemsSold;
  final double revenue;
  const CashierSummary({
    required this.cashierId,
    required this.cashierName,
    required this.transactions,
    required this.itemsSold,
    required this.revenue,
  });

  double get average => transactions > 0 ? revenue / transactions : 0;
}

List<CashierSummary> computeCashierSummaries(List<Sale> sales) {
  final agg = <String, CashierSummary>{};
  for (final s in sales) {
    final id = s.cashierRemoteId;
    final name = s.cashierName.isEmpty ? 'Tanpa Kasir' : s.cashierName;
    final key = id.isNotEmpty ? 'id:$id' : 'name:$name';
    final qty = s.totalQty;
    final prev = agg[key];
    if (prev == null) {
      agg[key] = CashierSummary(
        cashierId: id,
        cashierName: name,
        transactions: 1,
        itemsSold: qty,
        revenue: s.total,
      );
    } else {
      agg[key] = CashierSummary(
        cashierId: prev.cashierId,
        cashierName: prev.cashierName,
        transactions: prev.transactions + 1,
        itemsSold: prev.itemsSold + qty,
        revenue: prev.revenue + s.total,
      );
    }
  }
  final list = agg.values.toList()
    ..sort((a, b) => b.revenue.compareTo(a.revenue));
  return list;
}

class DiscountBreakdown {
  final String name;
  final String label;
  final double amount;
  const DiscountBreakdown({required this.name, required this.label, required this.amount});
}

class ReportSummary {
  final String periodLabel;
  final double revenue;
  final int transactions;
  final int itemsSold;
  final double average;
  final double discountTotal;
  final Map<String, DiscountBreakdown> discountBreakdown;
  final List<Sale> sales;

  const ReportSummary({
    required this.periodLabel,
    required this.revenue,
    required this.transactions,
    required this.itemsSold,
    required this.average,
    this.discountTotal = 0,
    this.discountBreakdown = const {},
    required this.sales,
  });

  List<TopProduct> get topProducts => computeTopProducts(sales);
  List<CashierSummary> get cashierSummaries => computeCashierSummaries(sales);
}

class ExportService {
  /// Nama file aman untuk disimpan/dibagikan.
  String buildFileName(String period, String ext) {
    final safe = period.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return 'laporan_$safe.$ext';
  }

  /// Membangun dokumen PDF tanpa menyimpan atau membagikannya.
  /// Dipakai oleh [PdfPreviewPage] untuk rendering preview.
  Future<pw.Document> buildPdfDocument(ReportSummary r) async {
    final doc = pw.Document();
    final rows = <List<String>>[
      ['ID', 'Tanggal', 'Pelanggan', 'Tipe', 'Kasir', 'Metode', 'Status', 'Subtotal', 'Diskon', 'Pajak', 'Total'],
      ...r.sales.map(
        (s) => [
          '#${s.id.toString().padLeft(3, '0')}',
          formatDateTime(s.createdAt),
          s.customerName.isEmpty ? '-' : s.customerName,
          s.orderType,
          s.cashierName.isEmpty ? '-' : s.cashierName,
          s.paymentMethod,
          s.isRefunded ? 'Refund' : 'Normal',
          formatRupiah(s.subtotal),
          formatRupiah(s.discountTotal),
          formatRupiah(s.tax),
          formatRupiah(s.total),
        ],
      ),
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 20),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
          ),
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            'Halaman ${ctx.pageNumber} dari ${ctx.pagesCount}  |  Dibuat pada ${formatDateTime(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (ctx) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Laporan Penjualan',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blueGrey800,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    r.periodLabel,
                    style: const pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
              pw.Container(
                width: 50,
                height: 50,
                child: pw.FlutterLogo(),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _pdfStat('Pendapatan', formatRupiah(r.revenue)),
              _pdfStat('Transaksi', '${r.transactions}'),
              _pdfStat('Produk Terjual', '${r.itemsSold}'),
              _pdfStat('Rata-rata', formatRupiah(r.average)),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Produk Terlaris',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (r.topProducts.isEmpty)
            pw.Text(
              'Belum ada data.',
              style: const pw.TextStyle(color: PdfColors.grey700),
            )
          else
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
              },
              data: [
                ['#', 'Nama', 'SKU', 'Harga', 'Terjual', 'Omzet'],
                for (var i = 0; i < r.topProducts.length; i++)
                  [
                    '${i + 1}',
                    r.topProducts[i].name,
                    r.topProducts[i].sku,
                    formatRupiah(
                      r.topProducts[i].qty > 0
                          ? r.topProducts[i].revenue / r.topProducts[i].qty
                          : 0,
                    ),
                    '${r.topProducts[i].qty}',
                    formatRupiah(r.topProducts[i].revenue),
                  ],
              ],
            ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Kinerja Kasir',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (r.cashierSummaries.isEmpty)
            pw.Text(
              'Belum ada data kasir.',
              style: const pw.TextStyle(color: PdfColors.grey700),
            )
          else
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
              },
              data: [
                ['#', 'Kasir', 'Transaksi', 'Qty', 'Rata-rata', 'Omzet'],
                for (var i = 0; i < r.cashierSummaries.length; i++)
                  [
                    '${i + 1}',
                    r.cashierSummaries[i].cashierName,
                    '${r.cashierSummaries[i].transactions}',
                    '${r.cashierSummaries[i].itemsSold}',
                    formatRupiah(r.cashierSummaries[i].average),
                    formatRupiah(r.cashierSummaries[i].revenue),
                  ],
              ],
            ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Rincian Transaksi',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (r.sales.isEmpty)
            pw.Text(
              'Tidak ada transaksi pada periode ini.',
              style: const pw.TextStyle(color: PdfColors.grey700),
            )
          else
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerLeft,
                5: pw.Alignment.centerLeft,
                6: pw.Alignment.centerLeft,
                7: pw.Alignment.centerRight,
                8: pw.Alignment.centerRight,
                9: pw.Alignment.centerRight,
                10: pw.Alignment.centerRight,
              },
              data: rows,
            ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total Pendapatan: ${formatRupiah(r.revenue)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );

    return doc;
  }

  /// Generate PDF lalu langsung bagikan via share sheet.
  Future<void> exportPdf(ReportSummary r) async {
    final doc = await buildPdfDocument(r);
    final bytes = await doc.save();
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name: buildFileName(r.periodLabel, 'pdf'),
            mimeType: 'application/pdf',
          ),
        ],
      ),
    );
  }

  /// Menyusun laporan sebagai berkas CSV (kompatibel dengan Excel & Google
  /// Sheets) lalu membagikannya via share sheet. Tata letaknya mengikuti
  /// laporan terdahulu: ringkasan, rincian transaksi, kinerja kasir, lalu
  /// produk terlaris — dipisah baris kosong antar seksi.
  Future<void> exportExcel(ReportSummary r) async {
    final rows = <List<dynamic>>[];

    // ── Judul ─────────────────────────────────────────────────────────────
    rows.add(['Laporan Penjualan']);
    rows.add([r.periodLabel]);
    rows.add([]);

    // ── Ringkasan ─────────────────────────────────────────────────────────
    rows.add(['Pendapatan', formatRupiah(r.revenue)]);
    rows.add(['Transaksi', r.transactions]);
    rows.add(['Produk Terjual', r.itemsSold]);
    rows.add(['Rata-rata', formatRupiah(r.average)]);
    rows.add([]);

    // ── Rincian transaksi ─────────────────────────────────────────────────
    rows.add([
      'ID',
      'Tanggal',
      'Pelanggan',
      'Tipe Pesanan',
      'Kasir',
      'Metode',
      'Status',
      'Subtotal',
      'Diskon',
      'Pajak',
      'Total',
      'Detail Item',
    ]);
    for (final s in r.sales) {
      final itemsStr = s.items.map((it) {
        final base =
            "${it.productName}${it.variant.isNotEmpty ? ' (${it.variant})' : ''} x${it.qty}";
        return it.note.isNotEmpty ? "$base [${it.note}]" : base;
      }).join(", ");
      rows.add([
        '#${s.id.toString().padLeft(3, '0')}',
        formatDateTime(s.createdAt),
        s.customerName.isEmpty ? '-' : s.customerName,
        s.orderType,
        s.cashierName.isEmpty ? '-' : s.cashierName,
        s.paymentMethod,
        s.isRefunded ? 'Refund' : 'Normal',
        s.subtotal,
        s.discountTotal,
        s.tax,
        s.total,
        itemsStr,
      ]);
    }
    rows.add([]);

    // ── Kinerja kasir ─────────────────────────────────────────────────────
    rows.add(['Kinerja Kasir']);
    rows.add(['#', 'Kasir', 'Transaksi', 'Qty', 'Rata-rata', 'Omzet']);
    final cashiers = r.cashierSummaries;
    for (var i = 0; i < cashiers.length; i++) {
      final c = cashiers[i];
      rows.add([
        i + 1,
        c.cashierName,
        c.transactions,
        c.itemsSold,
        c.average,
        c.revenue,
      ]);
    }
    rows.add([]);

    // ── Produk terlaris ───────────────────────────────────────────────────
    rows.add(['Produk Terlaris']);
    rows.add(['#', 'Nama', 'SKU', 'Harga', 'Terjual', 'Omzet']);
    final top = r.topProducts;
    for (var i = 0; i < top.length; i++) {
      final unit = top[i].qty > 0 ? top[i].revenue / top[i].qty : 0.0;
      rows.add([
        i + 1,
        top[i].name,
        top[i].sku,
        unit,
        top[i].qty,
        top[i].revenue,
      ]);
    }

    final csvData = const ListToCsvConverter().convert(rows);
    // Awali dengan BOM UTF-8 (U+FEFF) agar Excel mengenali encoding dengan
    // benar (mis. simbol "Rp" dan karakter non-ASCII tidak rusak).
    final bytes = utf8.encode('\u{FEFF}$csvData');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${buildFileName(r.periodLabel, 'csv')}');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Laporan Penjualan - ${r.periodLabel}',
      ),
    );
  }

  pw.Widget _pdfStat(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
