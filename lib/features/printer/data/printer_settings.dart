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

  const PrinterSettings({
    this.deviceMac = '',
    this.deviceName = '',
    this.paperSize = PaperSize.mm58,
    this.storeName = 'NARA',
    this.storeAddress = '',
    this.storeFooter = 'Terima kasih atas kunjungan Anda',
    this.autoPrint = false,
    this.copies = 1,
  });

  bool get hasDevice => deviceMac.isNotEmpty;

  PrinterSettings copyWith({
    String? deviceMac,
    String? deviceName,
    PaperSize? paperSize,
    String? storeName,
    String? storeAddress,
    String? storeFooter,
    bool? autoPrint,
    int? copies,
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
    );
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
}

final printerSettingsProvider =
    NotifierProvider<PrinterSettingsNotifier, PrinterSettings>(
      PrinterSettingsNotifier.new,
    );
