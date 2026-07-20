
import '../../customers/domain/customer.dart';
import 'sale_item.dart';

class Sale {
    String id;

    DateTime createdAt;

  double subtotal;
  double originalSubtotal;
  double tax;
  double discountTotal;
  double serviceCharge;
  double total;

  String paymentMethod;
  double cashAmount;
  double changeAmount;

  String customerName;

  String orderType;
  String invoiceId;


  bool isPaid;
    DateTime? paidAt;

  /// Status pembayaran MENTAH (lowercase) dari backend: unpaid | paid |
  /// refunded | partially_refunded | cancelled | pending. Sumber kebenaran untuk
  /// membedakan 'unpaid' dari 'cancelled'/'pending' (sama-sama bukan-lunas) —
  /// penting untuk tutup-meja: hanya yang persis 'unpaid' yang boleh dilunasi.
  String paymentStatus;

  /// QR self-order: waktu kasir mengonfirmasi/menerima pesanan (confirmed_at).
  /// Null = belum dikonfirmasi. Pesanan QR dibuat SUDAH lunas; nilai ini yang
  /// membedakan antrean kasir ("belum dikonfirmasi").
  DateTime? confirmedAt;

  /// Tahap penyelesaian pesanan QR yang dimajukan kasir:
  /// pending | received | preparing | delivering | completed.
  String fulfillmentStatus;

  /// Nomor antrian harian QR self-order (queue_no). Null untuk transaksi
  /// non-menu atau pesanan QR yang belum diberi antrian (mis. belum lunas &
  /// belum dikonfirmasi).
  int? queueNo;

  /// Ref charge gateway QRIS (payment_ref). Null = tanpa charge (open-bill /
  /// pilihan "bayar di kasir") — pembeda antrean kasir dari menunggu-QRIS.
  String? paymentRef;

  /// Catatan level-pesanan dari pelanggan QR ("alergi kacang untuk semua").
  String? note;

  bool isRefunded;
  /// True bila transaksi diretur SEBAGIAN (retur per-item). Backend field:
  /// `payment_status = 'partially_refunded'`. Berbeda dari [isRefunded] yang
  /// berarti retur PENUH. Transaksi partial masih bisa diretur lagi selama
  /// masih ada item dengan sisa qty (lihat [hasRefundableItems]).
  bool isPartiallyRefunded;
  /// Akumulasi nominal yang sudah diretur (backend field `refunded_amount`).
  /// 0 = belum ada retur. Dihitung server; mobile hanya menampilkan.
  double refundedAmount;
  DateTime? refundedAt;
  /// User yang melakukan refund (mis. owner / admin outlet via dashboard
  /// web). Backend field: `refunded_by`. Null = belum di-refund.
  String? refundedBy;
  /// Alasan refund yang di-input owner saat klik tombol Refund di
  /// dashboard web. Wajib (min 5 char) di backend.
  String? refundReason;

  String cashierRemoteId;
  String cashierName;
  int outletId;
  String? outletRemoteId;
  String outletName;

  int pointsEarned;
  int pointsUsed;

  String? tableId;
  String? tableName;
  /// Nama group meja (mis. "Lantai 2", "Outdoor"). Backend mengirim via
  /// LEFT JOIN ke `table_groups`. Null jika meja tidak punya group atau
  /// transaksi tidak dine-in. Dipakai untuk render lokasi meja yang
  /// informatif di UI ("Meja A1 · Lantai 2").
  String? tableGroupName;

  /// URL relatif bukti pembayaran (foto QRIS scan / struk transfer / dll).
  /// Null = belum upload atau tx cash yang tidak butuh bukti.
  String? paymentProofUrl;

  /// Sumber asal transaksi:
  ///   - 'kasir'   → dibuat oleh kasir lewat aplikasi ini (default).
  ///   - 'menu_qr' → self-order customer lewat QR-menu mako-scan-qr.
  /// Dipakai untuk menampilkan badge pembeda di riwayat & laporan.
  /// Default 'kasir' supaya transaksi lama (sebelum migration 000051)
  /// dan transaksi dari aplikasi kasir tetap tampil normal.
  String source;

