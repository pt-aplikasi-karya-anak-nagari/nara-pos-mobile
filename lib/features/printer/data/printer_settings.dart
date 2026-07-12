import 'dart:async';
import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/shared_prefs.dart';
import '../../user/data/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pengaturan printer thermal OFFLINE — sekarang PER-USER per-device.
///
/// Semua key SharedPreferences diberi awalan id user yang sedang login
/// (`printer.<userId>.<key>`) supaya tiap kasir yang login di device yang sama
/// menyimpan pengaturannya sendiri (printer terpasang, ukuran kertas, dst.).
/// Saat belum login / logout dipakai namespace bersama `printer.__shared__.*`.
///
/// Empat field perilaku (auto-print struk, auto-print dapur, jumlah salinan,
/// ukuran kertas) bersifat TRI-STATE: bila key TIDAK ADA berarti user mengikuti
/// default ROLE dari backend (lihat [RolePrinterConfig]); bila key ADA berarti
/// user menimpanya secara eksplisit. Karena itu keempatnya disimpan sebagai
/// getter nullable (`*Override`). Device MAC/nama + pemetaan stasiun tetap plain
/// per-user (properti hardware device+user, bukan tri-state).
class PrinterSettings {
  final String deviceMac;
  final String deviceName;

  /// Override ukuran kertas milik user. `null` = ikuti default role.
  final PaperSize? paperSizeOverride;

  final String storeName;
  final String storeAddress;
  final String storeFooter;

  /// Override auto-print struk milik user. `null` = ikuti default role.
  final bool? autoPrintOverride;

  /// Override jumlah salinan milik user. `null` = ikuti default role.
  final int? copiesOverride;

  /// Override auto-print tiket dapur/bar milik user. `null` = ikuti default
  /// role. Default lama (tanpa tiket dapur) tetap dipertahankan lewat default
  /// role hardcoded `false`.
  final bool? autoPrintKitchenOverride;

  /// E11: pemetaan stasiun cetak → MAC printer Bluetooth. Kosong / tak ada
  /// entry = stasiun memakai printer BT default (deviceMac). Disimpan sebagai
  /// JSON di SharedPreferences.
  final Map<String, String> stationPrinters;

  const PrinterSettings({
    this.deviceMac = '',
    this.deviceName = '',
    this.paperSizeOverride,
    this.storeName = 'NARA',
    this.storeAddress = '',
    this.storeFooter = 'Terima kasih atas kunjungan Anda',
    this.autoPrintOverride,
    this.copiesOverride,
    this.autoPrintKitchenOverride,
    this.stationPrinters = const {},
  });

  bool get hasDevice => deviceMac.isNotEmpty;

  // ── Getter kompat-mundur (fallback hardcoded, BUKAN sadar-role) ──────────
  //
  // Dipakai kode yang butuh nilai konkret tanpa lapisan role (mis. test print,
  // tiket dapur, laporan shift, laci kas). Nilai efektif yang sudah menggabung
  // default role ada di [EffectivePrinterConfig].

  /// Ukuran kertas pilihan user, atau 58mm bila belum diatur.
  PaperSize get paperSize => paperSizeOverride ?? PaperSize.mm58;

  /// Auto-print struk pilihan user, atau `false` bila belum diatur.
  bool get autoPrint => autoPrintOverride ?? false;

  /// Jumlah salinan pilihan user, atau 1 bila belum diatur.
  int get copies => copiesOverride ?? 1;

  /// Auto-print tiket dapur pilihan user, atau `false` bila belum diatur.
  bool get autoPrintKitchen => autoPrintKitchenOverride ?? false;

  /// MAC printer terikat untuk [stationId], atau '' bila belum diatur (konsumen
  /// harus fallback ke printer default).
  String macForStation(String stationId) => stationPrinters[stationId] ?? '';
}

class PrinterSettingsNotifier extends Notifier<PrinterSettings> {
  // Nama dasar key (tanpa awalan namespace). Awalan penuh dibangun di [_key].
  static const _kMac = 'mac';
  static const _kName = 'name';
  static const _kPaper = 'paper';
  static const _kStoreName = 'store_name';
  static const _kStoreAddress = 'store_address';
  static const _kStoreFooter = 'store_footer';
  static const _kAutoPrint = 'auto_print';
  static const _kCopies = 'copies';
  static const _kAutoPrintKitchen = 'auto_print_kitchen';
  static const _kStationPrinters = 'station_printers';

  static const _all = <String>[
    _kMac,
    _kName,
    _kPaper,
    _kStoreName,
    _kStoreAddress,
    _kStoreFooter,
    _kAutoPrint,
    _kCopies,
    _kAutoPrintKitchen,
    _kStationPrinters,
  ];

  late SharedPreferences _prefs;
  late String _ns;

  @override
  PrinterSettings build() {
    _prefs = ref.read(sharedPreferencesProvider);
    // Rebuild saat user berganti (login/logout) supaya memuat namespace yang
    // benar. Hanya pantau id user — abaikan rotasi token, dll.
    final userId = ref.watch(authProvider.select((s) => s.user?.remoteId));
    _ns = (userId == null || userId.isEmpty) ? '__shared__' : userId;
    _migrateLegacy();
    return _load();
  }

