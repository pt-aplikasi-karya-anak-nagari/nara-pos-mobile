class BillingInvoice {
  final String id;
  final String outletId;
  final String? subscriptionId;
  final String invoiceNo;
  final String planCode;
  final String planName;
  final String status;
  final int amountIdr;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime? paidAt;
  final String? paymentProofUrl;
  final String? paymentMethodCode;
  final String? paymentMethodName;
  final String? paymentChannel;
  final String? paymentAccountNo;
  final String? paymentAccountName;
  final DateTime? proofUploadedAt;
  final DateTime? confirmedAt;
  final DateTime? failedAt;
  final String? failureReason;
  final String? renewalMode;
  final String? notes;
  /// Referensi transfer eksternal yang diisi owner saat mengunggah bukti
  /// (mis. no. referensi / berita transfer dari bank).
  final String? externalReference;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BillingInvoice({
    required this.id,
    required this.outletId,
    this.subscriptionId,
    required this.invoiceNo,
    required this.planCode,
    required this.planName,
    required this.status,
    required this.amountIdr,
    required this.periodStart,
    required this.periodEnd,
    this.paidAt,
    this.paymentProofUrl,
    this.paymentMethodCode,
    this.paymentMethodName,
    this.paymentChannel,
    this.paymentAccountNo,
    this.paymentAccountName,
    this.proofUploadedAt,
    this.confirmedAt,
    this.failedAt,
    this.failureReason,
    this.renewalMode,
    this.notes,
    this.externalReference,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isPaid => status == 'paid';

  /// Invoice yang bukti transfernya sudah diunggah (menunggu / sudah dikonfirmasi).
  bool get hasProof => (paymentProofUrl ?? '').isNotEmpty;

  /// Ditolak admin — transfer tidak valid / tidak cocok. Owner perlu unggah
  /// ulang bukti yang benar.
  bool get isRejected => status == 'rejected';

  /// Owner boleh mengunggah bukti transfer HANYA selama invoice pending.
  /// Backend menolak upload untuk status non-pending; invoice yang ditolak
  /// harus di-checkout ulang (bikin invoice pending baru), bukan re-upload.
  bool get canUploadProof => status == 'pending';

  factory BillingInvoice.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) {
      if (value is String) {
        return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
      }
      return DateTime.now();
    }

    DateTime? parseNullableDate(dynamic value) {
      if (value is! String || value.isEmpty) return null;
      return DateTime.tryParse(value)?.toLocal();
    }

    return BillingInvoice(
      id: json['id']?.toString() ?? '',
      outletId: json['outlet_id']?.toString() ?? '',
      subscriptionId: json['subscription_id']?.toString(),
      invoiceNo: json['invoice_no']?.toString() ?? '',
      planCode: json['plan_code']?.toString() ?? '',
      planName: json['plan_name']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      amountIdr: (json['amount_idr'] as num?)?.toInt() ?? 0,
      periodStart: parseDate(json['period_start']),
      periodEnd: parseDate(json['period_end']),
      paidAt: parseNullableDate(json['paid_at']),
      paymentProofUrl: json['payment_proof_url']?.toString(),
      paymentMethodCode: json['payment_method_code']?.toString(),
      paymentMethodName: json['payment_method_name']?.toString(),
      paymentChannel: json['payment_channel']?.toString(),
      paymentAccountNo: json['payment_account_no']?.toString(),
      paymentAccountName: json['payment_account_name']?.toString(),
      proofUploadedAt: parseNullableDate(json['proof_uploaded_at']),
      confirmedAt: parseNullableDate(json['confirmed_at']),
      failedAt: parseNullableDate(json['failed_at']),
      failureReason: json['failure_reason']?.toString(),
      renewalMode: json['renewal_mode']?.toString(),
      notes: json['notes']?.toString(),
      externalReference: json['external_reference']?.toString(),
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }
}
