import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_endpoint.dart';
import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/outlet_scope.dart';
import '../domain/billing_invoice.dart';

class BillingRepository extends BaseApiService {
  BillingRepository(super.dio);

  Future<List<BillingInvoice>> getOutletInvoices(String outletId) {
    return get<List<BillingInvoice>>(
      ApiEndpoint.outletBillingInvoices(outletId),
      queryParameters: const {'limit': 50},
      converter: (data) {
        final list = data as List<dynamic>? ?? const [];
        return list
            .map(
              (json) => BillingInvoice.fromJson(json as Map<String, dynamic>),
            )
            .toList();
      },
    );
  }

  Future<String> downloadInvoiceHtml(String invoiceId) async {
    final res = await dio.get<String>(
      ApiEndpoint.billingInvoiceDownload(invoiceId),
      options: Options(
        responseType: ResponseType.plain,
        headers: const {'Accept': 'text/html'},
      ),
    );
    return res.data ?? '';
  }

  Future<void> shareInvoice(BillingInvoice invoice) async {
    final html = await downloadInvoiceHtml(invoice.id);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${invoice.invoiceNo}.html');
    await file.writeAsString(html, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/html')],
        subject: 'Invoice ${invoice.invoiceNo}',
      ),
    );
  }

  /// Buat invoice pembayaran langganan (checkout). Mengembalikan hasil berisi
  /// `gatewayPaymentUrl` (link Xendit) yang dibuka di browser untuk membayar.
  ///
  /// [renewalMode] hanya diperlukan bila outlet sudah punya langganan aktif
  /// dengan paket berbeda — backend membalas 409 (`renewal_choice_required`)
  /// bila kosong; UI menangkap [RenewalChoiceRequiredException] lalu meminta
  /// pilihan ('renew' = lanjut paket sama, 'upgrade_replace' = ganti paket).
  Future<BillingCheckoutResult> createCheckout(
    String outletId,
    String planCode, {
    String? renewalMode,
    String? voucherCode,
  }) async {
    try {
      final res = await dio.post<Map<String, dynamic>>(
        ApiEndpoint.billingCheckout(outletId),
        data: {
          'plan_code': planCode,
          if (renewalMode != null && renewalMode.isNotEmpty)
            'renewal_mode': renewalMode,
          if (voucherCode != null && voucherCode.isNotEmpty)
            'voucher_code': voucherCode,
        },
      );
      final data = res.data?['data'];
      return BillingCheckoutResult.fromJson(
        data is Map<String, dynamic> ? data : const {},
      );
    } on DioException catch (e) {
      final body = e.response?.data;
      final code = body is Map ? body['code']?.toString() : null;
      final msg = body is Map ? body['message']?.toString() : null;
      if (e.response?.statusCode == 409 && code == 'renewal_choice_required') {
        throw RenewalChoiceRequiredException(
          msg ?? 'Outlet sudah punya langganan aktif. Pilih mode perpanjangan.',
        );
      }
      throw msg ?? 'Gagal membuat pembayaran langganan';
    }
  }

  /// Sinkronkan status invoice langsung dari gateway (Xendit). Dipakai
  /// sebagai fallback saat webhook belum/tidak sampai (mis. di dev pakai
  /// localhost). Backend query Xendit; kalau sudah PAID, invoice ditandai
  /// lunas & langganan diaktifkan. Mengembalikan invoice terbaru.
  Future<BillingInvoice> syncInvoice(String invoiceId) async {
    return post<BillingInvoice>(
      ApiEndpoint.billingInvoiceSync(invoiceId),
      converter: (data) =>
          BillingInvoice.fromJson(data as Map<String, dynamic>),
    );
  }
}

/// Hasil checkout langganan — yang dipakai UI utama adalah `gatewayPaymentUrl`.
class BillingCheckoutResult {
  final String invoiceId;
  final String invoiceNo;
  final int amountIdr;
  final String status;
  final String? gatewayPaymentUrl;

  const BillingCheckoutResult({
    required this.invoiceId,
    required this.invoiceNo,
    required this.amountIdr,
    required this.status,
    this.gatewayPaymentUrl,
  });

  factory BillingCheckoutResult.fromJson(Map<String, dynamic> json) {
    final inv = json['invoice'];
    final pi = json['payment_instruction'];
    final invMap = inv is Map ? inv : const {};
    final piMap = pi is Map ? pi : const {};
    return BillingCheckoutResult(
      invoiceId: invMap['id']?.toString() ?? '',
      invoiceNo:
          invMap['invoice_no']?.toString() ??
          piMap['invoice_no']?.toString() ??
          '',
      amountIdr:
          (invMap['amount_idr'] as num?)?.toInt() ??
          (piMap['amount_idr'] as num?)?.toInt() ??
          0,
      status: invMap['status']?.toString() ?? 'pending',
      gatewayPaymentUrl: invMap['gateway_payment_url']?.toString(),
    );
  }
}

/// Dilempar saat backend butuh owner memilih mode perpanjangan (HTTP 409).
class RenewalChoiceRequiredException implements Exception {
  final String message;
  const RenewalChoiceRequiredException(this.message);
  @override
  String toString() => message;
}

final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  return BillingRepository(ref.watch(dioProvider));
});

final billingInvoicesProvider = FutureProvider<List<BillingInvoice>>((ref) {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null || outletId.isEmpty) return Future.value(const []);
  return ref.watch(billingRepositoryProvider).getOutletInvoices(outletId);
});
