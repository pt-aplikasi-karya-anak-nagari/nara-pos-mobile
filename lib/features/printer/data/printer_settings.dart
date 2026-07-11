import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/shared_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrinterSettings {
  final String deviceMac;
  final String deviceName;
  final PaperSize paperSize;
  final String storeName;
  final String storeAddress;
  final String storeFooter;
  final bool autoPrint;
  final int copies;

  /// E11: cetak tiket dapur/bar otomatis saat checkout kasir. Default false —
  /// perilaku lama (tanpa tiket dapur) tetap kalau toggle mati.
  final bool autoPrintKitchen;

  /// E11: pemetaan stasiun cetak → MAC printer Bluetooth. Kosong / tak ada
  /// entry = stasiun memakai printer BT default (deviceMac). Disimpan sebagai
  /// JSON di SharedPreferences.
  final Map<String, String> stationPrinters;

  const PrinterSettings({
    this.deviceMac = '',
    this.deviceName = '',
    this.paperSize = PaperSize.mm58,
    this.storeName = 'NARA',
    this.storeAddress = '',
    this.storeFooter = 'Terima kasih atas kunjungan Anda',
    this.autoPrint = false,
    this.copies = 1,
    this.autoPrintKitchen = false,
    this.stationPrinters = const {},
  });

  bool get hasDevice => deviceMac.isNotEmpty;

  /// MAC printer terikat untuk [stationId], atau '' bila belum diatur (konsumen
  /// harus fallback ke printer default).
  String macForStation(String stationId) => stationPrinters[stationId] ?? '';

  PrinterSettings copyWith({
    String? deviceMac,
    String? deviceName,
    PaperSize? paperSize,
    String? storeName,
    String? storeAddress,
    String? storeFooter,
    bool? autoPrint,
    int? copies,
    bool? autoPrintKitchen,
    Map<String, String>? stationPrinters,
  }) {
    return PrinterSettings(
      deviceMac: deviceMac ?? this.deviceMac,
      deviceName: deviceName ?? this.deviceName,
      paperSize: paperSize ?? this.paperSize,
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      storeFooter: storeFooter ?? this.storeFooter,
      autoPrint: autoPrint ?? this.autoPrint,
      copies: copies ?? this.copies,
      autoPrintKitchen: autoPrintKitchen ?? this.autoPrintKitchen,
      stationPrinters: stationPrinters ?? this.stationPrinters,
    );
  }
}

class PrinterSettingsNotifier extends Notifier<PrinterSettings> {
  static const _kMac = 'printer.mac';
  static const _kName = 'printer.name';
  static const _kPaper = 'printer.paper';
  static const _kStoreName = 'printer.store_name';
  static const _kStoreAddress = 'printer.store_address';
  static const _kStoreFooter = 'printer.store_footer';
  static const _kAutoPrint = 'printer.auto_print';
  static const _kCopies = 'printer.copies';
  static const _kAutoPrintKitchen = 'printer.auto_print_kitchen';
  static const _kStationPrinters = 'printer.station_printers';

  late SharedPreferences _prefs;

  @override
  PrinterSettings build() {
    _prefs = ref.read(sharedPreferencesProvider);
    return PrinterSettings(
      deviceMac: _prefs.getString(_kMac) ?? '',
      deviceName: _prefs.getString(_kName) ?? '',
      paperSize: _paperFromValue(_prefs.getInt(_kPaper) ?? 1),
      storeName: _prefs.getString(_kStoreName) ?? 'NARA',
      storeAddress: _prefs.getString(_kStoreAddress) ?? '',
      storeFooter:
          _prefs.getString(_kStoreFooter) ?? 'Terima kasih atas kunjungan Anda',
      autoPrint: _prefs.getBool(_kAutoPrint) ?? false,
      copies: _prefs.getInt(_kCopies) ?? 1,
      autoPrintKitchen: _prefs.getBool(_kAutoPrintKitchen) ?? false,
      stationPrinters: _decodeStationPrinters(
        _prefs.getString(_kStationPrinters),
      ),
    );
  }

  /// Decode JSON map {stationId: mac} yang tersimpan. Toleran terhadap data
  /// rusak / format lama — kembalikan map kosong bila gagal parse.
  Map<String, String> _decodeStationPrinters(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return const {};
  }

  PaperSize _paperFromValue(int v) {
    if (v == PaperSize.mm80.value) return PaperSize.mm80;
    if (v == PaperSize.mm72.value) return PaperSize.mm72;
    return PaperSize.mm58;
  }

  Future<void> setDevice({required String mac, required String name}) async {
    await _prefs.setString(_kMac, mac);
    await _prefs.setString(_kName, name);
    state = state.copyWith(deviceMac: mac, deviceName: name);
  }

  Future<void> clearDevice() async {
    await _prefs.remove(_kMac);
    await _prefs.remove(_kName);
    state = state.copyWith(deviceMac: '', deviceName: '');
  }

  Future<void> setPaperSize(PaperSize size) async {
    await _prefs.setInt(_kPaper, size.value);
    state = state.copyWith(paperSize: size);
  }

  Future<void> setHeader({
    required String name,
    required String address,
    required String footer,
  }) async {
    await _prefs.setString(_kStoreName, name);
    await _prefs.setString(_kStoreAddress, address);
    await _prefs.setString(_kStoreFooter, footer);
    state = state.copyWith(
      storeName: name,
      storeAddress: address,
      storeFooter: footer,
    );
  }

  Future<void> setAutoPrint(bool v) async {
    await _prefs.setBool(_kAutoPrint, v);
    state = state.copyWith(autoPrint: v);
  }

  Future<void> setCopies(int v) async {
    final clamped = v.clamp(1, 5);
    await _prefs.setInt(_kCopies, clamped);
    state = state.copyWith(copies: clamped);
  }

  Future<void> setAutoPrintKitchen(bool v) async {
    await _prefs.setBool(_kAutoPrintKitchen, v);
    state = state.copyWith(autoPrintKitchen: v);
  }

  /// Ikat [stationId] ke [mac]. [mac] kosong = lepas ikatan (kembali ke printer
  /// default). Persist sebagai JSON map.
  Future<void> setStationPrinter(String stationId, String mac) async {
    final next = Map<String, String>.from(state.stationPrinters);
    if (mac.isEmpty) {
      next.remove(stationId);
    } else {
      next[stationId] = mac;
    }
    await _prefs.setString(_kStationPrinters, json.encode(next));
    state = state.copyWith(stationPrinters: next);
  }
}

final printerSettingsProvider =
    NotifierProvider<PrinterSettingsNotifier, PrinterSettings>(
      PrinterSettingsNotifier.new,
    );