  Customer? customer;

  /// True bila transaksi ini dibuat offline dan masih menunggu sinkron ke
  /// backend (tersimpan di outbox lokal). Dipakai UI untuk menandai struk /
  /// konfirmasi "tersimpan offline". Tidak berasal dari backend.
  bool pendingSync;

    List<SaleItem> items = [];

  Sale({
    this.id = '',
    required this.createdAt,
    required this.subtotal,
    this.originalSubtotal = 0,
    required this.tax,
    this.discountTotal = 0,
    this.serviceCharge = 0,
    required this.total,
    required this.paymentMethod,
    this.cashAmount = 0,
    this.changeAmount = 0,
    this.customerName = '',
    this.orderType = 'Dine In',
    this.invoiceId = '',
    this.isPaid = true,
    this.paymentStatus = 'unpaid',
    this.paidAt,
    this.confirmedAt,
    this.fulfillmentStatus = 'pending',
    this.queueNo,
    this.paymentRef,
    this.note,
    this.isRefunded = false,
    this.isPartiallyRefunded = false,
    this.refundedAmount = 0,
    this.refundedAt,
    this.refundedBy,
    this.refundReason,
    this.cashierRemoteId = '',
    this.cashierName = '',
    this.outletId = 0,
    this.outletRemoteId,
    this.outletName = '',
    this.pointsEarned = 0,
    this.pointsUsed = 0,
    this.tableId,
    this.tableName,
    this.tableGroupName,
    this.paymentProofUrl,
    this.source = 'kasir',
    this.pendingSync = false,
  });

  /// True kalau transaksi dibuat lewat QR-menu customer (mako-scan-qr).
  bool get isFromMenuQr => source == 'menu_qr';

  /// True bila pesanan QR sudah dikonfirmasi kasir.
  bool get isConfirmed => confirmedAt != null;

  /// True bila transaksi BENAR-BENAR belum dibayar (persis payment_status=
  /// 'unpaid') — beda dari `!isPaid` yang juga true untuk 'cancelled' /
  /// 'refunded' / 'pending'. Dipakai filter tutup-meja agar total yang ditagih
  /// = tepat yang dilunasi backend (backend juga hanya menutup 'unpaid').
  bool get isUnpaid => paymentStatus == 'unpaid';

  /// True bila ronde sudah DIBATALKAN (void, payment_status='cancelled').
  /// Dipakai UI detail meja agar ronde void tak tampil seolah "belum bayar".
  bool get isCancelled => paymentStatus == 'cancelled';

  /// True bila tipe pesanan Dine In (case-insensitive). Dipakai untuk
  /// kondisional render info meja di UI & struk.
  bool get isDineIn => orderType.trim().toLowerCase() == 'dine in';

  /// Label meja gabungan: "Meja A1 · Lantai 2" (nama + group) atau
  /// "Meja A1" kalau tidak ada group, atau null jika tidak ada data
  /// meja sama sekali. Return null = jangan tampilkan baris ini.
  ///
  /// `tableName` dari backend umumnya sudah include prefix "Meja"
  /// (mis. "Meja 1", "Meja A1") — JANGAN tambah prefix lagi di caller.
  String? get tableDisplay {
    final name = tableName?.trim();
    if (name == null || name.isEmpty) return null;
    final group = tableGroupName?.trim();
    if (group == null || group.isEmpty) return name;
    return '$name · $group';
  }

  /// Versi tableDisplay untuk konteks yang label kolom-nya sudah
  /// "Meja" (mis. baris struk dengan label kiri "Meja"). Strip prefix
  /// "Meja " supaya tidak duplikat: "Meja 1 · Lantai 2" → "1 · Lantai 2".
  String? get tablePositionDisplay {
    final full = tableDisplay;
    if (full == null) return null;
    final lower = full.toLowerCase();
    if (lower.startsWith('meja ')) {
      return full.substring('meja '.length).trim();
    }
    return full;
  }

