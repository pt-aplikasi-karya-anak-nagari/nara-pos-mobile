import 'dart:math';

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/image_compress.dart';
import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/connectivity_service.dart';
import '../../../core/offline/entity_cache.dart';
import '../../../core/offline/sale_outbox.dart';
import '../../kasir/domain/cart_item.dart';
import '../domain/sale.dart';
import '../domain/sale_item.dart';
import '../../../core/outlet_scope.dart';
import '../../shifts/data/shift_repository.dart';

/// Cache offline riwayat transaksi per outlet. Menyimpan RAW JSON dari API
/// (codec identity) → fidelitas penuh tanpa perlu serializer model. Dipakai
/// untuk lihat & cetak ulang struk transaksi yang sudah tersinkron saat offline.
final _salesRawCache = EntityCache<Map<String, dynamic>>(
  'sales',
  toJson: (m) => m,
  fromJson: (m) => m,
);

class TransactionApiService extends BaseApiService {
  TransactionApiService(super.dio);

  Future<Map<String, dynamic>> checkout(String outletId, Map<String, dynamic> data) async {
    return await post<Map<String, dynamic>>(
      '/transactions/checkout/$outletId',
      data: data,
      converter: (res) => res as Map<String, dynamic>,
    );
  }

  /// Riwayat transaksi outlet. Backend mendukung filter opsional:
  /// [search] (LIKE invoice_no / customer_name), [status]
  /// (paid|unpaid|refunded), [paymentMethod], serta rentang tanggal
  /// [dateFrom]/[dateTo] (format YYYY-MM-DD, inclusive). Param hanya
  /// dikirim bila non-empty supaya envelope response tetap konsisten.
  Future<List<dynamic>> getHistory(
    String outletId, {
    int page = 1,
    int limit = 100,
    String? search,
    String? status,
    String? source,
    String? paymentMethod,
    String? dateFrom,
    String? dateTo,
  }) async {
    return await get<List<dynamic>>(
      '/transactions/outlet/$outletId',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (status != null && status.isNotEmpty) 'status': status,
        if (source != null && source.isNotEmpty) 'source': source,
        if (paymentMethod != null && paymentMethod.isNotEmpty)
          'payment_method': paymentMethod,
        if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
      },
      converter: (res) => res as List<dynamic>,
    );
  }

  Future<Map<String, dynamic>> getDetail(String transactionId) async {
    return await get<Map<String, dynamic>>(
      '/transactions/$transactionId',
      converter: (res) => res as Map<String, dynamic>,
    );
  }

  /// Riwayat transaksi untuk satu pelanggan.
  Future<List<dynamic>> getCustomerHistory(String customerId, {int page = 1, int limit = 100}) async {
    return await get<List<dynamic>>(
      '/customers/$customerId/transactions',
      queryParameters: {'page': page, 'limit': limit},
      converter: (res) => res as List<dynamic>,
    );
  }

  /// Refund transaksi. [overridePin] wajib bila outlet mengaktifkan
  /// `require_pin_refund` — backend memverifikasi PIN manajer berwenang dan
  /// membalas HTTP 403 dengan pesan jelas bila PIN salah/kosong.
  ///
  /// [items] opsional untuk retur PARSIAL: daftar
  /// `{transaction_item_id, quantity}`. Bila null/kosong, backend melakukan
  /// refund PENUH (perilaku lama). Bila diisi, hanya qty item tsb yang
  /// diretur & di-restock; nominal dihitung server.
  Future<Map<String, dynamic>> refund(
    String transactionId, {
    String? reason,
    String? overridePin,
    List<Map<String, dynamic>>? items,
  }) async {
    return await post<Map<String, dynamic>>(
      '/transactions/$transactionId/refund',
      data: {
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (overridePin != null && overridePin.isNotEmpty)
          'override_pin': overridePin,
        if (items != null && items.isNotEmpty) 'items': items,
      },
      converter: (res) => res as Map<String, dynamic>,
    );
  }

  /// Batalkan (void) transaksi UNPAID — bill "Bayar Nanti" yang salah input.
  /// Backend set status=cancelled, restore stok, lepas meja. Reason opsional.
  /// [overridePin] wajib bila outlet mengaktifkan `require_pin_void` (backend
  /// balas 403 bila PIN salah/kosong).
  Future<Map<String, dynamic>> voidTransaction(
    String transactionId, {
    String? reason,
    String? overridePin,
  }) async {
    return await post<Map<String, dynamic>>(
      '/transactions/$transactionId/void',
      data: {
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (overridePin != null && overridePin.isNotEmpty)
          'override_pin': overridePin,
      },
      converter: (res) => res as Map<String, dynamic>,
    );
  }

  /// Pindah / gabung bill antar meja — reassign transaksi aktif dari meja
  /// asal ke meja tujuan. Return payload {moved: n}.
  Future<Map<String, dynamic>> moveTable(
    String outletId,
    String fromTableId,
    String toTableId,
  ) async {
    return await post<Map<String, dynamic>>(
      '/outlets/$outletId/postables/move',
      data: {'from_table_id': fromTableId, 'to_table_id': toTableId},
      converter: (res) => res as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> markAsPaid(
    String transactionId, {
    required String paymentMethod,
    double cashAmount = 0,
    double changeAmount = 0,
    String? paymentProofUrl,
  }) async {
    return await post<Map<String, dynamic>>(
      '/transactions/$transactionId/mark-as-paid',
      data: {
        'payment_method': paymentMethod,
        'cash_amount': cashAmount,
        'change_amount': changeAmount,
        if (paymentProofUrl != null && paymentProofUrl.isNotEmpty)
          'payment_proof_url': paymentProofUrl,
      },
      converter: (res) => res as Map<String, dynamic>,
    );
  }

  /// Konfirmasi/terima pesanan QR yang SUDAH lunas (pelanggan bayar QRIS di
  /// depan). Tidak ada verifikasi bayar — kasir cukup menerima pesanan.
  Future<Map<String, dynamic>> confirmMenuOrder(String transactionId) async {
    return await post<Map<String, dynamic>>(
      '/transactions/$transactionId/confirm-order',
      converter: (res) => res as Map<String, dynamic>,
    );
  }

  /// Majukan tahap penyelesaian pesanan QR:
  /// received → preparing → delivering → completed.
  Future<Map<String, dynamic>> setOrderStatus(
    String transactionId,
    String status,
  ) async {
    return await post<Map<String, dynamic>>(
      '/transactions/$transactionId/order-status',
      data: {'status': status},
      converter: (res) => res as Map<String, dynamic>,
    );
  }

  /// Tolak bukti pembayaran dari customer (QR menu). Backend men-clear
  /// kolom `payment_proof_url`; status tetap unpaid sehingga customer di
  /// mako-scan-qr diminta upload ulang. Tidak butuh payload — kasir hanya
  /// menekan tombol tolak setelah cek bukti.
  Future<Map<String, dynamic>> rejectPaymentProof(String transactionId) async {
    return await post<Map<String, dynamic>>(
      '/transactions/$transactionId/reject-proof',
      data: const {},
      converter: (res) => res as Map<String, dynamic>,
    );
  }

  /// Ambil daftar transaksi unpaid yang sedang dijalankan di meja [tableId].
  /// Backend mengurutkan dari yang paling lama dibuat sehingga UI bisa
  /// langsung memakai item pertama untuk hitung durasi sejak order pertama.
  Future<List<dynamic>> getActiveByTable(String tableId) async {
    return await get<List<dynamic>>(
      '/postables/$tableId/active-transactions',
      converter: (res) => res as List<dynamic>,
    );
  }

  /// Upload bukti pembayaran ke backend. Mengembalikan URL relatif yang
  /// kemudian dipakai sebagai nilai `payment_proof_url` di payload
  /// checkout / mark-as-paid.
  ///
  /// File di-kompres dulu (JPEG q=50, max 1600 px) di main app sebelum
  /// upload supaya jaringan cafe yang lambat tidak terbebani foto 4MB.
  Future<String> uploadPaymentProof(String filePath) async {
    final compressedPath = await ImageCompress.compressFile(filePath);
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        compressedPath,
        filename: compressedPath.split('/').last,
      ),
    });
    final res = await dio.post<Map<String, dynamic>>(
      '/transactions/payment-proof',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        responseType: ResponseType.json,
      ),
    );
    final body = res.data;
    if (body == null) return '';
    final data = body['data'];
    return (data is Map ? data['payment_proof_url']?.toString() : null) ?? '';
  }
}

