import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Pelaporan crash & galat aplikasi kasir ke Sentry.
///
/// # KENAPA
///
/// Galat di tablet kasir sebelumnya hanya ditulis ke `debugPrint` — tak pernah
/// keluar dari perangkat. Tim baru tahu ada crash setelah Pemilik menelepon.
///
/// # MATI BILA TAK DIKONFIGURASI
///
/// DSN dibaca saat build: `--dart-define=SENTRY_DSN=...`. Tanpa itu tak ada
/// yang dinyalakan dan tak ada yang dikirim.
///
/// # YANG TIDAK DIKIRIM
///
/// Isi `debugPrint` (bisa memuat URL API & data transaksi), request, dan data
/// pengguna selain id. Tanpa screenshot, view hierarchy, tracing, atau replay.
/// Event yang terjadi saat offline disimpan Sentry dan dikirim saat online.
class Pantau {
  Pantau._();

  static const dsn = String.fromEnvironment('SENTRY_DSN');
  static const _environment = String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: kReleaseMode ? 'production' : 'development',
  );

  static bool _aktif = false;

  /// Apakah pelaporan menyala.
  static bool get aktif => _aktif;

  /// Nyalakan Sentry bila [dsn] terisi. Aman dipanggil berulang (tombol
  /// "Coba lagi" menjalankan ulang bootstrap). Gagal init tidak menghentikan
  /// aplikasi.
  ///
  /// Dipanggil SETELAH `FlutterError.onError` & `PlatformDispatcher.onError`
  /// milik aplikasi dipasang: Sentry membungkus keduanya dan tetap meneruskan
  /// ke penangan lama.
  static Future<void> mulai() async {
    if (_aktif || dsn.isEmpty) return;
    try {
      await SentryFlutter.init(aturOpsi);
      _aktif = true;
    } catch (e) {
      debugPrint('[NARA] Sentry gagal dinyalakan: $e');
    }
  }

  @visibleForTesting
  static void aturOpsi(SentryFlutterOptions o) {
    o.dsn = dsn;
    o.environment = _environment;
    o.sendDefaultPii = false;
    o.enablePrintBreadcrumbs = false;
    o.attachScreenshot = false;
    o.attachViewHierarchy = false;
    o.tracesSampleRate = 0;
    o.beforeSend = (event, hint) => bersihkan(event);
    o.beforeBreadcrumb = (b, hint) => b == null ? null : bersihkanBreadcrumb(b);
  }

  /// Laporkan galat yang tertangkap zona aplikasi. No-op bila mati.
  static Future<void> lapor(Object error, StackTrace? stack) async {
    if (!_aktif) return;
    try {
      await Sentry.captureException(error, stackTrace: stack);
    } catch (_) {}
  }

  /// URL tanpa query string & fragmen.
  @visibleForTesting
  static String? bersihkanUrl(String? url) {
    if (url == null) return null;
    final i = url.indexOf(RegExp(r'[?#]'));
    return i < 0 ? url : url.substring(0, i);
  }

  @visibleForTesting
  static SentryEvent bersihkan(SentryEvent event) {
    final req = event.request;
    if (req != null) {
      event.request = SentryRequest(
        url: bersihkanUrl(req.url),
        method: req.method,
      );
    }
    final user = event.user;
    if (user != null) {
      event.user = user.id == null ? null : SentryUser(id: user.id);
    }
    final crumbs = event.breadcrumbs;
    if (crumbs != null) {
      for (final b in crumbs) {
        bersihkanBreadcrumb(b);
      }
    }
    return event;
  }

  @visibleForTesting
  static Breadcrumb bersihkanBreadcrumb(Breadcrumb b) {
    final data = b.data;
    if (data != null) {
      for (final k in const ['url', 'from', 'to']) {
        final v = data[k];
        if (v is String) data[k] = bersihkanUrl(v);
      }
    }
    if (b.category == 'http' || b.category == 'navigation') {
      b.message = bersihkanUrl(b.message);
    }
    return b;
  }
}
