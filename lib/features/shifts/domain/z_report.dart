import 'shift.dart';

/// Rincian satu metode pembayaran pada Z-Report. [method] datang lowercase
/// dari backend (mis. "tunai", "qris", "kartu", "transfer", "lainnya").
class ZPaymentBreakdown {
  final String method;
  final double amount;

  const ZPaymentBreakdown({required this.method, required this.amount});

  factory ZPaymentBreakdown.fromJson(Map<String, dynamic> json) {
    return ZPaymentBreakdown(
      method: json['method']?.toString() ?? 'lainnya',
      amount: _parseDouble(json['amount']) ?? 0,
    );
  }
}

/// Laporan tutup shift (Z-Report). Ringkasan final sebuah shift: info shift,
/// rincian pembayaran per metode, dan total-total penjualan/pajak/service.
/// Sumber: GET /shifts/:id/z-report.
class ZReport {
  final Shift shift;
  final List<ZPaymentBreakdown> paymentBreakdown;
  final double grossSales;
  final double refundTotal;
  final double netSales; // = grossSales - refundTotal
  final double taxTotal;
  final double serviceTotal;
  final double discountTotal;
  final int transactionCount;

  const ZReport({
    required this.shift,
    required this.paymentBreakdown,
    required this.grossSales,
    required this.refundTotal,
    required this.netSales,
    required this.taxTotal,
    required this.serviceTotal,
    required this.discountTotal,
    required this.transactionCount,
  });

  factory ZReport.fromJson(Map<String, dynamic> json) {
    final shiftJson = json['shift'];
    final breakdown = json['payment_breakdown'];
    return ZReport(
      shift: Shift.fromJson(
        shiftJson is Map
            ? Map<String, dynamic>.from(shiftJson)
            : <String, dynamic>{},
      ),
      paymentBreakdown: breakdown is List
          ? breakdown
                .map((e) => ZPaymentBreakdown.fromJson(
                      Map<String, dynamic>.from(e as Map),
                    ))
                .toList()
          : const [],
      grossSales: _parseDouble(json['gross_sales']) ?? 0,
      refundTotal: _parseDouble(json['refund_total']) ?? 0,
      netSales: _parseDouble(json['net_sales']) ?? 0,
      taxTotal: _parseDouble(json['tax_total']) ?? 0,
      serviceTotal: _parseDouble(json['service_total']) ?? 0,
      discountTotal: _parseDouble(json['discount_total']) ?? 0,
      transactionCount: (json['transaction_count'] as num?)?.toInt() ?? 0,
    );
  }
}

double? _parseDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}