final transactionApiServiceProvider = Provider<TransactionApiService>((ref) {
  return TransactionApiService(ref.watch(dioProvider));
});

class TransactionRepository {
  final TransactionApiService apiService;
  final Ref _ref;

  TransactionRepository(this.apiService, this._ref);

  Future<Sale> saveFromCart({
    required List<CartItem> cart,
    required double subtotal,
    required double originalSubtotal,
    required double tax,
    required double total,
    double discountTotal = 0,
    double serviceCharge = 0,
    required String paymentMethod,
    double cashAmount = 0,
    double changeAmount = 0,
    String customerName = '',
    String orderType = 'Dine In',
    String cashierId = '',
    String cashierName = '',
    int outletId = 0,
    String? outletRemoteId,
    String outletName = '',
    bool isPaid = true,
    String? customerId,
    int pointsEarned = 0,
    // displayPointsEarned: poin yang sudah di-boost tier, untuk Sale/struk lokal.
    // API tetap menerima pointsEarned (base) — backend yang mem-boost, jangan
    // dobel. Bila null → pakai pointsEarned (perilaku lama).
    int? displayPointsEarned,
    int pointsUsed = 0,
    String? promoCode,
    String? tableId,
    String? tableName,
    String? paymentProofUrl,
    // E7: rincian split/multi-tender payment. Tiap entri = {payment_method,
    // amount, reference?}. Bila null/kosong → single-method (pakai paymentMethod).
    // Ikut tersimpan di payload outbox sehingga jalur offline pun mengirim split
    // saat sync.
    List<Map<String, dynamic>>? payments,
  }) async {
    // Idempotency key: digenerate sekali per checkout dan ikut tersimpan di
    // payload outbox. Saat transaksi offline di-retry, ref yang SAMA dikirim
    // ulang sehingga backend tidak membuat duplikat (lihat migration 000103).
    final clientRef =
        'cr_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(0x7fffffff)}';

    // Waktu bisnis transaksi: kapan sale BENAR-BENAR terjadi di kasir. Disimpan
    // DI DALAM payload outbox supaya bertahan saat replay offline. Backend
    // memakainya untuk created_at (bukan waktu sync), sehingga sale yang dibuat
    // offline lalu ter-sync belakangan tetap mendarat di hari/jam yang benar di
    // laporan, dan urut secara kronologis di dalam shift-nya. Format UTC ISO8601
    // — mengikuti pola occurred_at pada buka/tutup shift.
    final occurredAt = DateTime.now().toUtc().toIso8601String();

    // Ikat sale ke shift TEMPAT ia dibuat (bukan shift yang kebetulan aktif saat
    // sync — penting untuk sale offline yang di-replay belakangan). shift_id =
    // server id bila shift sudah tersinkron; shift_client_ref = open_client_ref
    // bila shift dibuka offline. Backend resolve via salah satunya (lalu
    // fallback GetActiveShift). Keduanya ikut tersimpan di payload outbox.
    final activeShift = _ref.read(activeShiftProvider).value;

    final checkoutData = {
      'payment_method': paymentMethod,
      'client_ref': clientRef,
      'occurred_at': occurredAt,
      'shift_id': activeShift?.remoteId ?? '',
      'shift_client_ref': activeShift?.clientRef ?? '',
      'customer_name': customerName,
      'customer_id': customerId ?? '',
      'order_type': orderType,
      'subtotal_amount': subtotal,
      'tax_amount': tax,
      'discount_amount': discountTotal,
      'service_charge': serviceCharge,
      'final_amount': total,
      'cash_amount': cashAmount,
      'change_amount': changeAmount,
      // E7: kirim rincian tender bila split payment. Backend memvalidasi
      // Σ(amount) == final_amount lalu menyimpan ke transaction_payments.
      if (payments != null && payments.isNotEmpty) 'payments': payments,
      'is_paid': isPaid,
      // Bukti pembayaran (foto QRIS scan / struk transfer) — opsional;
      // kalau cash atau user skip upload, kirim string kosong.
      'payment_proof_url': paymentProofUrl ?? '',
      // Backend memakai field ini untuk update poin pelanggan
      // (lihat transactionService.CreateTransaction → AddPoints).
      // Kalau tidak dikirim, delta = 0 dan poin pelanggan tidak akan berubah.
      'points_earned': pointsEarned,
      'points_used': pointsUsed,
      // Kode promo (opsional). Backend memvalidasi keabsahannya & mencatat
      // pemakaian; nominal diskonnya sudah termasuk di discount_amount/final.
      'promo_code': promoCode ?? '',
      // Kirim table_id supaya backend bisa: (1) mengunci meja jadi
      // "occupied" otomatis, (2) menampilkan transaksi ini di dialog
      // detail meja, (3) membebaskan meja saat semua transaksi di meja
      // ini lunas. Empty string = tidak terkait meja (Take Away dll).
      'table_id': tableId ?? '',
      'items': cart.map((item) => {
        'product_id': item.product.remoteId ?? '',
        'quantity': item.qty,
        if (item.variantId != null) 'variant_id': item.variantId,
        'name': item.displayName,
        'price': item.effectivePrice,
        if (item.note.trim().isNotEmpty) 'note': item.note.trim(),
        // Snapshot diskon per item (manual override > diskon master produk).
        // Backend pakai field ini untuk mengisi kolom diskon di transaction_items
        // sehingga riwayat / laporan / struk konsisten dengan apa yang
        // ditampilkan di kasir.
        'discount_type': item.effectiveDiscountType,
        'discount_value': item.effectiveDiscountValue,
        'discount_name': item.effectiveDiscountName,
        // C4: snapshot add-on/topping (harga sudah termasuk di price di atas).
        if (item.modifiers.isNotEmpty)
          'modifiers':
              item.modifiers.map((m) => m.toCheckoutJson()).toList(),
      }).toList(),
    };

    final oId = outletRemoteId ?? outletId.toString();

    // Bangun Sale optimistic dari data keranjang untuk jalur offline —
    // dipakai supaya struk tetap bisa dicetak & cart bisa dikosongkan
    // walau belum ada respons backend.
    Future<Sale> queueOffline() async {
      final localId =
          await _ref.read(saleOutboxProvider).enqueue(oId, checkoutData);
      await _ref.read(pendingSyncCountProvider.notifier).refresh();
      final sale = Sale(
        createdAt: DateTime.now(),
        subtotal: subtotal,
        originalSubtotal: originalSubtotal,
        tax: tax,
        discountTotal: discountTotal,
        serviceCharge: serviceCharge,
        total: total,
        paymentMethod: paymentMethod,
        cashAmount: cashAmount,
        changeAmount: changeAmount,
        customerName: customerName,
        orderType: orderType,
        invoiceId: 'OFFLINE',
        isPaid: isPaid,
        cashierName: cashierName,
        outletName: outletName,
        // Struk lokal menampilkan poin yang sudah di-boost (bila ada); payload
        // API (checkoutData.points_earned) tetap base — backend yang mem-boost.
        pointsEarned: displayPointsEarned ?? pointsEarned,
        pointsUsed: pointsUsed,
        tableId: tableId,
        tableName: tableName,
        pendingSync: true,
      );
      sale.id = localId;
      sale.items = cart
          .map((item) => SaleItem(
                productRemoteId: item.product.remoteId ?? '',
                productName: item.product.name,
                productEmoji: item.product.emoji,
                variant: item.variantName,
                price: item.effectivePrice,
                originalPrice: item.basePrice,
                qty: item.qty,
                note: item.note,
                modifiersLabel: item.modifiersLabel,
              ))
          .toList();
      return sale;
    }

    // Kalau perangkat sudah diketahui offline, langsung antrekan tanpa
    // menunggu timeout jaringan. Bila status tak diketahui, tetap coba
    // kirim; saat gagal karena koneksi, fallback ke antrian offline.
    if (_ref.read(isOfflineProvider)) {
      return queueOffline();
    }
    try {
      final response = await apiService.checkout(oId, checkoutData);
      return Sale.fromJson(response);
    } catch (e) {
      if (isOfflineError(e)) return queueOffline();
      rethrow;
    }
  }

