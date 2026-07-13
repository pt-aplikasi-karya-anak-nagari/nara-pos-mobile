/// Runtime configuration dari compile-time environment variable
/// (lihat [String.fromEnvironment]).
///
/// Semua nilai punya default DEV supaya `flutter run` langsung jalan TANPA
/// `--dart-define-from-file`. Untuk mengubah target (mis. server produksi),
/// override lewat `--dart-define-from-file=env/dev.json` atau `--dart-define`.
class AppConfig {
  AppConfig._();

  /// Host backend tanpa trailing slash (mis. `https://api.example.com`).
  /// Default = backend dev di LAN. Ganti IP ini bila alamat mesin berubah,
  /// atau override lewat dart-define.
  static const String apiHost = String.fromEnvironment(
    'API_HOST',
    defaultValue: 'http://192.0.88.24:3001',
  );

  /// Path versi API, mis. `/api/v1`.
  static const String apiBasePath = String.fromEnvironment(
    'API_BASE_PATH',
    defaultValue: '/api/v1',
  );

  /// HMAC secret untuk header `X-SIGNATURE`. Harus cocok dengan
  /// `api_secret_key` di config backend. Override untuk produksi.
  static const String apiSecret = String.fromEnvironment(
    'API_SECRET',
    defaultValue: 'mako_api_secret_key_789',
  );

  /// URL absolut base API (host + basePath).
  static String get apiBaseUrl => '$apiHost$apiBasePath';

  /// Pre-fill email login — hanya dipakai di debug mode untuk memudahkan QA.
  static const String devLoginEmail = String.fromEnvironment(
    'DEV_LOGIN_EMAIL',
    defaultValue: 'febriqgalp@gmail.com',
  );

  /// Pre-fill password login — hanya dipakai di debug mode.
  static const String devLoginPassword = String.fromEnvironment(
    'DEV_LOGIN_PASSWORD',
    defaultValue: 'password123',
  );

  /// Base URL halaman menu QR — dipakai untuk men-generate QR code per meja
  /// yang dipasang di cafe. URL final:
  ///   `<makoScanQrBaseUrl>/?outlet=<outletId>&table=<tableId>`
  ///
  /// Boleh kosong bila fitur QR belum dipakai. Kalau kosong, dialog QR
  /// menampilkan instruksi setup, bukan crash.
  static const String _naraScanQrBaseUrl = String.fromEnvironment(
    'NARA_SCAN_QR_BASE_URL',
    defaultValue: 'http://192.0.18.51:3001',
  );
  static const String _legacyScanQrBaseUrl = String.fromEnvironment(
    'MAKO_SCAN_QR_BASE_URL',
  );
  static String get makoScanQrBaseUrl =>
      _naraScanQrBaseUrl.isNotEmpty ? _naraScanQrBaseUrl : _legacyScanQrBaseUrl;

  /// Pastikan konfigurasi wajib sudah terisi. Panggil di `main()` sebelum
  /// `runApp` agar misconfig terdeteksi sejak awal.
  static void assertValid() {
    assert(
      apiHost.isNotEmpty,
      'API_HOST belum diset. Jalankan dengan '
      '--dart-define-from-file=env/dev.json',
    );
    assert(
      apiSecret.isNotEmpty,
      'API_SECRET belum diset. Jalankan dengan '
      '--dart-define-from-file=env/dev.json',
    );
  }
}
