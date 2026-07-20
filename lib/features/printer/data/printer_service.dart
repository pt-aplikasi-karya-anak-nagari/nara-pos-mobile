import 'dart:async';
import 'dart:ui' as ui;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
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
import '../domain/print_station.dart';
import 'print_station_repository.dart';
import 'printer_settings.dart';
import 'receipt_settings_repository.dart';
import 'role_printer_config_repository.dart';
import '../domain/receipt_settings.dart';

/// E11: metadata pesanan yang tercetak di kepala tiap tiket dapur/bar.
/// Sengaja lepas dari [Sale]/[CartItem] supaya [PrinterService.buildStationTicket]
/// murni & bisa diuji tanpa perangkat, dan bisa dipakai ulang untuk reprint
/// (yang merutekan lewat SaleItem.printStationId, bukan cart).
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

  Future<bool> get isConnected => PrintBluetoothThermal.connectionStatus;

  Future<List<BluetoothInfo>> pairedDevices() =>
      PrintBluetoothThermal.pairedBluetooths;

  Future<bool> connect(String mac) async {
    final connected = await PrintBluetoothThermal.connectionStatus;
    if (connected) {
      await PrintBluetoothThermal.disconnect;
    }
    return PrintBluetoothThermal.connect(macPrinterAddress: mac);
  }

  Future<bool> disconnect() => PrintBluetoothThermal.disconnect;

  Future<bool> _ensureConnected() async {
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

  Future<img.Image?> _renderLogo({int size = 160}) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final bg = Paint()..color = const Color(0xFFFFFFFF);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        bg,
      );
      const decoration = FlutterLogoDecoration(
        style: FlutterLogoStyle.markOnly,
      );
      final painter = decoration.createBoxPainter(() {});
      final inset = size * 0.12;
      painter.paint(
        canvas,
        Offset(inset, inset),
        ImageConfiguration(size: Size(size - inset * 2, size - inset * 2)),
      );
      final picture = recorder.endRecording();
      final uiImage = await picture.toImage(size, size);
      final bd = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return null;
      final decoded = img.decodePng(bd.buffer.asUint8List());
      if (decoded == null) return null;
      return img.grayscale(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<bool> testPrint() async {
    if (!await _ensureConnected()) return false;
    final s = _ref.read(printerSettingsProvider);
    final header = _resolveHeader(s);
    final logo = await _renderLogo();
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
    return PrintBluetoothThermal.writeBytes(bytes);
  }

  /// Nilai printer efektif (override user → default role → struk outlet →
  /// fallback hardcoded). Tak pernah melempar — offline / error → default role
  /// hardcoded supaya cetak tetap jalan.
  EffectivePrinterConfig _effectiveConfig(OutletReceiptSettings? rs) {
    // Sinkron: pakai `rs` yang sudah diambil pemanggil + default role yang sudah
    // termuat (valueOrNull), tanpa menunggu jaringan → aman offline.
    return EffectivePrinterConfig.resolve(
      user: _ref.read(printerSettingsProvider),
      role: _ref.read(rolePrinterConfigProvider).asData?.value ??
          RolePrinterConfig.fallback,
      receipt: rs,
    );
  }

  Future<bool> printReceipt(Sale sale, {bool reprint = false}) async {
    if (!await _ensureConnected()) return false;
    final s = _ref.read(printerSettingsProvider);
    // Branding/toggle struk dari backend (single source of truth per outlet).
    // Null-safe: kalau gagal fetch, struk tetap tercetak dengan default lama.
    OutletReceiptSettings? rs;
    try {
      rs = await _ref.read(receiptSettingsFutureProvider.future);
    } catch (_) {
      rs = null;
    }
    // Ukuran kertas & salinan pakai nilai EFEKTIF (override user → default role
    // → struk outlet). Salinan tak lagi hanya dari rs supaya default role &
    // override user ikut diperhitungkan.
    final eff = _effectiveConfig(rs);
    final logo = await _renderLogo();
    final profile = await CapabilityProfile.load();
    final gen = Generator(eff.paperSize, profile);
    final bytes = _buildReceipt(gen, s, sale, reprint: reprint, logo: logo, rs: rs);
    final copies = eff.copies;
    bool ok = true;
    for (var i = 0; i < copies; i++) {
      final sent = await PrintBluetoothThermal.writeBytes(bytes);
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
    return PrintBluetoothThermal.writeBytes(bytes);
  }

  /// E11: cetak tiket dapur/bar per stasiun saat checkout kasir.
  ///
  /// [cartItems] di-snapshot oleh pemanggil SEBELUM keranjang di-clear supaya
  /// kategori produk (dasar routing) tetap tersedia. Item dirutekan ke stasiun
  /// via [groupItemsByStation]; bila tak ada stasiun terkonfigurasi, semua item
  /// jatuh ke satu grup catch-all "Lainnya" → satu tiket berisi semuanya
  /// (default yang masuk akal).
  ///
  /// Satu tiket dicetak per grup. Tiap grup diarahkan ke printer stasiunnya
  /// (bila diikat di pengaturan) atau ke printer Bluetooth default sebagai
  /// fallback. Transport hari ini Bluetooth-ONLY (lihat [_resolveStationMac]).
  Future<bool> printKitchenTickets(Sale sale, List<CartItem> cartItems) async {
    if (cartItems.isEmpty) return false;
    final s = _ref.read(printerSettingsProvider);

    // Konfigurasi stasiun dari backend. Null-safe: gagal fetch → anggap tak ada
    // stasiun, tetap cetak satu tiket catch-all supaya dapur tidak buta.
    List<PrintStation> stations;
    try {
      stations = await _ref.read(printStationsFutureProvider.future);
    } catch (_) {
      stations = const [];
    }

    final groups = groupItemsByStation<CartItem>(
      items: cartItems,
      stations: stations,
      categoryOf: (c) => c.product.categoryId,
    );
    if (groups.isEmpty) return false;

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

    bool ok = true;
    String? connectedMac; // hindari reconnect berulang ke printer yang sama.
    for (final group in groups) {
      final items = group.items.map(_cartItemToTicketItem).toList();
      final bytes = buildStationTicket(
        gen,
        stationName: group.label,
        orderMeta: meta,
        items: items,
      );
      final mac = _resolveStationMac(s, group.station);
      if (mac.isEmpty) {
        // Tidak ada printer default maupun stasiun → tidak bisa cetak.
        ok = false;
        continue;
      }
      if (mac != connectedMac) {
        final connected = await connect(mac);
        if (!connected) {
          ok = false;
          continue;
        }
        connectedMac = mac;
      }
      final sent = await PrintBluetoothThermal.writeBytes(bytes);
      ok = ok && sent;
    }

    // Kembalikan koneksi ke printer default supaya operasi setelah ini (mis.
    // buka laci kas / cetak ulang struk) memakai printer utama, bukan printer
    // stasiun terakhir.
    if (s.hasDevice && connectedMac != null && connectedMac != s.deviceMac) {
      await connect(s.deviceMac);
    }
    return ok;
  }

  KitchenTicketItem _cartItemToTicketItem(CartItem c) => KitchenTicketItem(
        qty: c.qty,
        name: c.product.name,
        variant: c.variantName,
        modifiers: c.modifiers.map((m) => m.name).toList(),
        note: c.note,
      );

  /// Resolusi MAC printer untuk sebuah [station]:
  ///   1. Printer yang diikat ke stasiun di pengaturan (stationPrinters).
  ///   2. Fallback ke printer Bluetooth default aplikasi.
  String _resolveStationMac(PrinterSettings s, PrintStation? station) {
    if (station != null) {
      final bound = s.macForStation(station.id);
      if (bound.isNotEmpty) return bound;
      // TODO(hardware): LAN transport belum ada — fallback ke printer BT default.
      // Bila target stasiun berupa IP:PORT (printer jaringan), kita TIDAK punya
      // socket sender; jadi tiketnya tetap dicetak ke printer BT default.
      if (_looksLikeLanTarget(station.target)) {
        // sengaja jatuh ke fallback default di bawah.
      }
    }
    return s.deviceMac; // default BT (bisa '' → pemanggil menandai gagal).
  }

  /// Deteksi kasar target "IP:PORT" (printer jaringan). Dipakai hanya untuk
  /// menandai jalur hardware-gated; TIDAK mengubah perilaku (tetap fallback BT).
  bool _looksLikeLanTarget(String target) {
    final parts = target.split(':');
    if (parts.length != 2) return false;
    final octets = parts.first.split('.');
    if (octets.length != 4) return false;
    return octets.every((o) => int.tryParse(o) != null) &&
        int.tryParse(parts[1]) != null;
  }

  /// E11: bangun byte ESC/POS satu tiket dapur/bar. MURNI & injectable — tak
  /// menyentuh I/O printer sehingga bisa di-golden-test dengan [Generator] +
  /// [CapabilityProfile] yang dimuat di test. LEBIH RAMPING dari struk:
  /// header nama stasiun bold size-2; meta pesanan (no/meja/tipe/waktu); lalu
  /// per baris `qty x nama (varian)` + baris `+ modifier` (indent) + `* catatan`.
  /// TANPA harga, TANPA total, TANPA QR, TANPA logo. Diakhiri [Generator.cut].
  List<int> buildStationTicket(
    Generator gen, {
    required String stationName,
    required KitchenOrderMeta orderMeta,
    required List<KitchenTicketItem> items,
  }) {
    final bytes = <int>[];
    bytes.addAll(gen.reset());

    // Header: nama stasiun, bold size-2, tengah.
    bytes.addAll(
      gen.text(
        _safe(stationName),
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
        bytes.addAll(gen.text(_safe('  * ${it.note}'), styles: const PosStyles()));
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
    return PrintBluetoothThermal.writeBytes(<int>[...gen.drawer()]);
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
    for (final sale in sales) {
      if (!sale.countsAsSale) continue;
      if (sale.paymentMethod == 'QRIS') totalQris += sale.netTotal;
      if (sale.paymentMethod == 'Kartu') totalCard += sale.netTotal;
      if (sale.paymentMethod == 'Transfer') totalTransfer += sale.netTotal;
      if (sale.paymentMethod == 'Tunai') totalCash += sale.netTotal;
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
      ...gen.hr(ch: '-'),
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
      ...gen.hr(ch: '-'),
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

    return PrintBluetoothThermal.writeBytes(bytes);
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
          gen.text(_safe('  + ${it.modifiersLabel}'), styles: const PosStyles()),
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