  Stream<List<Sale>> watchAll() { return Stream.value([]); }
  
  Future<Sale> getDetail(String id) async {
    final res = await apiService.getDetail(id);
    return Sale.fromJson(res);
  }

  Sale? getById(String id) { return null; }

  /// Cari transaksi berdasarkan invoice number (mis. "INV-1234").
  /// Memuat history outlet lalu filter — cocok untuk scan QR struk.
  Future<Sale?> findByInvoiceId(String outletId, String invoiceId) async {
    final all = await getAllSales(outletId);
    for (final s in all) {
      if (s.invoiceId == invoiceId || s.id == invoiceId) return s;
    }
    return null;
  }
  /// Ambil daftar pesanan yang sedang berjalan (unpaid) di sebuah meja.
  /// Hasilnya sudah menyertakan items per transaksi (lihat
  /// transactionRepository.GetActiveByTable di backend), jadi UI bisa
  /// langsung menampilkan rincian tanpa perlu fetch detail satu per satu.
  Future<List<Sale>> getActiveSalesByTable(String tableId) async {
    final res = await apiService.getActiveByTable(tableId);
    return res.map((e) => Sale.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Pindahkan / gabungkan semua bill aktif dari meja asal ke meja tujuan.
  /// Kalau meja tujuan sudah terisi → gabung bill. Return jumlah pesanan
  /// yang dipindah. Backend juga mengatur status meja (asal lepas, tujuan
  /// terisi).
  Future<int> moveTableSales(
    String outletId,
    String sourceTableId,
    String targetTableId,
  ) async {
    final res = await apiService.moveTable(
      outletId,
      sourceTableId,
      targetTableId,
    );
    final moved = res['moved'];
    return moved is int ? moved : int.tryParse('${moved ?? 0}') ?? 0;
  }

  /// Refund transaksi: backend balikkan stok, set status refunded, kurangi
  /// poin pelanggan. Mengembalikan Sale terbaru dari backend. [overridePin]
  /// diteruskan bila outlet mensyaratkan PIN otorisasi manajer.
  ///
  /// [items] opsional (retur PARSIAL): daftar `{transaction_item_id,
  /// quantity}`. Null/kosong → refund PENUH (perilaku lama).
  Future<Sale> refund(
    String saleId, {
    String? reason,
    String? overridePin,
    List<Map<String, dynamic>>? items,
  }) async {
    final res = await apiService.refund(
      saleId,
      reason: reason,
      overridePin: overridePin,
      items: items,
    );
    return Sale.fromJson(res);
  }

  /// Void transaksi UNPAID (bill "Bayar Nanti" yang salah input). Backend
  /// set status=cancelled, restore stok, lepas meja bila sudah kosong.
  /// [overridePin] diteruskan bila outlet mensyaratkan PIN otorisasi manajer.
  Future<Sale> voidSale(String saleId, {String? reason, String? overridePin}) async {
    final res = await apiService.voidTransaction(
      saleId,
      reason: reason,
      overridePin: overridePin,
    );
    return Sale.fromJson(res);
  }

  /// Lunasi transaksi yang masih unpaid. Backend akan link ke shift aktif
  /// user, set paid_at, dan beri poin pelanggan.
  ///
  /// [paymentProofUrl] opsional. Kalau di-set (mis. pembayaran QRIS yang
  /// fotonya sudah di-upload terlebih dulu), nilainya disimpan di kolom
  /// payment_proof_url transaksi.
  Future<Sale> markAsPaid(String saleId, {required String paymentMethod, double cashAmount = 0, double changeAmount = 0, String? paymentProofUrl}) async {
    final res = await apiService.markAsPaid(
      saleId,
      paymentMethod: paymentMethod,
      cashAmount: cashAmount,
      changeAmount: changeAmount,
      paymentProofUrl: paymentProofUrl,
    );
    return Sale.fromJson(res);
  }

  /// Konfirmasi/terima pesanan QR yang sudah lunas. Kasir cukup menerima —
  /// tidak ada verifikasi bayar.
  Future<Sale> confirmMenuOrder(String saleId) async {
    final res = await apiService.confirmMenuOrder(saleId);
    return Sale.fromJson(res);
  }

  /// Majukan tahap penyelesaian pesanan QR (received→...→completed).
  Future<Sale> setOrderStatus(String saleId, String status) async {
    final res = await apiService.setOrderStatus(saleId, status);
    return Sale.fromJson(res);
  }

  /// Upload foto bukti pembayaran ke backend. Wrapper tipis ke api service.
  Future<String> uploadPaymentProof(String filePath) async {
    return apiService.uploadPaymentProof(filePath);
  }

  /// Tolak bukti pembayaran customer (QR menu). Backend men-clear kolom
  /// payment_proof_url; status tetap unpaid, sehingga customer di mako-
  /// scan-qr diminta upload bukti ulang.
  Future<Sale> rejectPaymentProof(String saleId) async {
    final res = await apiService.rejectPaymentProof(saleId);
    return Sale.fromJson(res);
  }

  Future<List<Sale>> getAllSales(String outletId) async {
    // Cache-aware: online → simpan raw JSON & kembalikan; offline → layani
    // dari cache supaya riwayat & cetak ulang struk tetap jalan tanpa koneksi.
    final raw = await readThroughCache<Map<String, dynamic>>(
      cache: _salesRawCache,
      outletId: outletId,
      fetch: () async {
        final res = await apiService.getHistory(outletId);
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      },
    );
    return raw.map(Sale.fromJson).toList();
  }

  Future<List<Sale>> getPaginatedHistory(
    String outletId, {
    int page = 1,
    int limit = 10,
    String? search,
    String? status,
    String? paymentMethod,
    String? dateFrom,
    String? dateTo,
  }) async {
    final res = await apiService.getHistory(
      outletId,
      page: page,
      limit: limit,
      search: search,
      status: status,
      paymentMethod: paymentMethod,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    return res.map((e) => Sale.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Riwayat transaksi pelanggan tertentu (untuk halaman detail pelanggan).
  Future<List<Sale>> getCustomerSales(String customerId) async {
    final res = await apiService.getCustomerHistory(customerId);
    return res.map((e) => Sale.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Pesanan QR (source=menu_qr) yang masih AKTIF: sudah LUNAS tapi belum
  /// selesai (fulfillment belum 'completed'). Auto-pay QRIS: pesanan dibuat
  /// UNPAID lalu ditandai lunas + auto-konfirmasi saat dibayar; yang masih
  /// menunggu pembayaran belum perlu ditangani kasir → tidak ditampilkan.
  /// Kasir memajukan statusnya (diterima → dipersiapkan → diantar → selesai).
  Future<List<Sale>> getMenuOrders(String outletId) async {
    final res = await apiService.getHistory(
      outletId,
      source: 'menu_qr',
      limit: 50,
    );
    return res
        .map((e) => Sale.fromJson(e as Map<String, dynamic>))
        .where(
          // Aktif = LUNAS (auto-pay QRIS), ATAU sudah dikonfirmasi/masuk dapur
          // walau belum bayar (open-bill: tab jalan, dilunasi di kasir), ATAU
          // unpaid TANPA charge gateway (pilihan "bayar di kasir" — kasir harus
          // menagih lalu Tandai Lunas). Menunggu-QRIS (ada paymentRef) tetap
          // disembunyikan — belum perlu ditangani.
          (s) =>
              (s.isPaid ||
                  s.isConfirmed ||
                  (!s.isPaid && !s.isConfirmed && s.paymentRef == null)) &&
              s.fulfillmentStatus != 'completed' &&
              !s.isRefunded,
        )
        .toList();
  }
}

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepository(ref.watch(transactionApiServiceProvider), ref);
});

final salesFutureProvider = FutureProvider<List<Sale>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return [];
  return ref.watch(transactionRepositoryProvider).getAllSales(outletId);
});

/// Pesanan QR menu (unpaid) untuk outlet aktif — tab "Pesanan Meja" kasir.
final menuOrdersProvider = FutureProvider<List<Sale>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return [];
  return ref.watch(transactionRepositoryProvider).getMenuOrders(outletId);
});

final transactionDetailProvider = FutureProvider.family<Sale, String>((ref, id) async {
  return ref.watch(transactionRepositoryProvider).getDetail(id);
});

/// Riwayat pembelian satu pelanggan, di-fetch dari backend dan auto-refetch
/// saat di-invalidate (mis. setelah checkout).
final customerSalesProvider =
    FutureProvider.family<List<Sale>, String>((ref, customerId) async {
  return ref.watch(transactionRepositoryProvider).getCustomerSales(customerId);
});

/// Daftar transaksi unpaid yang sedang berjalan di satu meja. Dipakai
/// dialog detail meja occupied untuk menampilkan rincian pesanan yang
/// sedang disajikan ke tamu (item, durasi sejak order, total).
///
/// Auto-refetch saat di-invalidate, mis. setelah checkout meja yang sama
/// atau setelah staff melunasi salah satu transaksinya.
final activeTableTransactionsProvider =
    FutureProvider.family<List<Sale>, String>((ref, tableId) async {
  if (tableId.isEmpty) return const [];
  return ref.watch(transactionRepositoryProvider).getActiveSalesByTable(tableId);
});
