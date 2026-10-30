import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/image_compress.dart';
import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/connectivity_service.dart';
import '../../../core/offline/entity_cache.dart';
import '../../../core/offline/product_cache.dart';
import '../../../core/device_identity.dart';
import '../../../core/offline/jam_offline.dart';
import '../../../core/offline/tanda_tangan.dart';
import '../../../core/offline/nomor_struk_offline.dart';
import '../../../core/offline/sale_outbox.dart';
import '../../customers/data/customer_repository.dart';
import '../../kasir/domain/cart_item.dart';
import '../../kasir/domain/batas_diskon.dart';
import '../domain/sale.dart';
import '../domain/sale_item.dart';
import '../../../core/outlet_scope.dart';
import '../../shifts/data/shift_repository.dart';
import '../../settings/data/app_settings.dart';
import '../../subscription/data/subscription_repository.dart';
import '../../subscription/domain/subscription.dart';
import 'pelunasan_offline.dart';
import 'transaksi_offline.dart';
import '../../user/data/auth_service.dart';

/// Cache offline riwayat transaksi per outlet. Menyimpan RAW JSON dari API
/// (codec identity) → fidelitas penuh tanpa perlu serializer model. Dipakai
/// untuk lihat & cetak ulang struk transaksi yang sudah tersinkron saat offline.
final _salesRawCache = EntityCache<Map<String, dynamic>>(
  'sales',
  toJson: (m) => m,
  fromJson: (m) => m,
);

/// Tab (transaksi aktif) per meja, kunci = ID meja.
final _tabMejaCache = EntityCache<Map<String, dynamic>>(
  'tab_meja',
  toJson: (m) => m,
  fromJson: (m) => m,
);

class TransactionApiService extends BaseApiService {
  TransactionApiService(super.dio);

