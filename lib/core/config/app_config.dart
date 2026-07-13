/// Konfigurasi runtime aplikasi.
///
/// Nilai di sini ditulis langsung sebagai konstanta di dalam kode — BUKAN dari
/// environment / `--dart-define` / file `env/*.json`. Untuk mengubah target
/// server, cukup edit nilai konstanta di bawah, terutama [apiHost] (dan
/// [makoScanQrBaseUrl]).
///
/// Untuk dev di LAN, `./scripts/set_dev_ip.sh` bisa menyetel [apiHost] otomatis
/// ke IP Mac saat ini supaya tidak perlu edit manual tiap IP DHCP berubah.
class AppConfig {
  AppConfig._();

  /// Host backend tanpa trailing slash (mis. `https://api.example.com`).
  /// Ganti IP/host ini bila alamat server berubah.
  static const String apiHost = 'http://192.168.1.25:3001';

  /// Path versi API, mis. `/api/v1`.
  static const String apiBasePath = '/api/v1';

  /// HMAC secret untuk header `X-SIGNATURE`. Harus cocok dengan
  /// `api_secret_key` di config backend.
  static const String apiSecret = 'mako_api_secret_key_789';

  /// URL absolut base API (host + basePath).
  static String get apiBaseUrl => '$apiHost$apiBasePath';

  /// Pre-fill email login — hanya dipakai di debug mode untuk memudahkan QA.
  static const String devLoginEmail = 'febriqgalp@gmail.com';

  /// Pre-fill password login — hanya dipakai di debug mode.
  static const String devLoginPassword = 'password123';

  /// Base URL halaman menu QR — dipakai untuk men-generate QR code per meja
  /// yang dipasang di cafe. URL final:
  ///   `<makoScanQrBaseUrl>/?outlet=<outletId>&table=<tableId>`
  ///
  /// Boleh dikosongkan bila fitur QR belum dipakai. Kalau kosong, dialog QR
  /// menampilkan instruksi setup, bukan crash.
  static const String makoScanQrBaseUrl = 'http://192.168.1.25:3001';

  /// Sanity check konfigurasi wajib. Panggil di `main()` sebelum `runApp`.
  /// Assertion hanya aktif di debug build.
  static void assertValid() {
    assert(apiHost.isNotEmpty, 'apiHost tidak boleh kosong.');
    assert(apiSecret.isNotEmpty, 'apiSecret tidak boleh kosong.');
  }
}
