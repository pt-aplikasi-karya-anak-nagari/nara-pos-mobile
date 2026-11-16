import 'package:flutter/foundation.dart' show kReleaseMode;

/// Konfigurasi runtime aplikasi.
///
/// Alamat server dibaca dari berkas env lewat `--dart-define-from-file`:
///
///   - `env/dev.json`  — debug/profile (`scripts/run_dev`, `scripts/build_dev`).
///     Tidak di-commit; dibuat dari `env/dev.example.json`, dan
///     `scripts/set_dev_ip` mengisinya dengan IP Wi-Fi PC saat ini.
///   - `env/prod.json` — rilis (`scripts/run_prod`, `scripts/build_prod`).
///
/// Kunci: `NARA_API_HOST`, `NARA_WEB_URL`, `NARA_MENU_QR_URL`. Tanpa berkas env
/// (mis. `flutter run` polos dari IDE), nilai bawaan di bawah dipakai: nilai
/// `...Dev` untuk debug/profile, `...Rilis` untuk `--release`.
///
/// Pengaman rilis: `scripts/build_prod` menjalankan `test/app_config_test.dart`
/// DENGAN `env/prod.json`, dan [assertValid] menolak start bila build rilis
/// menunjuk ke `http://` atau IP lokal — APK pelanggan tidak bisa membawa
/// alamat laptop developer.
class AppConfig {
  AppConfig._();

  /// Host backend untuk debug/profile, tanpa trailing slash.
  ///
  /// Pakai IP Wi-Fi PC (bukan adaptor vEthernet/WSL 172.x — itu tak bisa
  /// dijangkau tablet), formatnya `http://IP:PORT` tanpa `/` sebelum port.
  static const String apiHostDev = String.fromEnvironment(
    'NARA_API_HOST',
    defaultValue: 'http://192.168.1.22:3001',
  );

  /// Host backend untuk build rilis. Wajib `https://` dan bukan IP lokal.
  static const String apiHostRilis = String.fromEnvironment(
    'NARA_API_HOST',
    defaultValue: 'https://api.nara.id',
  );

  /// Host backend yang dipakai saat ini (dipilih dari mode build).
  static const String apiHost = kReleaseMode ? apiHostRilis : apiHostDev;

  /// Path versi API, mis. `/api/v1`.
  static const String apiBasePath = '/api/v1';

  /// HMAC secret dev untuk header `X-SIGNATURE` (cocok dengan `.env` lokal).
  /// Backend produksi MENOLAK nilai ini, jadi build rilis wajib memakai
  /// secret sendiri.
  static const String apiSecretDev = 'mako_api_secret_key_789';

  /// Secret rilis TIDAK ditulis di repo: disuntik saat build lewat
  /// `--dart-define=NARA_API_SECRET=...` (dilakukan `scripts/build_prod.sh`
  /// dari env `NARA_API_SECRET`). Harus sama dengan `API_SECRET_KEY` server
  /// produksi.
  static const String apiSecretRilis = String.fromEnvironment(
    'NARA_API_SECRET',
  );

  /// HMAC secret yang dipakai saat ini (dipilih dari mode build). Debug boleh
  /// di-override juga lewat `--dart-define`.
  static const String apiSecret = kReleaseMode
      ? apiSecretRilis
      : (apiSecretRilis == '' ? apiSecretDev : apiSecretRilis);

  /// URL absolut base API (host + basePath).
  static String get apiBaseUrl => '$apiHost$apiBasePath';

  /// Base URL halaman menu QR di web — dipakai untuk men-generate QR code per
  /// meja yang dipasang di cafe. URL final: `<base>/?data=<token>`.
  ///
  /// Boleh dikosongkan bila fitur QR belum dipakai. Kalau kosong, dialog QR
  /// menampilkan instruksi setup, bukan crash.
  static const String makoScanQrBaseUrlDev = String.fromEnvironment(
    'NARA_MENU_QR_URL',
    defaultValue: 'http://192.168.1.22:3000/menu',
  );

  /// Base URL menu QR untuk build rilis (web produksi).
  static const String makoScanQrBaseUrlRilis = String.fromEnvironment(
    'NARA_MENU_QR_URL',
    defaultValue: 'https://app.nara.id/menu',
  );

  /// Dashboard web — pendaftaran akun Pemilik HANYA lewat web; aplikasi kasir
  /// cukup membuka halaman daftarnya di browser.
  static const String webBaseUrlDev = String.fromEnvironment(
    'NARA_WEB_URL',
    defaultValue: 'http://192.168.1.22:3000',
  );
  static const String webBaseUrlRilis = String.fromEnvironment(
    'NARA_WEB_URL',
    defaultValue: 'https://app.nara.id',
  );
  static const String webBaseUrl = kReleaseMode
      ? webBaseUrlRilis
      : webBaseUrlDev;

  /// Halaman pendaftaran akun Pemilik di web.
  static const String daftarPemilikUrl = '$webBaseUrl/register';

  /// Base URL menu QR yang dipakai saat ini (dipilih dari mode build).
  static const String makoScanQrBaseUrl = kReleaseMode
      ? makoScanQrBaseUrlRilis
      : makoScanQrBaseUrlDev;

  /// Sanity check konfigurasi wajib. Panggil di `main()` sebelum `runApp`.
  /// Assertion hanya aktif di debug build.
  static void assertValid() {
    assert(apiHost.isNotEmpty, 'apiHost tidak boleh kosong.');
    assert(apiSecret.isNotEmpty, 'apiSecret tidak boleh kosong.');
    // Assert mati di rilis — build rilis tanpa secret harus tetap ketahuan.
    if (kReleaseMode && apiSecret.isEmpty) {
      throw StateError(
        'NARA_API_SECRET kosong: build rilis wajib lewat scripts/build_prod.sh '
        'dengan env NARA_API_SECRET.',
      );
    }
    // Build rilis yang tak sengaja memakai env/dev.json.
    if (kReleaseMode) {
      for (final url in [apiHost, webBaseUrl]) {
        final masalah = masalahAlamatRilis(url);
        if (masalah != null) {
          throw StateError(
            'Alamat rilis $url ditolak: $masalah. Build lewat scripts/build_prod.',
          );
        }
      }
    }
  }
}

/// Alamat untuk build rilis harus https dan bukan host lokal — supaya APK
/// yang sampai ke pelanggan tidak menunjuk ke laptop developer. null = sah.
String? masalahAlamatRilis(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return 'bukan URL yang valid';
  if (uri.scheme != 'https') return 'harus https://, bukan ${uri.scheme}://';
  final h = uri.host;
  final lokal =
      h == 'localhost' ||
      h.endsWith('.local') ||
      h.endsWith('.localhost') ||
      RegExp(r'^(127|10)\.').hasMatch(h) ||
      RegExp(r'^192\.168\.').hasMatch(h) ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(h) ||
      RegExp(r'^169\.254\.').hasMatch(h);
  if (lokal) return 'host lokal/LAN ($h) tidak boleh dipakai di rilis';
  return null;
}

/// Panduan hapus akun & unduh data (Kebijakan Privasi) — juga URL yang
/// didaftarkan di Play Console sebagai "Delete account URL".
const String urlPanduanHapusAkun = '${AppConfig.webBaseUrl}/privasi#hapus-akun';
