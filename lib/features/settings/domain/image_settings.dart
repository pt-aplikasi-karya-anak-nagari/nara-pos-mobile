// Domain model untuk pengaturan kualitas upload gambar per outlet.
// Backend: outletasIntmage_settings table (migration 000096).
//
// Settings ini dipakai backend untuk auto resize + compress saat
// upload. Flutter side bisa juga pre-apply (image_picker.imageQuality)
// untuk hemat bandwidth — backend tetap sumber kebenaran.

class OutletImageSettings {
  final String outletId;
  final bool enabled;
  final bool stripMetadata;
  final bool convertPngToJpeg;

  // Products
  final int productsQuality;
  final int productsMaxDim;
  final int productsMaxSizeKb;

  // Payment proof
  final int paymentProofQuality;
  final int paymentProofMaxDim;
  final int paymentProofMaxSizeKb;

  // Attendance
  final int attendanceQuality;
  final int attendanceMaxDim;
  final int attendanceMaxSizeKb;

  // Receipt logo
  final int receiptLogoQuality;
  final int receiptLogoMaxDim;
  final int receiptLogoMaxSizeKb;

  const OutletImageSettings({
    required this.outletId,
    this.enabled = true,
    this.stripMetadata = true,
    this.convertPngToJpeg = true,
    this.productsQuality = 80,
    this.productsMaxDim = 1024,
    this.productsMaxSizeKb = 500,
    this.paymentProofQuality = 75,
    this.paymentProofMaxDim = 1280,
    this.paymentProofMaxSizeKb = 800,
    this.attendanceQuality = 70,
    this.attendanceMaxDim = 800,
    this.attendanceMaxSizeKb = 400,
    this.receiptLogoQuality = 85,
    this.receiptLogoMaxDim = 512,
    this.receiptLogoMaxSizeKb = 200,
  });

  factory OutletImageSettings.fromJson(Map<String, dynamic> json) {
    int asInt(String k, int fallback) =>
        (json[k] as num?)?.toInt() ?? fallback;
    return OutletImageSettings(
      outletId: (json['outletasIntd'] as String?) ?? '',
      enabled: json['enabled'] as bool? ?? true,
      stripMetadata: json['strip_metadata'] as bool? ?? true,
      convertPngToJpeg: json['convert_png_to_jpeg'] as bool? ?? true,
      productsQuality: asInt('products_quality', 80),
      productsMaxDim: asInt('products_max_dim', 1024),
      productsMaxSizeKb: asInt('products_max_size_kb', 500),
      paymentProofQuality: asInt('payment_proof_quality', 75),
      paymentProofMaxDim: asInt('payment_proof_max_dim', 1280),
      paymentProofMaxSizeKb: asInt('payment_proof_max_size_kb', 800),
      attendanceQuality: asInt('attendance_quality', 70),
      attendanceMaxDim: asInt('attendance_max_dim', 800),
      attendanceMaxSizeKb: asInt('attendance_max_size_kb', 400),
      receiptLogoQuality: asInt('receipt_logo_quality', 85),
      receiptLogoMaxDim: asInt('receipt_logo_max_dim', 512),
      receiptLogoMaxSizeKb: asInt('receipt_logo_max_size_kb', 200),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'strip_metadata': stripMetadata,
        'convert_png_to_jpeg': convertPngToJpeg,
        'products_quality': productsQuality,
        'products_max_dim': productsMaxDim,
        'products_max_size_kb': productsMaxSizeKb,
        'payment_proof_quality': paymentProofQuality,
        'payment_proof_max_dim': paymentProofMaxDim,
        'payment_proof_max_size_kb': paymentProofMaxSizeKb,
        'attendance_quality': attendanceQuality,
        'attendance_max_dim': attendanceMaxDim,
        'attendance_max_size_kb': attendanceMaxSizeKb,
        'receipt_logo_quality': receiptLogoQuality,
        'receipt_logo_max_dim': receiptLogoMaxDim,
        'receipt_logo_max_size_kb': receiptLogoMaxSizeKb,
      };

  factory OutletImageSettings.defaults(String outletId) =>
      OutletImageSettings(outletId: outletId);
}

// Context keys — match dengan entity.ImageContext* di backend.
enum ImageContext {
  products,
  paymentProof,
  attendance,
  receiptLogo,
}

extension ImageContextExt on ImageContext {
  /// String key untuk form field saat upload (form_data['outletasIntd']
  /// digabung dengan context routing di backend).
  String get key {
    switch (this) {
      case ImageContext.products:
        return 'products';
      case ImageContext.paymentProof:
        return 'payment_proof';
      case ImageContext.attendance:
        return 'attendance';
      case ImageContext.receiptLogo:
        return 'receipt_logo';
    }
  }
}

extension OutletImageSettingsContext on OutletImageSettings {
  /// Resolve (quality, maxDim, maxSizeKb) untuk context tertentu.
  /// Dipakai Flutter ImagePicker.imageQuality untuk pre-compress
  /// sebelum upload — saves bandwidth, backend tetap re-process.
  (int quality, int maxDim, int maxSizeKb) perContext(ImageContext ctx) {
    switch (ctx) {
      case ImageContext.products:
        return (productsQuality, productsMaxDim, productsMaxSizeKb);
      case ImageContext.paymentProof:
        return (paymentProofQuality, paymentProofMaxDim, paymentProofMaxSizeKb);
      case ImageContext.attendance:
        return (attendanceQuality, attendanceMaxDim, attendanceMaxSizeKb);
      case ImageContext.receiptLogo:
        return (receiptLogoQuality, receiptLogoMaxDim, receiptLogoMaxSizeKb);
    }
  }
}