  String _key(String base) => 'printer.$_ns.$base';

  /// Migrasi satu-kali key lama tak-berawalan (`printer.<key>`) ke namespace
  /// user yang SEKARANG login (device owner). Legacy key dikonsumsi (dihapus)
  /// setelah disalin supaya tidak ikut ter-migrasi ke user berikutnya di device
  /// yang sama — user baru mulai bersih.
  ///
  /// Hanya berjalan saat ada user login: kalau dijalankan di namespace bersama
  /// (belum login) legacy key akan terhapus sebelum sempat dimiliki device
  /// owner sebenarnya, sehingga owner kehilangan printer-nya.
  void _migrateLegacy() {
    if (_ns == '__shared__') return;
    for (final base in _all) {
      final legacyKey = 'printer.$base';
      if (!_prefs.containsKey(legacyKey)) continue;
      final newKey = _key(base);
      if (!_prefs.containsKey(newKey)) {
        final v = _prefs.get(legacyKey);
        if (v is String) {
          unawaited(_prefs.setString(newKey, v));
        } else if (v is int) {
          unawaited(_prefs.setInt(newKey, v));
        } else if (v is bool) {
          unawaited(_prefs.setBool(newKey, v));
        } else if (v is double) {
          unawaited(_prefs.setDouble(newKey, v));
        }
      }
      unawaited(_prefs.remove(legacyKey));
    }
  }

  PrinterSettings _load() {
    return PrinterSettings(
      deviceMac: _prefs.getString(_key(_kMac)) ?? '',
      deviceName: _prefs.getString(_key(_kName)) ?? '',
      paperSizeOverride: _prefs.containsKey(_key(_kPaper))
          ? _paperFromValue(_prefs.getInt(_key(_kPaper))!)
          : null,
      storeName: _prefs.getString(_key(_kStoreName)) ?? 'NARA',
      storeAddress: _prefs.getString(_key(_kStoreAddress)) ?? '',
      storeFooter: _prefs.getString(_key(_kStoreFooter)) ??
          'Terima kasih atas kunjungan Anda',
      autoPrintOverride: _prefs.containsKey(_key(_kAutoPrint))
          ? _prefs.getBool(_key(_kAutoPrint))
          : null,
      copiesOverride: _prefs.containsKey(_key(_kCopies))
          ? _prefs.getInt(_key(_kCopies))
          : null,
      autoPrintKitchenOverride: _prefs.containsKey(_key(_kAutoPrintKitchen))
          ? _prefs.getBool(_key(_kAutoPrintKitchen))
          : null,
      stationPrinters: _decodeStationPrinters(
        _prefs.getString(_key(_kStationPrinters)),
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
    await _prefs.setString(_key(_kMac), mac);
    await _prefs.setString(_key(_kName), name);
    state = _load();
  }

  Future<void> clearDevice() async {
    await _prefs.remove(_key(_kMac));
    await _prefs.remove(_key(_kName));
    state = _load();
  }

  // ── Setter override (menulis key = menimpa default role) ─────────────────

  Future<void> setPaperSize(PaperSize size) async {
    await _prefs.setInt(_key(_kPaper), size.value);
    state = _load();
  }

  /// Hapus override ukuran kertas → kembali mengikuti default role.
  Future<void> clearPaperSize() async {
    await _prefs.remove(_key(_kPaper));
    state = _load();
  }

  Future<void> setHeader({
    required String name,
    required String address,
    required String footer,
  }) async {
    await _prefs.setString(_key(_kStoreName), name);
    await _prefs.setString(_key(_kStoreAddress), address);
    await _prefs.setString(_key(_kStoreFooter), footer);
    state = _load();
  }

  Future<void> setAutoPrint(bool v) async {
    await _prefs.setBool(_key(_kAutoPrint), v);
    state = _load();
  }

  /// Hapus override auto-print struk → kembali mengikuti default role.
  Future<void> clearAutoPrint() async {
    await _prefs.remove(_key(_kAutoPrint));
    state = _load();
  }

  Future<void> setCopies(int v) async {
    final clamped = v.clamp(1, 5);
    await _prefs.setInt(_key(_kCopies), clamped);
    state = _load();
  }

  /// Hapus override jumlah salinan → kembali mengikuti default role.
  Future<void> clearCopies() async {
    await _prefs.remove(_key(_kCopies));
    state = _load();
  }

  Future<void> setAutoPrintKitchen(bool v) async {
    await _prefs.setBool(_key(_kAutoPrintKitchen), v);
    state = _load();
  }

  /// Hapus override auto-print tiket dapur → kembali mengikuti default role.
  Future<void> clearAutoPrintKitchen() async {
    await _prefs.remove(_key(_kAutoPrintKitchen));
    state = _load();
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
    await _prefs.setString(_key(_kStationPrinters), json.encode(next));
    state = _load();
  }
}

final printerSettingsProvider =
    NotifierProvider<PrinterSettingsNotifier, PrinterSettings>(
      PrinterSettingsNotifier.new,
    );
