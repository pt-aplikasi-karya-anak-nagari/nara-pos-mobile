import 'package:flutter/foundation.dart' show kReleaseMode;

/// Konfigurasi runtime aplikasi.
///
/// Nilai di sini ditulis langsung sebagai konstanta di dalam kode — BUKAN dari
/// environment / `--dart-define` / file `env/*.json`, jadi app langsung jalan
/// tanpa flag build.
///
/// Server DEV dan RILIS dipisah jadi dua konstanta, dipilih otomatis oleh mode
/// build: `flutter build/run --release` → nilai `...Rilis`; debug & profile →
/// nilai `...Dev`. Dengan begitu APK rilis tidak bisa ikut membawa IP LAN.
/// Test `test/app_config_test.dart` (jalan di CI) dan `scripts/build_prod.sh`
/// menolak nilai rilis yang masih `http://` atau IP lokal.
///
/// Untuk dev di LAN, `./scripts/set_dev_ip.sh` (Mac) menyetel [apiHostDev]
/// otomatis ke IP saat ini. Di Windows via kabel USB, set [apiHostDev] ke
/// `http://127.0.0.1:3001` lalu pakai `scripts/run_dev_windows.ps1`.
class AppConfig {
  AppConfig._();

  /// Host backend untuk debug/profile, tanpa trailing slash.
  ///
  /// Pakai IP Wi-Fi PC (bukan adaptor vEthernet/WSL 172.x — itu tak bisa
  /// dijangkau tablet), formatnya `http://IP:PORT` tanpa `/` sebelum port.
  static const String apiHostDev = 'http://192.168.1.22:3001';

  /// Host backend untuk build rilis. Wajib `https://` dan bukan IP lokal.
  static const String apiHostRilis = 'https://api.nara.id';

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
  static const String apiSecretRilis = String.fromEnvironment('NARA_API_SECRET');

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
  static const String makoScanQrBaseUrlDev = 'http://192.168.1.22:3000/menu';

  /// Base URL menu QR untuk build rilis (web produksi).
  static const String makoScanQrBaseUrlRilis = 'https://app.nara.id/menu';

  /// Dashboard web — pendaftaran akun Pemilik HANYA lewat web; aplikasi kasir
  /// cukup membuka halaman daftarnya di browser.
  static const String webBaseUrlDev = 'http://192.168.1.22:3000';
  static const String webBaseUrlRilis = 'https://app.nara.id';
  static const String webBaseUrl = kReleaseMode ? webBaseUrlRilis : webBaseUrlDev;

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
  }
}

/// Panduan hapus akun & unduh data (Kebijakan Privasi) — juga URL yang
/// didaftarkan di Play Console sebagai "Delete account URL".
const String urlPanduanHapusAkun = '${AppConfig.webBaseUrl}/privasi#hapus-akun';
