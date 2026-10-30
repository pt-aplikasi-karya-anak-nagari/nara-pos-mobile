import 'dart:async';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image/image.dart' as img;
import '../../../core/permission_service.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../../core/format.dart';
import '../../kasir/domain/cart_item.dart';
import '../../outlet/domain/outlet.dart';
import '../../products/domain/product.dart';
import '../../transactions/domain/sale.dart';
import '../../shifts/domain/shift.dart';
import '../../../core/outlet_scope.dart';
import 'logo_struk.dart';
import 'printer_lan.dart';
import 'printer_settings.dart';
import 'receipt_settings_repository.dart';
import 'role_printer_config_repository.dart';
import '../domain/receipt_settings.dart';

/// Metadata pesanan yang tercetak di kepala tiket dapur. Sengaja lepas dari
/// [Sale]/[CartItem] supaya [PrinterService.buildKitchenTicket] murni & bisa
/// diuji tanpa perangkat.
/// Judul di kepala tiket dapur.
const kKitchenTicketTitle = 'PESANAN';

class KitchenOrderMeta {
  final String orderNo;
  final String? tableLabel;
  final String orderType;
  final DateTime time;

  const KitchenOrderMeta({
    required this.orderNo,
    this.tableLabel,
    required this.orderType,
    required this.time,
  });
}

/// E11: satu baris pada tiket dapur — tanpa harga sama sekali. Kitchen cuma
/// perlu tahu apa yang harus dibuat.
class KitchenTicketItem {
  final int qty;
  final String name;
  final String variant;
  final List<String> modifiers;
  final String note;

  const KitchenTicketItem({
    required this.qty,
    required this.name,
    this.variant = '',
    this.modifiers = const [],
    this.note = '',
  });
}

class PrinterService {
  PrinterService(this._ref);
  final Ref _ref;

  Future<bool> get isPermissionGranted =>
      _ref.read(systemPermissionServiceProvider).isNearbyDevicesGranted;

  Future<bool> get isBluetoothEnabled => PrintBluetoothThermal.bluetoothEnabled;

  /// Printer LAN yang tersimpan, atau null bila printernya Bluetooth.
  AlamatPrinterLan? get _lan =>
      AlamatPrinterLan.dariKunci(_ref.read(printerSettingsProvider).deviceMac);

  /// Printer tersimpan adalah printer jaringan (LAN/Wi-Fi)?
  bool get pakaiLan => _lan != null;

  /// Bluetooth: status sambungan. LAN: printer bisa dihubungi.
  Future<bool> get isConnected async {
    final lan = _lan;
    if (lan != null) return cekPrinterLan(lan);
    return PrintBluetoothThermal.connectionStatus;
  }

  /// Kirim byte ESC/POS ke printer tersimpan — LAN lewat TCP, selain itu
  /// Bluetooth.
  Future<bool> _kirim(List<int> bytes) async {
    final lan = _lan;
    if (lan != null) return kirimKePrinterLan(lan, bytes);
    return PrintBluetoothThermal.writeBytes(bytes);
  }

  Future<List<BluetoothInfo>> pairedDevices() =>
      PrintBluetoothThermal.pairedBluetooths;

  Future<bool> connect(String mac) async {
    final lan = AlamatPrinterLan.dariKunci(mac);
    if (lan != null) return cekPrinterLan(lan);
    final connected = await PrintBluetoothThermal.connectionStatus;
    if (connected) {
      await PrintBluetoothThermal.disconnect;
    }
    return PrintBluetoothThermal.connect(macPrinterAddress: mac);
  }

  Future<bool> disconnect() async {
    if (pakaiLan) return true; // LAN: koneksi dibuka-tutup per cetakan
    return PrintBluetoothThermal.disconnect;
  }

  Future<bool> _ensureConnected() async {
    final s0 = _ref.read(printerSettingsProvider);
    if (!s0.hasDevice) return false;
    if (pakaiLan) return true; // dibuka saat mengirim
    if (await PrintBluetoothThermal.connectionStatus) return true;
    final s = _ref.read(printerSettingsProvider);
    if (!s.hasDevice) return false;
    return PrintBluetoothThermal.connect(macPrinterAddress: s.deviceMac);
  }

