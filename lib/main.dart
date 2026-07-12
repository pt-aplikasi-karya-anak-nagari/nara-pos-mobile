import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
// intl mengekspor TextDirection sendiri (API LTR/RTL) yang bentrok dgn milik
// Flutter (dart:ui, ltr/rtl) yang dipakai _FallbackErrorWidget → sembunyikan.
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/auth_storage.dart';
import 'core/config/app_config.dart';
import 'core/format.dart';
import 'core/notifications.dart';
import 'core/shared_prefs.dart';
import 'features/notifications/data/notification_history.dart';
import 'features/notifications/domain/app_notification.dart';
import 'firebase_options.dart';

/// Background message handler. WAJIB top-level + `@pragma('vm:entry-point')`
/// karena dipanggil dari isolate terpisah saat app di-killed / di-background.
/// Tidak boleh akses state Riverpod / Navigator — isolate context berbeda.
///
/// Server FCM mengirim payload dengan field `notification` (title+body) yang
/// otomatis dirender oleh OS sebagai banner — handler ini hanya perlu memastikan
/// Firebase ter-init di isolate baru supaya tidak crash kalau ada data payload
/// yang ingin diolah di sini ke depannya.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // SELURUH body dibungkus try/catch. Handler ini jalan di ISOLATE TERPISAH yang
  // TIDAK tercakup runZonedGuarded di main() — jadi Firebase.initializeApp yang
  // gagal (mis. Play Services usang) pun tak boleh meng-crash isolate &
  // menghilangkan pemrosesan notif. Notif tetap dirender OS dari payload.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Persist ke inbox lokal supaya muncul di halaman "Notifikasi" walau
    // user belum buka app sejak notif diterima. Background handler jalan di
    // ISOLATE TERPISAH — tidak punya ProviderScope, jadi pakai
    // `addStandalone()` yang langsung baca/tulis SharedPreferences.
    final notif = message.notification;
    final data = message.data;
    final id =
        message.messageId ??
        '${data['order_id'] ?? ''}-${DateTime.now().microsecondsSinceEpoch}';
    await NotificationHistory.addStandalone(
      AppNotification(
        id: id,
        title: notif?.title ?? data['title']?.toString() ?? 'Notifikasi',
        body: notif?.body ?? data['body']?.toString() ?? '',
        type: data['type']?.toString(),
        orderId: data['order_id']?.toString(),
        invoiceNo: data['invoice_no']?.toString(),
        table: data['table']?.toString(),
        receivedAt: DateTime.now(),
      ),
    );
  } catch (_) {
    // Non-fatal — kalau init/write gagal, notif tetap dirender OS dari payload.
    // Inbox akan miss entry ini tapi user tidak terdampak signifikan.
  }
}

Future<void> main() async {
  // Seluruh bootstrap dijalankan dalam SATU zona terjaga. Error async yang lolos
  // (callback notifikasi fire-and-forget, microtask offline-sync, post-frame
  // initial-message, dsb.) ditangkap di sini & DICATAT — tidak dibiarkan menjadi
  // crash diam yang menyisakan layar putih (native splash) selamanya.
  runZonedGuarded(_bootstrap, (error, stack) {
    debugPrint('[NARA] Uncaught zone error: $error\n$stack');
  });
}

