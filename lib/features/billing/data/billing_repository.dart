import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/image_compress.dart';
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
  /// invoice + [PaymentInstruction] (detail transfer bank manual: nama bank,
  /// no & atas nama rekening, nominal). Owner transfer manual lalu mengunggah
  /// bukti via [uploadPaymentProof]; admin yang mengonfirmasi.
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

  /// Unggah bukti transfer untuk sebuah invoice pending (multipart, field
  /// `image`). Setelah ini status invoice tetap `pending` sampai admin
  /// mengonfirmasi transfer masuk. [externalReference] opsional — mis. no.
  /// referensi/berita transfer dari bank.
  ///
  /// File dikompres dulu (JPEG, max 1600 px) supaya upload cepat & hemat
  /// storage — konsisten dengan upload bukti bayar di kasir.
  Future<void> uploadPaymentProof(
    String invoiceId,
    File image, {
    String? externalReference,
  }) async {
    final compressedPath = await ImageCompress.compressFile(image.path);
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        compressedPath,
        filename: compressedPath.split('/').last,
      ),
      if (externalReference != null && externalReference.isNotEmpty)
        'external_reference': externalReference,
    });
    await dio.post<Map<String, dynamic>>(
      ApiEndpoint.billingInvoiceUploadProof(invoiceId),
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        responseType: ResponseType.json,
      ),
    );
  }
}

/// Hasil checkout langganan — invoice yang dibuat + instruksi transfer bank
/// manual yang harus ditampilkan ke owner.
class BillingCheckoutResult {
  final String invoiceId;
  final String invoiceNo;
  final int amountIdr;
  final String status;
  final PaymentInstruction? paymentInstruction;

  const BillingCheckoutResult({
    required this.invoiceId,
    required this.invoiceNo,
    required this.amountIdr,
    required this.status,
    this.paymentInstruction,
  });

  factory BillingCheckoutResult.fromJson(Map<String, dynamic> json) {
    final inv = json['invoice'];
    final pi = json['payment_instruction'];
    final invMap = inv is Map ? inv : const {};
    final piMap = pi is Map<String, dynamic> ? pi : null;
    return BillingCheckoutResult(
      invoiceId: invMap['id']?.toString() ?? '',
      invoiceNo:
          invMap['invoice_no']?.toString() ??
          piMap?['invoice_no']?.toString() ??
          '',
      amountIdr:
          (invMap['amount_idr'] as num?)?.toInt() ??
          (piMap?['amount_idr'] as num?)?.toInt() ??
          0,
      status: invMap['status']?.toString() ?? 'pending',
      paymentInstruction: piMap != null
          ? PaymentInstruction.fromJson(piMap)
          : null,
    );
  }
}

/// Instruksi transfer bank manual (pengganti gateway/QR). Ditampilkan ke owner
/// setelah checkout: transfer sesuai nominal ke rekening berikut lalu unggah
/// bukti transfer.
class PaymentInstruction {
  final String methodCode;
  final String methodName;
  final int amountIdr;
  final String invoiceNo;
  final String bankName;
  final String bankAccountNo;
  final String bankAccountName;
  final String instructions;

  const PaymentInstruction({
    required this.methodCode,
    required this.methodName,
    required this.amountIdr,
    required this.invoiceNo,
    required this.bankName,
    required this.bankAccountNo,
    required this.bankAccountName,
    required this.instructions,
  });

  factory PaymentInstruction.fromJson(Map<String, dynamic> json) {
    return PaymentInstruction(
      methodCode: json['method_code']?.toString() ?? '',
      methodName: json['method_name']?.toString() ?? '',
      amountIdr: (json['amount_idr'] as num?)?.toInt() ?? 0,
      invoiceNo: json['invoice_no']?.toString() ?? '',
      bankName: json['bank_name']?.toString() ?? '',
      bankAccountNo: json['bank_account_no']?.toString() ?? '',
      bankAccountName: json['bank_account_name']?.toString() ?? '',
      instructions: json['instructions']?.toString() ?? '',
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