  int get totalQty => items.fold(0, (sum, it) => sum + it.qty);
  set totalQty(int value) {}

  /// Nilai transaksi setelah dikurangi yang sudah diretur.
  ///
  /// Retur TIDAK mengubah [total] — nilai jual asli sengaja dipertahankan
  /// server, dan yang dikembalikan dicatat terpisah di [refundedAmount]. Jadi
  /// agregasi omzet WAJIB memakai getter ini, bukan [total].
  ///
  /// Retur penuh bernilai nol tanpa membaca [refundedAmount], karena struk yang
  /// diretur lewat jalur lama menyimpan 0 di kolom itu. Aturan yang sama dipakai
  /// server (lihat report/refund_netting.go) supaya angka mobile dan web sama.
  double get netTotal {
    final net = total - refundedValue;
    return net > 0 ? net : 0;
  }

  /// Porsi struk yang sudah diretur, 0..1. Padanan `refundRatio()` di server.
  /// Retur penuh dipatok 1 tanpa membaca [refundedAmount], karena struk yang
  /// diretur lewat jalur lama menyimpan 0 di kolom itu.
  double get refundRatio {
    if (isRefunded) return 1;
    if (total <= 0) return 0;
    final r = refundedAmount > total ? total : refundedAmount;
    return r / total;
  }

  /// Nominal yang dikembalikan ke pelanggan. Untuk retur PENUH nilainya seluruh
  /// [total] — bukan [refundedAmount], yang bisa 0 pada struk lama.
  double get refundedValue => total * refundRatio;

  /// Diskon yang benar-benar berlaku setelah retur, proporsional terhadap porsi
  /// yang dikembalikan. Padanan `netAmount(t, 'discount_amount')` di server;
  /// tanpa ini kartu "Total Diskon" offline berbeda dari angka server.
  double get netDiscountTotal => discountTotal * (1 - refundRatio);

  /// Kuantitas yang benar-benar terjual: dikurangi unit yang sudah diretur
  /// (barangnya kembali ke rak). Padanan `quantity - refunded_qty` di server.
  int get netQty {
    if (isRefunded) return 0;
    return items.fold(0, (sum, it) => sum + it.remainingQty);
  }

  /// True bila transaksi ini terhitung sebagai PENJUALAN.
  ///
  /// Yang dihitung: lunas + diretur sebagian (pelanggannya nyata dan tetap
  /// membayar sebagian). Yang TIDAK: diretur penuh, belum dibayar, dibatalkan.
  ///
  /// Sengaja tidak cukup `!isRefunded`: daftar riwayat dari
  /// `GET /outlets/:id/transactions` memuat SEMUA status (unpaid, cancelled,
  /// dst) karena mobile memanggilnya tanpa filter status, jadi predikat itu
  /// akan menghitung bill yang belum dibayar sebagai omzet. Definisi ini
  /// menyamai server, yang menghitung 'paid' + 'partially_refunded'
  /// (lihat report/refund_netting.go), supaya angka kasir dan owner sama.
  bool get countsAsSale => isPaid || isPartiallyRefunded;

  /// True bila masih ada minimal satu item yang bisa diretur
  /// (quantity - refunded_qty > 0). Dipakai untuk menampilkan opsi
  /// "Refund sebagian" dan menggate tombol refund pada transaksi yang
  /// sudah diretur sebagian.
  bool get hasRefundableItems => items.any((it) => it.remainingQty > 0);

