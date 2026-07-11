import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';

// Laporan pakai agregasi SERVER (C3) supaya angka konsisten dengan web
// (timezone, pagination, perlakuan refund dihitung di backend, bukan di klien).
// Endpoint: GET /reports/outlet/:outletId/summary?date_from=&date_to=

class ServerReportSummary {
  final double revenue;
  final int transactions;
  final int itemsSold;
  final double average;
  final double discountTotal;

  const ServerReportSummary({
    required this.revenue,
    required this.transactions,
    required this.itemsSold,
    required this.average,
    required this.discountTotal,
  });

  factory ServerReportSummary.fromJson(Map<String, dynamic> j) => ServerReportSummary(
    revenue: (j['total_revenue'] as num?)?.toDouble() ?? 0,
    transactions: (j['transaction_count'] as num?)?.toInt() ?? 0,
    itemsSold: (j['items_sold'] as num?)?.toInt() ?? 0,
    average: (j['average_ticket'] as num?)?.toDouble() ?? 0,
    discountTotal: (j['discount_total'] as num?)?.toDouble() ?? 0,
  );
}

// Laporan Pajak (PPN/PB1) keluaran per masa — untuk pelaporan SPT. Hanya
// menghitung transaksi LUNAS (paid). DPP = gross − pajak − service.
// Endpoint: GET /reports/outlet/:outletId/tax-period?date_from=&date_to=

/// Satu baris masa pajak (per bulan, mis. "2026-05").
class TaxPeriodRow {
  final String period; // "YYYY-MM"
  final double dpp;
  final double tax;
  final double service;
  final double discount;
  final double gross;
  final int txCount;

  const TaxPeriodRow({
    required this.period,
    required this.dpp,
    required this.tax,
    required this.service,
    required this.discount,
    required this.gross,
    required this.txCount,
  });

  factory TaxPeriodRow.fromJson(Map<String, dynamic> j) => TaxPeriodRow(
    period: j['period']?.toString() ?? '',
    dpp: (j['dpp'] as num?)?.toDouble() ?? 0,
    tax: (j['tax'] as num?)?.toDouble() ?? 0,
    service: (j['service'] as num?)?.toDouble() ?? 0,
    discount: (j['discount'] as num?)?.toDouble() ?? 0,
    gross: (j['gross'] as num?)?.toDouble() ?? 0,
    txCount: (j['tx_count'] as num?)?.toInt() ?? 0,
  );
}

/// Rekap pajak keluaran per masa + total keseluruhan rentang.
class TaxPeriodReport {
  final List<TaxPeriodRow> rows;
  final double totalDpp;
  final double totalTax;
  final double totalService;
  final double totalGross;
  final int totalTx;

  const TaxPeriodReport({
    required this.rows,
    required this.totalDpp,
    required this.totalTax,
    required this.totalService,
    required this.totalGross,
    required this.totalTx,
  });

  factory TaxPeriodReport.fromJson(Map<String, dynamic> j) {
    final rawRows = j['rows'];
    return TaxPeriodReport(
      rows: rawRows is List
          ? rawRows
                .map((e) =>
                    TaxPeriodRow.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList()
          : const [],
      totalDpp: (j['total_dpp'] as num?)?.toDouble() ?? 0,
      totalTax: (j['total_tax'] as num?)?.toDouble() ?? 0,
      totalService: (j['total_service'] as num?)?.toDouble() ?? 0,
      totalGross: (j['total_gross'] as num?)?.toDouble() ?? 0,
      totalTx: (j['total_tx'] as num?)?.toInt() ?? 0,
    );
  }
}

class LaporanReportService extends BaseApiService {
  LaporanReportService(super.dio);

  Future<ServerReportSummary> getSummary(String outletId, String from, String to) async {
    return get(
      '/reports/outlet/$outletId/summary',
      queryParameters: {
        if (from.isNotEmpty) 'date_from': from,
        if (to.isNotEmpty) 'date_to': to,
      },
      converter: (data) {
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        return ServerReportSummary.fromJson(map);
      },
    );
  }

  /// Laporan pajak (PPN/PB1) keluaran per masa untuk rentang tanggal.
  Future<TaxPeriodReport> getTaxPeriod(
    String outletId,
    String from,
    String to,
  ) async {
    return get(
      '/reports/outlet/$outletId/tax-period',
      queryParameters: {
        if (from.isNotEmpty) 'date_from': from,
        if (to.isNotEmpty) 'date_to': to,
      },
      converter: (data) {
        final map = data is Map
            ? Map<String, dynamic>.from(data)
            : <String, dynamic>{};
        return TaxPeriodReport.fromJson(map);
      },
    );
  }
}

final laporanReportServiceProvider = Provider<LaporanReportService>((ref) {
  return LaporanReportService(ref.watch(dioProvider));
});

typedef ReportRangeKey = ({String outletId, String from, String to});

/// Ringkasan laporan dari server untuk rentang tertentu. Return null bila
/// gagal (offline) → caller fallback ke agregasi klien.
final serverSummaryProvider =
    FutureProvider.family<ServerReportSummary?, ReportRangeKey>((ref, key) async {
  if (key.outletId.isEmpty) return null;
  try {
    return await ref
        .read(laporanReportServiceProvider)
        .getSummary(key.outletId, key.from, key.to);
  } catch (_) {
    return null;
  }
});

/// Laporan pajak (PPN/PB1) per masa untuk rentang tertentu. Berbeda dengan
/// [serverSummaryProvider] yang menelan error (fallback offline), provider ini
/// membiarkan error naik supaya layar Laporan Pajak bisa tampilkan state error.
final taxPeriodProvider =
    FutureProvider.family<TaxPeriodReport, ReportRangeKey>((ref, key) async {
  return ref
      .read(laporanReportServiceProvider)
      .getTaxPeriod(key.outletId, key.from, key.to);
});
