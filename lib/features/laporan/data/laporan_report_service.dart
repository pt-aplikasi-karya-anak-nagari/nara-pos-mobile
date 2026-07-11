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