  /// Maps from Go backend entity Transaction JSON.
  /// Backend tidak punya status 'refunded' di kolom payment_status —
  /// status refund dideteksi dari refunded_at != null.
  factory Sale.fromJson(Map<String, dynamic> json) {
    final refundedAt = json['refunded_at'] != null
        ? DateTime.tryParse(json['refunded_at'].toString())?.toLocal()
        : null;
    final paidAt = json['paid_at'] != null
        ? DateTime.tryParse(json['paid_at'].toString())?.toLocal()
        : null;
    final confirmedAt = json['confirmed_at'] != null
        ? DateTime.tryParse(json['confirmed_at'].toString())?.toLocal()
        : null;
    // payment_status kini bisa: paid | unpaid | refunded | partially_refunded.
    // Retur sebagian TIDAK dianggap refund penuh (isRefunded) walau backend
    // ikut mengisi refunded_at — pembeda: status 'partially_refunded'.
    final statusLower = json['payment_status']?.toString().toLowerCase();
    final isPartial = statusLower == 'partially_refunded';
    final sale = Sale(
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
      subtotal: _d(json['subtotal_amount']),
      originalSubtotal: _d(json['subtotal_amount']),
      tax: _d(json['tax_amount']),
      discountTotal: _d(json['discount_amount']),
      serviceCharge: _d(json['service_charge']),
      total: _d(json['final_amount']),
      paymentMethod: json['payment_method']?.toString() ?? '',
      cashAmount: _d(json['cash_amount']),
      changeAmount: _d(json['change_amount']),
      customerName: json['customer_name']?.toString() ?? '',
      orderType: json['order_type']?.toString() ?? 'Dine In',
      invoiceId: json['invoice_no']?.toString() ?? '',
      isPaid: json['payment_status'] == 'paid',
      paymentStatus: statusLower ?? 'unpaid',
      paidAt: paidAt,
      confirmedAt: confirmedAt,
      fulfillmentStatus:
          json['fulfillment_status']?.toString() ?? 'pending',
      queueNo: (json['queue_no'] as num?)?.toInt(),
      paymentRef: json['payment_ref']?.toString(),
      note: json['note']?.toString(),
      // Backend juga set `payment_status = 'refunded'` di endpoint refund
      // baru (lihat repository.Refund). Cek both supaya kompat data lama
      // (yang cuma punya refunded_at) maupun data baru (status='refunded').
      // Retur SEBAGIAN dikecualikan: refunded_at bisa terisi tapi status
      // 'partially_refunded' → bukan refund penuh.
      isRefunded: statusLower == 'refunded' ||
          (refundedAt != null && !isPartial),
      isPartiallyRefunded: isPartial,
      refundedAmount: _d(json['refunded_amount']),
      refundedAt: refundedAt,
      refundedBy: json['refunded_by']?.toString(),
      refundReason: json['refund_reason']?.toString(),
      cashierRemoteId: json['user_id']?.toString() ?? '',
      outletRemoteId: json['outlet_id']?.toString(),
      tableId: json['table_id']?.toString(),
      // table_name & table_group_name dikirim backend via JOIN ke
      // pos_tables / table_groups (lihat transactionWithTableSelect di
      // repository). Null aman: dine-in tanpa meja atau bukan dine-in
      // sama sekali (takeaway). Trim() supaya whitespace dari backend
      // string tidak bocor ke UI.
      tableName: () {
        final s = json['table_name']?.toString().trim();
        return (s == null || s.isEmpty) ? null : s;
      }(),
      tableGroupName: () {
        final s = json['table_group_name']?.toString().trim();
        return (s == null || s.isEmpty) ? null : s;
      }(),
      paymentProofUrl: json['payment_proof_url']?.toString(),
      // Backend field baru dari migration 000051. Backward-compat:
      // kalau tidak ada (dipanggil dari endpoint legacy), default 'kasir'.
      source: json['source']?.toString() ?? 'kasir',
    );
    sale.id = json['id']?.toString() ?? '';

    if (json['items'] is List) {
      sale.items = (json['items'] as List)
          .map((e) => SaleItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return sale;
  }

  Map<String, dynamic> toJson() {
    return {
      'payment_method': paymentMethod,
      'items': items.map((e) => e.toJson()).toList(),
    };
  }

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