  Future<Map<String, dynamic>> checkout(
    String outletId,
    Map<String, dynamic> data,
  ) async {
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
  Future<List<dynamic>> getCustomerHistory(
    String customerId, {
    int page = 1,
    int limit = 100,
  }) async {
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
  /// Kirim struk transaksi ke WhatsApp pelanggan. Isi pesan disusun
  /// backend; [phone] kosong = pakai nomor yang tercatat di transaksi.
  /// Mengembalikan nomor tujuan yang sudah dinormalkan (62…).
  Future<String> kirimStrukWa(String transactionId, {String? phone}) async {
    final res = await post<Map<String, dynamic>>(
      '/transactions/$transactionId/receipt/whatsapp',
      data: {if (phone != null && phone.trim().isNotEmpty) 'phone': phone},
      converter: (res) => res as Map<String, dynamic>,
    );
    return res['sent_to']?.toString() ?? '';
  }

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

  /// Pelunasan "Bayar Nanti" yang dilakukan saat offline (dari antrian).
  /// Hanya [data]['transaction_ids'] yang dilunasi; idempoten per client_ref.
  Future<Map<String, dynamic>> lunasiOffline(
    String outletId,
    Map<String, dynamic> data,
  ) async {
    return await post<Map<String, dynamic>>(
      '/transactions/offline/lunasi/$outletId',
      data: data,
      converter: (res) =>
          res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{},
    );
  }

  /// Open bill: lunasi SELURUH tab satu meja (semua ronde unpaid yang tampil di
  /// tab) sekali bayar. Backend menutup semua ronde secara atomik & membebaskan
  /// meja. Mengembalikan {table_id, settled_count, tab_total, ...}.
  Future<Map<String, dynamic>> settleTable(
    String outletId,
    String tableId, {
    required String paymentMethod,
    double cashAmount = 0,
    double changeAmount = 0,
    String? paymentProofUrl,
  }) async {
    return await post<Map<String, dynamic>>(
      '/transactions/outlet/$outletId/tables/$tableId/settle',
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

  /// Transaksi milik satu shift, untuk rekap tender & cetak laporan tutup
  /// kasir. Backend mengurutkannya dari yang paling awal dan MEMUAT ITEMNYA
  /// (loadItemsForTransactions), jadi struk bisa langsung dicetak tanpa fetch
  /// detail satu per satu.
  Future<List<dynamic>> getByShift(String shiftId) async {
    return await get<List<dynamic>>(
      '/shifts/$shiftId/transactions',
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
    // Potongan promo resmi + tukar poin yang dihitung aplikasi dari aturan
    // outlet — dikecualikan dari batas diskon kasir saat offline (sama
    // dengan server).
    double diskonResmi = 0,
    // Jatuh tempo Bayar Nanti (hanya bila !isPaid). Null = hari ini.
    DateTime? jatuhTempo,
    String? tableId,
    String? tableName,
    String? paymentProofUrl,
    // E7: rincian split/multi-tender payment. Tiap entri = {payment_method,
    // amount, reference?}. Bila null/kosong → single-method (pakai paymentMethod).
    // Ikut tersimpan di payload outbox sehingga jalur offline pun mengirim split
    // saat sync.
    List<Map<String, dynamic>>? payments,
    // B1c: PIN otorisasi manajer. Hanya diisi saat checkout pertama ditolak
    // backend karena diskon melampaui batas kasir (`max_discount_percent`) dan
    // kasir mengulang dengan PIN. Null/kosong → tidak dikirim (perilaku lama).
    String? overridePin,
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
      if (!isPaid && jatuhTempo != null)
        'jatuh_tempo': tanggalJatuhTempo(jatuhTempo),
      // Bukti pembayaran (foto QRIS scan / struk transfer) — opsional;
      // kalau cash atau user skip upload, kirim string kosong.
      'payment_proof_url': paymentProofUrl ?? '',
      // B1c: PIN otorisasi manajer bila diskon melampaui batas kasir. Dikirim
      // hanya bila diisi — checkout normal (diskon di bawah batas) tak
      // menyertakannya sehingga perilaku lama tidak berubah.
      if (overridePin != null && overridePin.isNotEmpty)
        'override_pin': overridePin,
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
      'items': cart
          .map(
            (item) => {
              'product_id': item.product.remoteId ?? '',
              'quantity': item.qty,
              if (item.variantId != null) 'variant_id': item.variantId,
              'name': item.displayName,
              'price': item.effectivePrice,
              // Harga dasar produk/varian saat penjualan (sebelum diskon &
              // add-on). Dipakai server HANYA untuk transaksi offline, bila
              // harganya sudah diubah sebelum transaksi sempat terkirim.
              'base_price': item.basePrice,
              // Snapshot flag pajak per item. Server otoritatif atas pajak &
              // mengecualikan item non-pajak; dikirim agar payload konsisten
              // dengan preview kasir.
              'is_taxable': item.isTaxable,
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
                'modifiers': item.modifiers
                    .map((m) => m.toCheckoutJson())
                    .toList(),
            },
          )
          .toList(),
    };

    final oId = outletRemoteId ?? outletId.toString();

    // Bangun Sale optimistic dari data keranjang untuk jalur offline —
    // dipakai supaya struk tetap bisa dicetak & cart bisa dikosongkan
    // walau belum ada respons backend.
    Future<Sale> queueOffline() async {
      // DISKON DI ATAS BATAS KASIR. Online, server menolaknya lalu aplikasi
      // meminta PIN manajer. Offline, PIN tak bisa diperiksa — menerimanya
      // begitu saja berarti PIN apa pun lolos. Ditolak di sini, sebelum
      // pelanggan menerima diskonnya; kalau tidak, server menolak transaksinya
      // saat sinkron dan omzetnya tak pernah tercatat. PIN yang sudah
      // dimasukkan (checkout online yang terputus di tengah) tetap dikirim dan
      // diperiksa server saat sinkron.
      final pengaturan = await bacaAppSettingsTersimpan(oId);

      // BATAS LAMA OFFLINE. Tablet yang terlalu lama tak tersambung tak boleh
      // terus berjualan: kasir yang dinonaktifkan Pemilik selagi tablet
      // offline baru benar-benar terhenti saat tablet tersambung lagi.
      // Memundurkan jam tablet tak memperpendek hitungannya (jam_offline.dart).
      final jam = _ref.read(jamOfflineProvider);
      final jamMundur = await jam.amati();
      final lamaOffline = jam.lamaOffline();
      // Pengaturan Pemilik, tapi tak pernah lebih longgar dari batas platform.
      final batasOffline = batasOfflineEfektif(pengaturan.maxOfflineHours);
      if (melewatiBatasOffline(lamaOffline, batasOffline)) {
        throw TransaksiOfflineDitolak(
          pesanBatasOffline(lamaOffline!, batasOffline),
        );
      }

      // LANGGANAN. Saat offline server tak bisa menolak; dinilai di sini dari
      // status terakhir yang tersimpan, dengan jam acuan yang tak bisa
      // dimundurkan. Sesudah masa tenggang server menolak transaksinya —
      // berjualan terus offline hanya menumpuk transaksi yang tak diterima.
      final langganan = await bacaLanggananTersimpan(oId);
      if (langganan != null && !bolehJualOffline(langganan, jam.waktuAcuan())) {
        throw TransaksiOfflineDitolak(
          'Langganan outlet sudah berakhir. Sambungkan ke internet dan '
          'perpanjang langganan untuk melanjutkan penjualan — transaksi yang '
          'sudah tersimpan tetap aman.',
        );
      }

      if (overridePin == null || overridePin.isEmpty) {
        final batas = pengaturan.maxDiscountPercent;
        final persen = persenDiskonKasir(
          cart,
          diskonOrder: diskonOrderKasir(
            diskonOrderDari(diskonTotal: discountTotal, keranjang: cart),
            diskonResmi: diskonResmi,
          ),
        );
        if (melebihiBatasDiskon(persen, batas)) {
          throw TransaksiOfflineDitolak(
            'Diskon ${persen.toStringAsFixed(1)}% di atas batas kasir '
            '${batas.toStringAsFixed(0)}%. PIN manajer hanya bisa diperiksa '
            'saat online — kurangi diskonnya, atau tunggu internet kembali.',
          );
        }
      }

      // Penanda transaksi offline untuk server:
      //  - offline_ref: nomor struk yang dicetak (bukan lagi "OFFLINE");
      //  - cashier_id : kasir yang menjual — antrian bisa terkirim saat kasir
      //    lain sudah login, dan server harus mencatat kasir yang benar;
      //  - is_offline : server memakai harga & stok saat penjualan terjadi.
      final nomorStruk = await _ref
          .read(nomorStrukOfflineProvider)
          .berikutnya();
      final kasirId = _ref.read(authProvider).user?.remoteId ?? '';
      final dataOffline = <String, dynamic>{
        ...checkoutData,
        // Perangkat penanda tangan — server mencari kunci publiknya.
        'device_id': DeviceIdentity.current.id,
        'is_offline': true,
        'offline_ref': nomorStruk,
        if (kasirId.isNotEmpty) 'cashier_id': kasirId,
        // Jam tablet terdeteksi dimundurkan: penanda untuk ditinjau Pemilik.
        if (jamMundur) 'jam_mundur': true,
        // Dijual dalam sesi kasir yang dibuka offline (kartu/PIN dicocokkan
        // di perangkat, belum oleh server).
        if (_ref.read(authProvider.notifier).sesiOffline) 'sesi_offline': true,
        // Data struk yang tak dikirim ke server tapi dibutuhkan untuk
        // menampilkan & mencetak ulang transaksi ini dari Riwayat selama
        // belum terkirim (lihat transaksi_offline.dart). Server
        // mengabaikan field yang tak dikenalnya.
        'struk_lokal': {
          'cashier_name': cashierName,
          'outlet_name': outletName,
          'original_subtotal': originalSubtotal,
          'table_name': ?tableName,
          'points_earned': displayPointsEarned ?? pointsEarned,
          'items': [
            for (final item in cart)
              {
                'product_name': item.product.name,
                'emoji': item.product.emoji,
                'variant': item.variantName,
                'original_price': item.basePrice,
                'modifiers_label': item.modifiersLabel,
              },
          ],
        },
      };
      // Tanda tangan perangkat atas isi transaksi, dibuat SEKARANG — isi yang
      // diubah sesudahnya (di antrian / cadangan) terdeteksi server. Gagal
      // menandatangani tak boleh menggagalkan penjualan; server lalu
      // menandainya tanpa_tanda_tangan.
      try {
        dataOffline['tanda_tangan'] = await _ref
            .read(kunciTandaTanganProvider)
            .tandatangani(dataOffline);
      } catch (_) {}
      final localId = await _ref
          .read(saleOutboxProvider)
          .enqueue(oId, dataOffline, localId: SaleOutbox.idLokalBaru());
      await _ref.read(pendingSyncCountProvider.notifier).refresh();

      // Poin yang ditukar ikut berkurang di salinan pelanggan perangkat.
      if (pointsUsed > 0 && (customerId ?? '').isNotEmpty) {
        unawaited(
          _ref
              .read(customerRepositoryProvider)
              .kurangiPoinLokal(oId, customerId!, pointsUsed)
              .catchError((_) {}),
        );
      }

      // Stok di katalog perangkat ikut berkurang, supaya kasir tak menjual
      // melebihi stok selama offline.
      unawaited(
        _ref
            .read(productCacheProvider)
            .kurangiStokLokal(oId, [
              for (final item in cart)
                if ((item.product.remoteId ?? '').isNotEmpty)
                  (
                    productId: item.product.remoteId!,
                    variantId: item.variantId,
                    qty: item.qty,
                  ),
            ])
            .catchError((_) {}),
      );
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
        invoiceId: nomorStruk,
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
          .map(
            (item) => SaleItem(
              productRemoteId: item.product.remoteId ?? '',
              productName: item.product.name,
              productEmoji: item.product.emoji,
              variant: item.variantName,
              price: item.effectivePrice,
              originalPrice: item.basePrice,
              qty: item.qty,
              note: item.note,
              modifiersLabel: item.modifiersLabel,
            ),
          )
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

  Stream<List<Sale>> watchAll() {
    return Stream.value([]);
  }

  Future<Sale> getDetail(String id) async {
    final res = await apiService.getDetail(id);
    return Sale.fromJson(res);
  }

  Sale? getById(String id) {
    return null;
  }

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
  /// Penjualan satu shift — dipakai rekap tender di Riwayat Shift dan struk
  /// laporan tutup kasir.
  ///
  /// Sebelum ini daftarnya di-hardcode kosong, sehingga rekapnya menampilkan
  /// Rp0 untuk SEMUA metode bayar tepat di sebelah Ekspektasi Kas yang benar —
  /// dua angka bertentangan di dokumen serah-terima uang, dan yang
  /// menandatanganinya tak punya cara tahu mana yang bisa dipercaya.
  Future<List<Sale>> getSalesByShift(String shiftId) async {
    final res = await apiService.getByShift(shiftId);
    return res.map((e) => Sale.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Sale>> getActiveSalesByTable(String tableId) async {
    // Disimpan per meja: saat offline tab meja tetap bisa dilihat & dilunasi.
    final raw = await readThroughCache<Map<String, dynamic>>(
      cache: _tabMejaCache,
      outletId: tableId,
      fetch: () async => [
        for (final e in await apiService.getActiveByTable(tableId))
          Map<String, dynamic>.from(e as Map),
      ],
    );
    return raw.map(Sale.fromJson).toList();
  }

  /// Transaksi dari riwayat yang tersimpan di perangkat — untuk membuka
  /// detail tagihan saat offline.
  Future<Sale?> cariTersimpan(String outletId, String id) async {
    try {
      for (final m in await _salesRawCache.getAll(outletId)) {
        if (m['id']?.toString() == id) return Sale.fromJson(m);
      }
    } catch (_) {}
    return null;
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
  /// Kirim struk via WhatsApp. Lihat [TransactionApiService.kirimStrukWa].
  Future<String> kirimStrukWa(String saleId, {String? phone}) =>
      apiService.kirimStrukWa(saleId, phone: phone);

  Future<Sale> voidSale(
    String saleId, {
    String? reason,
    String? overridePin,
  }) async {
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
  Future<Sale> markAsPaid(
    String saleId, {
    required String paymentMethod,
    double cashAmount = 0,
    double changeAmount = 0,
    String? paymentProofUrl,
  }) async {
    final res = await apiService.markAsPaid(
      saleId,
      paymentMethod: paymentMethod,
      cashAmount: cashAmount,
      changeAmount: changeAmount,
      paymentProofUrl: paymentProofUrl,
    );
    return Sale.fromJson(res);
  }

  /// Open bill: tutup meja sekali bayar — lunasi semua ronde tab meja dalam SATU
  /// transaksi backend (atomik) & bebaskan meja. Backend melunasi TEPAT ronde
  /// yang tampil di tab (kasir + QR terkonfirmasi), bukan pesanan QR yang masih
  /// menunggu konfirmasi. Return jumlah ronde yang dilunasi.
  Future<int> settleTable(
    String outletId,
    String tableId, {
    required String paymentMethod,
    double cashAmount = 0,
    double changeAmount = 0,
    String? paymentProofUrl,
  }) async {
    final res = await apiService.settleTable(
      outletId,
      tableId,
      paymentMethod: paymentMethod,
      cashAmount: cashAmount,
      changeAmount: changeAmount,
      paymentProofUrl: paymentProofUrl,
    );
    final n = res['settled_count'];
    return n is int ? n : int.tryParse('${n ?? 0}') ?? 0;
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
    try {
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
    } catch (e) {
      // Offline: tampilkan riwayat yang terakhir tersimpan di perangkat,
      // disaring di sini (halaman pertama memuat semuanya).
      if (!isOfflineError(e)) rethrow;
      if (page > 1) return const [];
      final tersimpan = (await _salesRawCache.getAll(
        outletId,
      )).map(Sale.fromJson).toList();
      return saringRiwayatTersimpan(
        tersimpan,
        cari: search,
        status: status,
        dari: DateTime.tryParse(dateFrom ?? ''),
        sampai: DateTime.tryParse(dateTo ?? ''),
      );
    }
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
        .where(pesananMejaPerluDitangani)
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

final transactionDetailProvider = FutureProvider.family<Sale, String>((
  ref,
  id,
) async {
  // Transaksi offline yang belum terkirim: belum ada di server, ambil dari
  // antrian di perangkat.
  final dilunasi = await ref.watch(idDilunasiLokalProvider.future);
  Sale lapis(Sale s) =>
      dilunasi.contains(s.id) && !s.isPaid ? tandaiLunasLokal(s) : s;
  if (SaleOutbox.idOffline(id)) {
    final sale = await cariTransaksiOffline(ref.read(saleOutboxProvider), id);
    if (sale != null) return lapis(sale);
    throw 'Transaksi ini sudah terkirim ke server. Muat ulang Riwayat untuk '
        'melihat versi terbarunya.';
  }
  final repo = ref.watch(transactionRepositoryProvider);
  try {
    return lapis(await repo.getDetail(id));
  } catch (e) {
    // Offline: tagihan dari riwayat yang tersimpan, supaya tetap bisa
    // dilihat dan dilunasi.
    if (!isOfflineError(e)) rethrow;
    final outletId = ref.read(activeOutletIdProvider) ?? '';
    final tersimpan = await repo.cariTersimpan(outletId, id);
    if (tersimpan == null) rethrow;
    return lapis(tersimpan);
  }
});

/// Riwayat pembelian satu pelanggan, di-fetch dari backend dan auto-refetch
/// saat di-invalidate (mis. setelah checkout).
final customerSalesProvider = FutureProvider.family<List<Sale>, String>((
  ref,
  customerId,
) async {
  return ref.watch(transactionRepositoryProvider).getCustomerSales(customerId);
});

/// Daftar transaksi unpaid yang sedang berjalan di satu meja. Dipakai
/// dialog detail meja occupied untuk menampilkan rincian pesanan yang
/// sedang disajikan ke tamu (item, durasi sejak order, total).
///
/// Auto-refetch saat di-invalidate, mis. setelah checkout meja yang sama
/// atau setelah staff melunasi salah satu transaksinya.
///
/// Saat offline: tab yang tersimpan + penjualan Bayar Nanti meja ini yang
/// dibuat offline (antrian). Tagihan yang sudah dilunasi di perangkat tampil
/// lunas — server belum tahu, tapi kasir tak boleh menagihnya lagi.
final activeTableTransactionsProvider =
    FutureProvider.family<List<Sale>, String>((ref, tableId) async {
      if (tableId.isEmpty) return const [];
      ref.watch(pendingSyncCountProvider);
      final dilunasi = await ref.watch(idDilunasiLokalProvider.future);
      List<Sale> server;
      try {
        server = await ref
            .watch(transactionRepositoryProvider)
            .getActiveSalesByTable(tableId);
      } catch (e) {
        if (!isOfflineError(e)) rethrow;
        server = const [];
      }
      final antrian = [
        for (final ps in await ref.read(saleOutboxProvider).pending())
          if (ps.payload['table_id']?.toString() == tableId &&
              ps.payload['is_paid'] == false)
            saleDariAntrian(ps),
      ];
      return [
        for (final s in [...server, ...antrian])
          dilunasi.contains(s.id) && !s.isPaid ? tandaiLunasLokal(s) : s,
      ];
    });

/// True bila pesanan QR ini masih PEKERJAAN kasir — layak muncul di tab
/// "Pesanan dari Scan Meja".
///
/// Fungsi MURNI supaya tiap keadaannya bisa diuji tanpa jaringan.
///
/// Pembayaran QR self-order selalu manual (tanpa payment gateway), jadi setiap
/// pesanan yang masih HIDUP adalah pekerjaan kasir: sudah lunas, sudah
/// dikonfirmasi/masuk dapur walau belum bayar (open-bill), atau belum bayar
/// sama sekali ("bayar di kasir" — kasir menagih lalu Tandai Lunas).
///
/// Tiga keadaan MATI dikecualikan:
///
///   selesai     pesanan yang sudah rampung; menampilkannya lagi membuat
///               antrean tak pernah kosong.
///   diretur     uangnya sudah kembali ke pelanggan.
///   DIBATALKAN  pelanggan membatalkan dari halaman menu QR. Inilah yang
///               bocor: kasir menekan "Tandai Lunas" dan barulah backend
///               menolak ("transaksi sudah cancelled"). Penjaga terakhirnya
///               bekerja — yang salah adalah menampilkan pesanan mati sebagai
///               pekerjaan, sementara pesanan yang benar-benar perlu
///               ditangani tenggelam di antaranya.
bool pesananMejaPerluDitangani(Sale s) {
  return s.fulfillmentStatus != 'completed' && !s.isRefunded && !s.isCancelled;
}

/// Transaksi offline yang tak bisa diselesaikan di perangkat (mis. diskon di
/// atas batas kasir tanpa PIN yang bisa diperiksa). Pesannya untuk kasir.
class TransaksiOfflineDitolak implements Exception {
  TransaksiOfflineDitolak(this.pesan);
  final String pesan;

  @override
  String toString() => pesan;
}

/// Saring riwayat yang tersimpan di perangkat — dipakai saat offline, ketika
/// penyaringan oleh server tak tersedia. Aturannya mengikuti filter halaman
/// Riwayat: cari (invoice / pelanggan), status, dan rentang tanggal inklusif.
List<Sale> saringRiwayatTersimpan(
  List<Sale> semua, {
  String? cari,
  String? status,
  DateTime? dari,
  DateTime? sampai,
}) {
  final q = (cari ?? '').trim().toLowerCase();
  final akhir = sampai == null
      ? null
      : DateTime(
          sampai.year,
          sampai.month,
          sampai.day,
        ).add(const Duration(days: 1));
  final hasil = semua.where((s) {
    if (q.isNotEmpty &&
        !s.invoiceId.toLowerCase().contains(q) &&
        !s.customerName.toLowerCase().contains(q)) {
      return false;
    }
    switch (status ?? '') {
      case 'paid':
        if (!s.isPaid || s.isRefunded) return false;
      case 'unpaid':
        if (!s.isUnpaid) return false;
      case 'refunded':
        if (!s.isRefunded && !s.isPartiallyRefunded) return false;
    }
    final t = s.createdAt.toLocal();
    if (dari != null && t.isBefore(DateTime(dari.year, dari.month, dari.day))) {
      return false;
    }
    if (akhir != null && !t.isBefore(akhir)) return false;
    return true;
  }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return hasil;
}