/// Bootstrap aplikasi. Dipisah dari [main] agar bisa dipanggil ULANG oleh tombol
/// "Coba lagi" di [_BootstrapErrorApp] tanpa perlu membungkus zona baru.
///
/// KONTRAK: apa pun yang terjadi, fungsi ini SELALU memanggil `runApp(...)` —
/// entah app sungguhan (sukses) atau [_BootstrapErrorApp] (gagal total). Tidak
/// pernah return tanpa merender frame, sehingga native launch screen (putih)
/// tak akan pernah menetap.
Future<void> _bootstrap() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // Error handler global: apa pun yang lolos JANGAN sampai menyisakan layar putih
  // tanpa info. Render sebagai widget error (release-safe) & catat ke log.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[NARA] FlutterError: ${details.exception}');
  };
  binding.platformDispatcher.onError = (error, stack) {
    debugPrint('[NARA] PlatformDispatcher error: $error\n$stack');
    return true; // ditangani — jangan sampai jadi crash tak tertangani.
  };
  ErrorWidget.builder = (details) => _FallbackErrorWidget(details: details);

  try {
    AppConfig.assertValid();

    // Flavor runtime (flutter_flavor). Dipilih dari APP_ENV (env/*.json). `name`
    // dikosongkan untuk PROD → FlavorBanner tidak menampilkan ribbon (app bersih);
    // untuk DEV → ribbon "DEV" muncul di sudut. variables menyimpan info env untuk
    // diakses di mana saja (mis. debug panel).
    FlavorConfig(
      name: AppConfig.isProd ? '' : AppConfig.flavor.id.toUpperCase(),
      color: const Color(0xFFB0231F),
      location: BannerLocation.topEnd,
      variables: {
        'env': AppConfig.flavorLabel,
        'apiBaseUrl': AppConfig.apiBaseUrl,
      },
    );

    // Jelaskan environment aktif di log startup + peringatkan misconfig produksi
    // (mis. build prod tapi masih mengarah ke backend LAN).
    debugPrint('[NARA] flavor=${AppConfig.flavor.id} '
        '(${AppConfig.flavorLabel}) · API=${AppConfig.apiBaseUrl}');
    for (final warn in AppConfig.configWarnings()) {
      debugPrint('[NARA] ⚠️  $warn');
    }

    // Firebase best-effort. Config prod bisa mismatch, Play Services usang, atau
    // channel gagal → JANGAN blokir startup: app tetap jalan mode tanpa-push.
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    } catch (e, st) {
      debugPrint('[NARA] Firebase.initializeApp gagal (mode tanpa-push): $e\n$st');
    }

    try {
      await initializeDateFormatting(kAppLocale);
    } catch (e) {
      debugPrint('[NARA] initializeDateFormatting gagal: $e');
    }
    // Locale default global supaya semua DateFormat / NumberFormat tanpa argumen
    // locale otomatis pakai bahasa Indonesia.
    Intl.defaultLocale = kAppLocale;

    // SharedPreferences WAJIB (dipakai ProviderScope override + AuthStorage).
    // Kalau ini gagal, tak ada yang bisa dibangun normal → jatuh ke catch luar &
    // tampilkan _BootstrapErrorApp (bukan layar putih).
    final prefs = await SharedPreferences.getInstance();

    // AuthStorage best-effort: secure-storage bisa throw saat decrypt (mis.
    // setelah restore backup ke device baru, upgrade OS, atau key ter-invalidasi).
    // Gagal → lanjut sebagai logged-out (token in-memory null → diarahkan ke
    // login), BUKAN blank. Detail resilience baca-key ada di AuthStorage.init().
    final authStorage = AuthStorage(prefs);
    try {
      await authStorage.init();
    } catch (e, st) {
      debugPrint('[NARA] AuthStorage.init gagal (lanjut logged-out): $e\n$st');
    }

    // Inisialisasi notifikasi bersifat best-effort. Kegagalan plugin (ikon hilang,
    // izin ditolak, channel gagal dibuat, dsb.) TIDAK boleh memblokir startup.
    try {
      await NotificationService.instance.init();
    } catch (e, st) {
      debugPrint('[NARA] NotificationService.init gagal, dilewati: $e\n$st');
    }

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    runApp(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authStorageProvider.overrideWithValue(authStorage),
        ],
        child: const NaraApp(),
      ),
    );
  } catch (e, st) {
    // Jaring pengaman terakhir: bootstrap gagal total (mis. SharedPreferences tak
    // bisa dibuka). SELALU render sesuatu — tak pernah layar putih diam.
    debugPrint('[NARA] Bootstrap gagal total: $e\n$st');
    runApp(_BootstrapErrorApp(error: e, onRetry: _bootstrap));
  }
}

/// Layar fallback saat bootstrap gagal total. Menampilkan pesan + tombol "Coba
/// lagi" yang menjalankan ulang [_bootstrap] (mengganti dirinya dengan app
/// sungguhan bila init kedua sukses). Detail error hanya tampil di non-release.
class _BootstrapErrorApp extends StatelessWidget {
  const _BootstrapErrorApp({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 56,
                  color: Color(0xFFB0231F),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Gagal memuat aplikasi',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Terjadi kendala saat memulai. Coba lagi, atau tutup lalu buka '
                  'kembali aplikasi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                if (!kReleaseMode) ...[
                  const SizedBox(height: 12),
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: Colors.black38),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pengganti kotak error abu-abu default Flutter. Dibungkus [Directionality] +
/// [Material] sendiri supaya aman dirender di mana pun di pohon widget (termasuk
/// di atas MaterialApp, saat belum ada Directionality ancestor).
class _FallbackErrorWidget extends StatelessWidget {
  const _FallbackErrorWidget({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: const Color(0xFFFAFAFA),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 40,
                  color: Color(0xFFB0231F),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Terjadi kesalahan menampilkan halaman',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (!kReleaseMode) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${details.exception}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