  _ReceiptHeader _resolveHeader(PrinterSettings s) {
    final outlet = _ref.read(activeOutletProvider);
    return _ReceiptHeader(
      name: outlet?.name.isNotEmpty == true ? outlet!.name : 'NARA',
      address: outlet?.address ?? '',
      phone: outlet?.phone ?? '',
    );
  }

  // Logo terakhir yang sudah disiapkan untuk printer, supaya tak didekode
  // ulang setiap cetak struk.
  String? _kunciLogo;
  img.Image? _logoSiap;

  /// Logo kepala struk dari Pengaturan Struk outlet. Null bila outlet tak
  /// punya logo atau logonya dimatikan — struk lalu tercetak tanpa logo.
  /// Tak pernah melempar: logo yang gagal dimuat tak boleh menggagalkan cetak.
  Future<img.Image?> _logoStruk(
    OutletReceiptSettings? rs,
    PaperSize kertas,
  ) async {
    try {
      if (rs == null || !rs.headerShowLogo) return null;
      final url = rs.headerLogoUrl?.trim() ?? '';
      final outletId = rs.outletId.isNotEmpty
          ? rs.outletId
          : (_ref.read(activeOutletIdProvider) ?? 'outlet');
      final bytes = await _ref
          .read(logoStrukStoreProvider)
          .ambil(outletId, url);
      if (bytes == null) return null;
      final lebar = lebarLogoUntuk(kertas);
      final kunci = '$outletId|$url|${bytes.length}|$lebar';
      if (kunci != _kunciLogo) {
        _logoSiap = siapkanLogoStruk(bytes, lebarMaks: lebar);
        _kunciLogo = kunci;
      }
      return _logoSiap;
    } catch (_) {
      return null;
    }
  }

  Future<OutletReceiptSettings?> _pengaturanStruk() async {
    try {
      return await _ref.read(receiptSettingsFutureProvider.future);
    } catch (_) {
      return null;
    }
  }

