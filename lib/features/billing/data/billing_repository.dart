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
    String billingCycle = 'monthly',
  }) async {
    try {
      final res = await dio.post<Map<String, dynamic>>(
        ApiEndpoint.billingCheckout(outletId),
        data: {
          'plan_code': planCode,
          'billing_cycle': billingCycle,
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

  /// Status terkini sebuah invoice + instruksi bayarnya. Dipolling layar bayar
  /// QRIS; server ikut menanyakan ke gateway bila webhook-nya belum tiba.
  Future<BillingCheckoutResult> cekPembayaran(
    String outletId,
    String invoiceId,
  ) async {
    try {
      final res = await dio.post<Map<String, dynamic>>(
        ApiEndpoint.billingCekPembayaran(outletId, invoiceId),
      );
      final data = res.data?['data'];
      return BillingCheckoutResult.fromJson(
        data is Map<String, dynamic> ? data : const {},
      );
    } on DioException catch (e) {
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      throw msg ?? 'Gagal memeriksa status pembayaran';
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

  /// Invoice sudah lunas (langganan aktif).
  bool get lunas => status == 'paid';

  /// Dibayar otomatis lewat QRIS, bukan transfer manual.
  bool get qris => paymentInstruction?.isQris ?? false;

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

/// `method_code` invoice yang dibayar otomatis lewat QRIS (Xendit).
const metodeQris = 'xendit_qris';

/// Sisa waktu sebuah kode QR pada saat [kini]. `habis` juga true bila batas
/// waktunya tidak ada — QR tanpa batas waktu yang jelas tidak ditampilkan
/// sebagai "masih berlaku".
({bool habis, bool mendesak, String teks}) sisaWaktuQris(
  DateTime? expiresAt,
  DateTime kini,
) {
  if (expiresAt == null) return (habis: true, mendesak: false, teks: '');
  final detik = expiresAt.difference(kini).inSeconds;
  if (detik <= 0) return (habis: true, mendesak: false, teks: '');
  final m = detik ~/ 60;
  final d = detik % 60;
  final teks = m >= 60
      ? '${m ~/ 60} jam ${m % 60} menit'
      : '${m.toString().padLeft(2, '0')}:${d.toString().padLeft(2, '0')}';
  return (habis: false, mendesak: detik <= 120, teks: teks);
}

/// Instruksi bayar yang dikembalikan checkout.
///
///  - `method_code` [metodeQris]      → QRIS otomatis: tampilkan [qrString]
///    lalu polling `cekPembayaran` sampai lunas.
///  - `method_code` `manual_transfer` → transfer bank + unggah bukti (cadangan,
///    dipakai bila gateway belum dikonfigurasi di server).
class PaymentInstruction {
  final String methodCode;
  final String methodName;
  final int amountIdr;
  final String invoiceNo;
  final String bankName;
  final String bankAccountNo;
  final String bankAccountName;
  final String instructions;

  /// "xendit" bila dibayar lewat gateway.
  final String provider;

  /// Isi kode QRIS. Kosong = kode kedaluwarsa/gagal; checkout lagi untuk
  /// kode baru (invoice-nya tetap sama).
  final String qrString;

  /// Batas waktu kode QR.
  final DateTime? expiresAt;

  /// pending | paid | expired | failed.
  final String gatewayStatus;

  bool get isQris => methodCode == metodeQris;

  const PaymentInstruction({
    required this.methodCode,
    required this.methodName,
    required this.amountIdr,
    required this.invoiceNo,
    required this.bankName,
    required this.bankAccountNo,
    required this.bankAccountName,
    required this.instructions,
    this.provider = '',
    this.qrString = '',
    this.expiresAt,
    this.gatewayStatus = '',
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
      provider: json['provider']?.toString() ?? '',
      qrString: json['qr_string']?.toString() ?? '',
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      gatewayStatus: json['gateway_status']?.toString() ?? '',
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
