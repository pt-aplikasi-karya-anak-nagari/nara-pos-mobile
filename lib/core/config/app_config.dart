/// Flavor / environment build. Selaras dengan backend (`SERVER_ENVIRONMENT`
/// = development/production) dan web (`.env.local`): dev = mesin lokal/LAN,
/// prod = server produksi.
enum Flavor {
  dev,
  prod;

  /// Label manusiawi untuk banner / UI.
  String get label => this == Flavor.prod ? 'Production' : 'Development';

  /// Nama pendek (id) — cocok dengan nama file env & Android product flavor.
  String get id => this == Flavor.prod ? 'prod' : 'dev';
}

/// Runtime configuration dari compile-time environment variable
/// (lihat [String.fromEnvironment]).
///
/// Default-nya sudah diisi nilai DEV supaya `flutter run` langsung jalan
/// TANPA perlu `--dart-define-from-file`. Flag itu kini OPSIONAL — dipakai
/// hanya bila ingin meng-override (mis. build produksi):
/// ```
/// # Dev (default)
/// flutter run --flavor dev --dart-define-from-file=env/dev.json
/// # Prod (release)
/// flutter build apk --release --flavor prod --dart-define-from-file=env/prod.json
/// ```
///
/// ⚠️ Karena default dev (termasuk secret dev) ikut ter-compile, untuk build
/// PRODUKSI tetap override via `--dart-define-from-file=env/prod.json`.
class AppConfig {
  AppConfig._();

  /// Environment build aktif. Diisi dari dart-define `APP_ENV` (nilai
  /// "dev"/"prod"; "development"/"production" juga diterima). Default = dev.
  static const String _appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  /// Flavor aktif.
  static Flavor get flavor {
    final v = _appEnv.trim().toLowerCase();
    return (v == 'prod' || v == 'production') ? Flavor.prod : Flavor.dev;
  }

  static bool get isProd => flavor == Flavor.prod;
  static bool get isDev => !isProd;

  /// Label environment untuk banner / diagnostik ("Development"/"Production").
  static String get flavorLabel => flavor.label;

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

  /// HMAC secret untuk header `X-SIGNATURE`. Default = secret DEV (harus
  /// cocok dengan `api_secret_key` di config backend). Override untuk produksi.
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

  /// Base URL halaman menu QR — dipakai untuk
  /// men-generate QR code per meja yang dipasang di cafe. URL final:
  ///   `<naraScanQrBaseUrl>/?outlet=<outletId>&table=<tableId>`
  ///
  /// Boleh kosong di env pengembangan kalau fitur QR belum dipakai. Kalau
  /// kosong, dialog QR akan menampilkan instruksi setup, bukan crash.
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

  /// Peringatan konfigurasi (dikembalikan untuk di-log di `main`, tidak fatal).
  /// Di build PRODUKSI, host non-https atau menuju localhost/LAN hampir pasti
  /// salah konfigurasi (ketinggalan pakai env dev). Selaras dengan fail-fast
  /// produksi di backend (config.LoadConfig).
  static List<String> configWarnings() {
    final w = <String>[];
    if (isProd) {
      final host = apiHost.toLowerCase();
      if (host.startsWith('http://')) {
        w.add('Flavor PROD tapi API_HOST bukan https ($apiHost).');
      }
      if (host.contains('localhost') ||
          host.contains('127.0.0.1') ||
          host.contains('192.168.') ||
          host.contains('10.0.') ||
          host.contains('192.0.')) {
        w.add('Flavor PROD tapi API_HOST mengarah ke alamat lokal/LAN ($apiHost) '
            '— apakah lupa pakai env/prod.json?');
      }
    }
    return w;
  }
}