  Future<bool> testPrint() async {
    if (!await _ensureConnected()) return false;
    final s = _ref.read(printerSettingsProvider);
    final header = _resolveHeader(s);
    final logo = await _logoStruk(await _pengaturanStruk(), s.paperSize);
    final profile = await CapabilityProfile.load();
    final gen = Generator(s.paperSize, profile);
    final bytes = <int>[
      ...gen.reset(),
      if (logo != null) ...gen.image(logo, align: PosAlign.center),
      ...gen.text(
        'TEST PRINT',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
      ...gen.text(
        _safe(header.name),
        styles: const PosStyles(align: PosAlign.center),
      ),
      if (header.address.isNotEmpty)
        ...gen.text(
          _safe(header.address),
          styles: const PosStyles(align: PosAlign.center),
        ),
      ...gen.hr(),
      ...gen.text('Printer terhubung.'),
      ...gen.text('Ukuran kertas: ${_paperLabel(s.paperSize)}'),
      ...gen.text('Waktu: ${formatDateTime(DateTime.now())}'),
      ...gen.feed(2),
      ...gen.cut(),
    ];
    return _kirim(bytes);
  }

  /// Nilai printer efektif (override user → default role → struk outlet →
  /// fallback hardcoded). Tak pernah melempar — offline / error → default role
  /// hardcoded supaya cetak tetap jalan.
  EffectivePrinterConfig _effectiveConfig(OutletReceiptSettings? rs) {
    // Sinkron: pakai `rs` yang sudah diambil pemanggil + default role yang sudah
    // termuat (valueOrNull), tanpa menunggu jaringan → aman offline.
    return EffectivePrinterConfig.resolve(
      user: _ref.read(printerSettingsProvider),
      role:
          _ref.read(rolePrinterConfigProvider).asData?.value ??
          RolePrinterConfig.fallback,
      receipt: rs,
    );
  }

  Future<bool> printReceipt(Sale sale, {bool reprint = false}) async {
    if (!await _ensureConnected()) return false;
    final s = _ref.read(printerSettingsProvider);
    // Branding/toggle struk dari backend (single source of truth per outlet).
    // Null-safe: kalau gagal fetch, struk tetap tercetak dengan default lama.
    final rs = await _pengaturanStruk();
    // Ukuran kertas & salinan pakai nilai EFEKTIF (override user → default role
    // → struk outlet). Salinan tak lagi hanya dari rs supaya default role &
    // override user ikut diperhitungkan.
    final eff = _effectiveConfig(rs);
    final logo = await _logoStruk(rs, eff.paperSize);
    final profile = await CapabilityProfile.load();
    final gen = Generator(eff.paperSize, profile);
    final bytes = _buildReceipt(
      gen,
      s,
      sale,
      reprint: reprint,
      logo: logo,
      rs: rs,
    );
    final copies = eff.copies;
    bool ok = true;
    for (var i = 0; i < copies; i++) {
      final sent = await _kirim(bytes);
      ok = ok && sent;
    }
    return ok;
  }

  /// Cetak label rak: per salinan → nama produk (bold, tengah), harga (tengah),
  /// lalu barcode Code128 dari [code]. [code] = `product.barcode` bila ada,
  /// jika tidak `product.sku`; bila keduanya kosong → hanya nama + harga tanpa
  /// barcode. Encoding Code128 divalidasi paket (bisa melempar) → dibungkus
  /// try/catch, gagal → kodenya dicetak sebagai teks biasa. [qty] salinan
  /// dicetak berurutan dengan pemisah kecil, diakhiri feed + potong. Ukuran
  /// kertas pakai nilai EFEKTIF seperti [printReceipt].
  Future<bool> printLabel(Product product, {int qty = 1}) async {
    if (!await _ensureConnected()) return false;
    // Ukuran kertas efektif (override user → default role → struk outlet).
    // Null-safe: gagal fetch → default, label tetap tercetak.
    OutletReceiptSettings? rs;
    try {
      rs = await _ref.read(receiptSettingsFutureProvider.future);
    } catch (_) {
      rs = null;
    }
    final eff = _effectiveConfig(rs);
    final profile = await CapabilityProfile.load();
    final gen = Generator(eff.paperSize, profile);

    // Kode barcode: barcode produk diutamakan, fallback ke SKU. Keduanya
    // kosong → label tanpa barcode.
    final barcode = product.barcode?.trim() ?? '';
    final sku = product.sku?.trim() ?? '';
    final code = barcode.isNotEmpty ? barcode : sku;

    final copies = qty < 1 ? 1 : qty;
    final bytes = <int>[...gen.reset()];
    for (var i = 0; i < copies; i++) {
      bytes.addAll(
        gen.text(
          _safe(product.name),
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
      );
      bytes.addAll(
        gen.text(
          formatRupiah(product.price),
          styles: const PosStyles(align: PosAlign.center),
        ),
      );
      if (code.isNotEmpty) {
        try {
          // Prefiks '{B' memilih Code128 set B (ASCII penuh) sesuai ESC/POS —
          // selektor set tidak ikut tercetak pada teks di bawah barcode.
          bytes.addAll(
            gen.barcode(
              Barcode.code128('{B$code'.split('')),
              textPos: BarcodeText.below,
            ),
          );
        } catch (_) {
          // Data tak valid untuk Code128 → cetak kodenya sebagai teks biasa.
          bytes.addAll(
            gen.text(
              _safe(code),
              styles: const PosStyles(align: PosAlign.center),
            ),
          );
        }
      }
      // Pemisah antar salinan supaya mudah dipotong/dirobek.
      if (i < copies - 1) {
        bytes.addAll(gen.feed(1));
        bytes.addAll(gen.hr());
      }
    }
    bytes.addAll(gen.feed(2));
    bytes.addAll(gen.cut());
    return _kirim(bytes);
  }

  /// Cetak SATU tiket dapur berisi seluruh item pesanan ke printer Bluetooth
  /// default, saat checkout kasir.
  ///
  /// [cartItems] di-snapshot oleh pemanggil SEBELUM keranjang di-clear.
  Future<bool> printKitchenTickets(Sale sale, List<CartItem> cartItems) async {
    if (cartItems.isEmpty) return false;
    final s = _ref.read(printerSettingsProvider);
    if (!s.hasDevice) return false;

    final meta = KitchenOrderMeta(
      orderNo: sale.invoiceId.isNotEmpty ? sale.invoiceId : sale.id.toString(),
      tableLabel: sale.isDineIn ? sale.tablePositionDisplay : null,
      orderType: sale.orderType,
      time: sale.createdAt,
    );

    // Ukuran kertas efektif supaya lebar tiket dapur konsisten dengan struk.
    final eff = _effectiveConfig(null);
    final profile = await CapabilityProfile.load();
    final gen = Generator(eff.paperSize, profile);

    final bytes = buildKitchenTicket(
      gen,
      title: kKitchenTicketTitle,
      orderMeta: meta,
      items: cartItems.map(_cartItemToTicketItem).toList(),
    );
    if (!await connect(s.deviceMac)) return false;
    return _kirim(bytes);
  }

  KitchenTicketItem _cartItemToTicketItem(CartItem c) => KitchenTicketItem(
    qty: c.qty,
    name: c.product.name,
    variant: c.variantName,
    modifiers: c.modifiers.map((m) => m.name).toList(),
    note: c.note,
  );

  /// Bangun byte ESC/POS satu tiket dapur. MURNI & injectable — tak
  /// menyentuh I/O printer sehingga bisa di-golden-test dengan [Generator] +
  /// [CapabilityProfile] yang dimuat di test. LEBIH RAMPING dari struk:
  /// header [title] bold size-2; meta pesanan (no/meja/tipe/waktu); lalu
  /// per baris `qty x nama (varian)` + baris `+ modifier` (indent) + `* catatan`.
  /// TANPA harga, TANPA total, TANPA QR, TANPA logo. Diakhiri [Generator.cut].
  List<int> buildKitchenTicket(
    Generator gen, {
    required String title,
    required KitchenOrderMeta orderMeta,
    required List<KitchenTicketItem> items,
  }) {
    final bytes = <int>[];
    bytes.addAll(gen.reset());

    // Header: judul tiket, bold size-2, tengah.
    bytes.addAll(
      gen.text(
        _safe(title),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    );
    bytes.addAll(gen.hr());

    // Meta pesanan (mirror idiom PosColumn di _buildReceipt).
    bytes.addAll(
      gen.row([
        PosColumn(text: 'No', width: 4),
        PosColumn(
          text: '#${orderMeta.orderNo}',
          width: 8,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]),
    );
    if (orderMeta.tableLabel != null && orderMeta.tableLabel!.isNotEmpty) {
      bytes.addAll(
        gen.row([
          PosColumn(text: 'Meja', width: 4),
          PosColumn(
            text: _safe(orderMeta.tableLabel!),
            width: 8,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }
    bytes.addAll(
      gen.row([
        PosColumn(text: 'Tipe', width: 4),
        PosColumn(
          text: _safe(orderMeta.orderType),
          width: 8,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]),
    );
    bytes.addAll(
      gen.row([
        PosColumn(text: 'Waktu', width: 4),
        PosColumn(
          text: formatDateTime(orderMeta.time),
          width: 8,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]),
    );
    bytes.addAll(gen.hr());

    // Baris item: `qty x nama (varian)` bold, lalu modifier & catatan.
    for (final it in items) {
      final line = it.variant.isEmpty
          ? '${it.qty} x ${it.name}'
          : '${it.qty} x ${it.name} (${it.variant})';
      bytes.addAll(gen.text(_safe(line), styles: const PosStyles(bold: true)));
      for (final m in it.modifiers) {
        if (m.trim().isEmpty) continue;
        bytes.addAll(gen.text(_safe('  + $m'), styles: const PosStyles()));
      }
      if (it.note.isNotEmpty) {
        bytes.addAll(
          gen.text(_safe('  * ${it.note}'), styles: const PosStyles()),
        );
      }
    }

    bytes.addAll(gen.feed(2));
    bytes.addAll(gen.cut());
    return bytes;
  }

  /// Buka laci kas (cash drawer) lewat pulse ESC/POS (perintah ESC p).
  /// Dipanggil otomatis saat pembayaran tunai supaya laci terbuka tanpa
  /// kunci manual. Aman dipanggil walau printer/laci tidak terpasang —
  /// langsung return false tanpa melempar error sehingga tidak mengganggu
  /// alur checkout.
  Future<bool> openCashDrawer() async {
    final s = _ref.read(printerSettingsProvider);
    if (!s.hasDevice) return false;
    if (!await _ensureConnected()) return false;
    final profile = await CapabilityProfile.load();
    final gen = Generator(s.paperSize, profile);
    return _kirim(<int>[...gen.drawer()]);
  }

  Future<bool> printShiftReport(Shift shift, List<Sale> sales) async {
    if (!await _ensureConnected()) return false;
    final s = _ref.read(printerSettingsProvider);
    final profile = await CapabilityProfile.load();
    final gen = Generator(s.paperSize, profile);
    final header = _resolveHeader(s);

    double totalQris = 0;
    double totalCard = 0;
    double totalTransfer = 0;
    double totalCash = 0;

    // netTotal, bukan total: struk yang diretur sebagian hanya menyumbang porsi
    // yang benar-benar diterima. Kalau memakai nilai penuh, rekap tender yang
    // dicetak tidak akan cocok dengan uang di laci maupun dengan Z-report server.
    //
    // Dikelompokkan lewat TIPE metode bayar, bukan nama tampilannya. Nama di
    // basis data adalah "Kartu Debit/Kredit" dan "Transfer Bank" — cocok-persis
    // dengan 'Kartu'/'Transfer' tak pernah benar, dan kertas ini akan mencetak
    // Rp0 untuk keduanya tanpa ada yang tahu. Pemilik juga bebas mengganti nama
    // metode bayarnya kapan saja.
    for (final sale in sales) {
      if (!sale.countsAsSale) continue;
      totalQris += sale.porsiTender('qris');
      totalCard += sale.porsiTender('card');
      totalTransfer += sale.porsiTender('transfer');
      totalCash += sale.porsiTender('cash');
    }

    final bytes = <int>[
      ...gen.reset(),
      ...gen.text(
        _safe(header.name),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
      ...gen.text(
        'LAPORAN SHIFT',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
      ...gen.hr(),
      ...gen.text('ID Shift: #${shift.remoteId}'),
      ...gen.text('Kasir: ${_safe(shift.cashierName)}'),
      ...gen.text('Outlet: ${_safe(shift.outletRemoteId ?? 'Unknown')}'),
      ...gen.text('Mulai: ${formatDateTime(shift.startTime)}'),
      if (shift.endTime != null)
        ...gen.text('Selesai: ${formatDateTime(shift.endTime!)}'),
      ...gen.hr(),
      ...gen.text('RINGKASAN KAS', styles: const PosStyles(bold: true)),
      ...gen.row([
        PosColumn(text: 'Modal Awal', width: 6),
        PosColumn(
          text: _fmtShort(shift.startingCash),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]),
      ...gen.row([
        PosColumn(text: 'Penjualan Tunai', width: 6),
        PosColumn(
          text: _fmtShort(totalCash),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]),
      ...gen.hr(),
      ...gen.row([
        PosColumn(
          text: 'Ekspektasi Kas',
          width: 6,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: _fmtShort(shift.expectedCash ?? 0),
          width: 6,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]),
      ...gen.row([
        PosColumn(text: 'Uang Fisik', width: 6),
        PosColumn(
          text: _fmtShort(shift.actualCash ?? 0),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]),
      ...gen.row([
        PosColumn(
          text: 'Selisih',
          width: 6,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: _fmtShort(shift.difference ?? 0),
          width: 6,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]),
      ...gen.hr(),
      ...gen.text('METODE PEMBAYARAN', styles: const PosStyles(bold: true)),
      ...gen.row([
        PosColumn(text: 'Tunai', width: 6),
        PosColumn(
          text: _fmtShort(totalCash),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]),
      ...gen.row([
        PosColumn(text: 'QRIS', width: 6),
        PosColumn(
          text: _fmtShort(totalQris),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]),
      ...gen.row([
        PosColumn(text: 'Kartu', width: 6),
        PosColumn(
          text: _fmtShort(totalCard),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]),
      ...gen.row([
        PosColumn(text: 'Transfer', width: 6),
        PosColumn(
          text: _fmtShort(totalTransfer),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]),
      ...gen.hr(),
      ...gen.row([
        PosColumn(
          text: 'TOTAL PENJUALAN',
          width: 6,
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: _fmtShort(totalCash + totalQris + totalCard + totalTransfer),
          width: 6,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]),
      if (shift.notes != null && shift.notes!.isNotEmpty) ...[
        ...gen.feed(1),
        ...gen.text('Catatan:', styles: const PosStyles(bold: true)),
        ...gen.text(_safe(shift.notes!)),
      ],
      ...gen.feed(2),
      ...gen.cut(),
    ];

    return _kirim(bytes);
  }

  List<int> _buildReceipt(
    Generator gen,
    PrinterSettings s,
    Sale sale, {
    bool reprint = false,
    img.Image? logo,
    OutletReceiptSettings? rs,
  }) {
    final bytes = <int>[];
    final header = _resolveHeader(s);

    // Resolusi field header: backend (rs) menang bila non-empty, jika
    // tidak fallback ke outlet/PrinterSettings lama.
    final bizName = (rs?.headerBusinessName.isNotEmpty ?? false)
        ? rs!.headerBusinessName
        : header.name;
    final bizAddress = (rs?.headerAddress.isNotEmpty ?? false)
        ? rs!.headerAddress
        : header.address;
    final bizPhone = (rs?.headerPhone.isNotEmpty ?? false)
        ? rs!.headerPhone
        : header.phone;

    // Display toggles (default true = perilaku lama).
    final showCashier = rs?.showCashierName ?? true;
    final showCustomer = rs?.showCustomerName ?? true;
    final showOrderType = rs?.showOrderType ?? true;
    final showTable = rs?.showTableNumber ?? true;
    final showPayment = rs?.showPaymentDetail ?? true;
    final showNotes = rs?.showItemNotes ?? true;
    final showTxId = rs?.showTransactionId ?? true;
    final showTax = rs?.showTaxBreakdown ?? true;

    bytes.addAll(gen.reset());

    if (logo != null && (rs?.headerShowLogo ?? true)) {
      bytes.addAll(gen.image(logo, align: PosAlign.center));
    }

    bytes.addAll(
      gen.text(
        _safe(bizName),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    );
    if (bizAddress.isNotEmpty) {
      bytes.addAll(
        gen.text(
          _safe(bizAddress),
          styles: const PosStyles(align: PosAlign.center),
        ),
      );
    }
    if (bizPhone.isNotEmpty) {
      bytes.addAll(
        gen.text(
          _safe('Telp: $bizPhone'),
          styles: const PosStyles(align: PosAlign.center),
        ),
      );
    }
    // NPWP / Tax ID — penting untuk pelanggan bisnis yang butuh faktur.
    if ((rs?.headerTaxId ?? '').isNotEmpty) {
      bytes.addAll(
        gen.text(
          _safe('NPWP: ${rs!.headerTaxId}'),
          styles: const PosStyles(align: PosAlign.center),
        ),
      );
    }
    // Baris ekstra header (mis. Instagram, slogan) dari konfigurasi owner.
    for (final line in (rs?.headerExtraLines ?? const <String>[])) {
      if (line.trim().isEmpty) continue;
      bytes.addAll(
        gen.text(_safe(line), styles: const PosStyles(align: PosAlign.center)),
      );
    }
    bytes.addAll(gen.hr());

    if (showTxId) {
      bytes.addAll(
        gen.row([
          PosColumn(text: 'No', width: 4),
          PosColumn(
            text: '#${sale.invoiceId.isNotEmpty ? sale.invoiceId : sale.id}',
            width: 8,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }
    bytes.addAll(
      gen.row([
        PosColumn(text: 'Waktu', width: 4),
        PosColumn(
          text: formatDateTime(sale.createdAt),
          width: 8,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]),
    );
    if (showOrderType) {
      bytes.addAll(
        gen.row([
          PosColumn(text: 'Tipe', width: 4),
          PosColumn(
            text: _safe(sale.orderType),
            width: 8,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }
    // Baris meja untuk dine-in — informatif bila banyak meja & beberapa
    // tamu sekaligus. Lewati kalau tipe non-dine-in atau data meja kosong
    // (mis. takeaway, atau dine-in yang belum di-assign meja).
    // Pakai tablePositionDisplay (strip prefix "Meja") supaya tidak
    // duplikat dengan label kolom kiri "Meja".
    if (showTable && sale.isDineIn && sale.tablePositionDisplay != null) {
      bytes.addAll(
        gen.row([
          PosColumn(text: 'Meja', width: 4),
          PosColumn(
            text: _safe(sale.tablePositionDisplay!),
            width: 8,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }
    if (showCashier && sale.cashierName.isNotEmpty) {
      bytes.addAll(
        gen.row([
          PosColumn(text: 'Kasir', width: 4),
          PosColumn(
            text: _safe(sale.cashierName),
            width: 8,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }
    if (showCustomer && sale.customerName.isNotEmpty) {
      bytes.addAll(
        gen.row([
          PosColumn(text: 'Pelanggan', width: 4),
          PosColumn(
            text: _safe(sale.customerName),
            width: 8,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }
    if (showPayment) {
      bytes.addAll(
        gen.row([
          PosColumn(text: 'Bayar', width: 4),
          PosColumn(
            text: _safe(sale.paymentMethod),
            width: 8,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }
    bytes.addAll(gen.hr());

    for (final it in sale.items) {
      final line = it.variant.isEmpty
          ? it.productName
          : '${it.productName} (${it.variant})';
      bytes.addAll(gen.text(_safe(line), styles: const PosStyles(bold: true)));
      // C4: add-on/topping di bawah nama produk.
      if (it.modifiersLabel.isNotEmpty) {
        bytes.addAll(
          gen.text(
            _safe('  + ${it.modifiersLabel}'),
            styles: const PosStyles(),
          ),
        );
      }
      if (it.discountAmount > 0) {
        bytes.addAll(
          gen.row([
            PosColumn(
              text: '${it.qty} x ${_fmtShort(it.originalPrice)}',
              width: 7,
            ),
            PosColumn(
              text: _fmtShort(it.originalPrice * it.qty),
              width: 5,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]),
        );
        bytes.addAll(
          gen.row([
            PosColumn(text: '  Diskon ${it.discountLabel}', width: 7),
            PosColumn(
              text: '-${_fmtShort(it.discountAmount)}',
              width: 5,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]),
        );
      } else {
        bytes.addAll(
          gen.row([
            PosColumn(text: '${it.qty} x ${_fmtShort(it.price)}', width: 7),
            PosColumn(
              text: _fmtShort(it.subtotal),
              width: 5,
              styles: const PosStyles(align: PosAlign.right),
            ),
          ]),
        );
      }
      if (showNotes && it.note.isNotEmpty) {
        bytes.addAll(
          gen.text(_safe('  * ${it.note}'), styles: const PosStyles()),
        );
      }
    }
    bytes.addAll(gen.hr());

    bytes.addAll(
      gen.row([
        PosColumn(text: 'Subtotal', width: 6),
        PosColumn(
          text: formatRupiah(sale.originalSubtotal),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]),
    );
    if (sale.discountTotal > 0) {
      bytes.addAll(
        gen.row([
          PosColumn(text: 'Total Diskon', width: 6),
          PosColumn(
            text: '-${formatRupiah(sale.discountTotal)}',
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }
    if (sale.serviceCharge > 0) {
      bytes.addAll(
        gen.row([
          PosColumn(text: 'Layanan', width: 6),
          PosColumn(
            text: formatRupiah(sale.serviceCharge),
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }
    if (showTax && sale.tax > 0) {
      bytes.addAll(
        gen.row([
          PosColumn(text: 'Pajak', width: 6),
          PosColumn(
            text: formatRupiah(sale.tax),
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }
    bytes.addAll(
      gen.row([
        PosColumn(
          text: 'TOTAL',
          width: 6,
          styles: const PosStyles(bold: true, height: PosTextSize.size2),
        ),
        PosColumn(
          text: formatRupiah(sale.total),
          width: 6,
          styles: const PosStyles(
            align: PosAlign.right,
            bold: true,
            height: PosTextSize.size2,
          ),
        ),
      ]),
    );
    if (showPayment && sale.cashAmount > 0) {
      bytes.addAll(
        gen.row([
          PosColumn(text: 'Tunai', width: 6),
          PosColumn(
            text: formatRupiah(sale.cashAmount),
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
      bytes.addAll(
        gen.row([
          PosColumn(text: 'Kembalian', width: 6),
          PosColumn(
            text: formatRupiah(sale.changeAmount),
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }

    if ((rs?.showLoyaltyPoints ?? true) && sale.pointsEarned > 0) {
      bytes.addAll(
        gen.text(
          _safe('Poin diperoleh: +${sale.pointsEarned}'),
          styles: const PosStyles(align: PosAlign.center),
        ),
      );
    }

    bytes.addAll(gen.hr());

    if (sale.isRefunded) {
      bytes.addAll(
        gen.text(
          '*** REFUNDED ***',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
      );
    } else if (sale.isPartiallyRefunded) {
      // Tanpa penanda ini, struk cetak ulang atas transaksi yang sebagian
      // barangnya sudah dikembalikan terlihat identik dengan struk normal.
      bytes.addAll(
        gen.text(
          '*** RETUR SEBAGIAN ***',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
      );
    }
    if (reprint) {
      bytes.addAll(
        gen.text(
          '-- CETAK ULANG --',
          styles: const PosStyles(align: PosAlign.center),
        ),
      );
    }
    if (sale.pendingSync) {
      bytes.addAll(
        gen.text(
          '** OFFLINE - BELUM SINKRON **',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
      );
    }

    bytes.addAll(gen.feed(1));
    final noresi = sale.invoiceId.isNotEmpty
        ? sale.invoiceId
        : sale.id.toString();
    bytes.addAll(
      gen.qrcode('resi:$noresi', align: PosAlign.center, size: QRSize.size5),
    );
    bytes.addAll(gen.feed(1));

    // Footer: ucapan terima kasih (backend menang), teks promo, lalu QR
    // review opsional — semuanya dari konfigurasi owner di backend.
    final thanks = (rs?.footerThanksText.isNotEmpty ?? false)
        ? rs!.footerThanksText
        : s.storeFooter;
    if (thanks.isNotEmpty) {
      bytes.addAll(
        gen.text(
          _safe(thanks),
          styles: const PosStyles(align: PosAlign.center),
        ),
      );
    }
    if ((rs?.footerPromoText ?? '').isNotEmpty) {
      bytes.addAll(
        gen.text(
          _safe(rs!.footerPromoText),
          styles: const PosStyles(align: PosAlign.center),
        ),
      );
    }
    // Akun sosmed & WiFi tamu outlet (diatur Owner di dashboard).
    final sosmed = rs?.barisSosmed ?? const <String>[];
    if (sosmed.isNotEmpty) {
      bytes.addAll(gen.feed(1));
      bytes.addAll(
        gen.text(
          'Ikuti kami',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
      );
      for (final b in sosmed) {
        bytes.addAll(
          gen.text(_safe(b), styles: const PosStyles(align: PosAlign.center)),
        );
      }
    }
    final wifi = rs?.barisWifi ?? const <String>[];
    if (wifi.isNotEmpty) {
      bytes.addAll(gen.hr());
      for (final b in wifi) {
        bytes.addAll(
          gen.text(_safe(b), styles: const PosStyles(align: PosAlign.center)),
        );
      }
      bytes.addAll(gen.hr());
    }
    if ((rs?.footerShowQr ?? false) && (rs?.footerQrUrl ?? '').isNotEmpty) {
      bytes.addAll(gen.feed(1));
      bytes.addAll(
        gen.qrcode(rs!.footerQrUrl, align: PosAlign.center, size: QRSize.size4),
      );
      if (rs.footerQrCaption.isNotEmpty) {
        bytes.addAll(
          gen.text(
            _safe(rs.footerQrCaption),
            styles: const PosStyles(align: PosAlign.center),
          ),
        );
      }
    }

    bytes.addAll(
      gen.text(
        'Powered by NARA POS',
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    bytes.addAll(gen.cut());
    return bytes;
  }

  String _fmtShort(double v) => formatRupiah(v).replaceAll('Rp ', '');

  String _safe(String s) {
    final buf = StringBuffer();
    for (final r in s.runes) {
      if (r <= 0xFF) {
        buf.writeCharCode(r);
      } else {
        buf.write('?');
      }
    }
    return buf.toString();
  }
}

String _paperLabel(PaperSize size) {
  if (size == PaperSize.mm80) return '80mm';
  if (size == PaperSize.mm72) return '72mm';
  return '58mm';
}

String paperSizeLabel(PaperSize size) => _paperLabel(size);

class _ReceiptHeader {
  final String name;
  final String address;
  final String phone;
  const _ReceiptHeader({
    required this.name,
    required this.address,
    required this.phone,
  });
}

class ReceiptHeaderDefaults {
  final String name;
  final String address;
  final String phone;
  const ReceiptHeaderDefaults({
    required this.name,
    required this.address,
    required this.phone,
  });
}

ReceiptHeaderDefaults receiptHeaderDefaultsFrom(Outlet? outlet) {
  return ReceiptHeaderDefaults(
    name: outlet?.name ?? '',
    address: outlet?.address ?? '',
    phone: outlet?.phone ?? '',
  );
}

final receiptHeaderDefaultsProvider = Provider<ReceiptHeaderDefaults>((ref) {
  final outlet = ref.watch(activeOutletProvider);
  return receiptHeaderDefaultsFrom(outlet);
});

final printerServiceProvider = Provider<PrinterService>((ref) {
  return PrinterService(ref);
});
