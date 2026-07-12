import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
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
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Persist ke inbox lokal supaya muncul di halaman "Notifikasi" walau
  // user belum buka app sejak notif diterima. Background handler jalan di
  // ISOLATE TERPISAH — tidak punya ProviderScope, jadi pakai
  // `addStandalone()` yang langsung baca/tulis SharedPreferences.
  try {
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
    // Non-fatal — kalau write gagal, notif tetap dirender OS dari payload.
    // Inbox akan miss entry ini tapi user tidak terdampak signifikan.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  // Firebase wajib di-init paling awal — sebelum background handler dipasang
  // & sebelum NotificationService binding ke FirebaseMessaging.onMessage.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await initializeDateFormatting(kAppLocale);
  // Locale default global supaya semua DateFormat / NumberFormat tanpa argumen
  // locale otomatis pakai bahasa Indonesia.
  Intl.defaultLocale = kAppLocale;
  final prefs = await SharedPreferences.getInstance();
  final authStorage = AuthStorage(prefs);
  await authStorage.init();
  // Inisialisasi notifikasi bersifat best-effort. Kegagalan plugin (ikon hilang,
  // izin ditolak, channel gagal dibuat, dsb.) TIDAK boleh memblokir startup:
  // kalau exception di sini lolos tak tertangkap, runApp() di bawah tak pernah
  // jalan dan app stuck di splash putih (native launch screen). Bungkus & lewati.
  try {
    await NotificationService.instance.init();
  } catch (e, st) {
    debugPrint('NotificationService.init gagal, dilewati: $e\n$st');
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
}
