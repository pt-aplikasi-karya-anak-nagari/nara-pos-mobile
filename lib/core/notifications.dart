import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../features/notifications/data/notification_history.dart';
import '../features/notifications/domain/app_notification.dart';
import 'format.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _fcmListenersAttached = false;

  /// Broadcast stream untuk event "user tap notifikasi". Payload-nya adalah
  /// `data` map dari FCM RemoteMessage (mis. `{type: new_menu_order,
  /// order_id: TRX..., invoice_no: INV-..., table: A1}`).
  ///
  /// Dengarkan dari widget tree (mis. di NaraApp.builder) untuk men-trigger
  /// navigasi ke detail terkait. Broadcast supaya boleh banyak listener
  /// & late-subscriber tetap aman (subscribe setelah init tidak crash).
  final StreamController<Map<String, String>> _tapController =
      StreamController<Map<String, String>>.broadcast();

  Stream<Map<String, String>> get onNotificationTap => _tapController.stream;

  /// Broadcast stream untuk event "FCM message ARRIVE di foreground" (bukan
  /// tap). Listener pakai ini untuk side-effect otomatis — mis. cetak struk
  /// pesanan QR ke printer kasir tanpa user perlu tap notif dulu.
  ///
  /// **Tidak meliputi background/killed state**: di state itu, app tidak
  /// punya kontrol — OS render banner langsung. Side-effect yang butuh
  /// hardware (printer Bluetooth, kamera, dll) hanya bekerja di foreground.
  final StreamController<RemoteMessage> _foregroundController =
      StreamController<RemoteMessage>.broadcast();

  Stream<RemoteMessage> get onForegroundMessage => _foregroundController.stream;

  /// Broadcast stream untuk event "notif sudah ter-persist ke inbox lokal".
  /// `NotificationHistory` Notifier subscribe ke stream ini supaya state
  /// in-memory langsung sync saat FCM masuk — tanpa harus restart app
  /// / re-mount halaman / re-read SharedPreferences manual.
  ///
  /// Disk write (via `NotificationHistory.addStandalone`) tetap dilakukan
  /// oleh `_persistToHistory` di bawah, supaya data tidak hilang kalau
  /// listener Notifier kebetulan belum mount (mis. race saat cold-start).
  /// Listener-nya hanya update state in-memory; storage idempotent by id.
  final StreamController<AppNotification> _newNotifController =
      StreamController<AppNotification>.broadcast();

  Stream<AppNotification> get onNotificationReceived =>
      _newNotifController.stream;

  static const _channelId = 'mako_transactions';
  static const _channelName = 'Transaksi';
  static const _channelDesc = 'Notifikasi transaksi berhasil';

  /// Channel khusus pesan dari FCM (mis. notifikasi pesanan baru dari QR
  /// menu). Dipisah dari channel transaksi lokal supaya user bisa
  /// mengatur tone/preference per kategori di settings OS.
  ///
  /// **PENTING:** Suffix `_v3` sengaja ditambahkan karena Android tidak
  /// mengizinkan ganti sound di channel yang sudah pernah dibuat. Bila
  /// nanti sound diganti / di-aktifkan, BUMP suffix-nya (v4, v5, ...).
  /// Backend juga harus pakai channel_id yang sama — lihat
  /// `service/fcm_service.go` `ChannelID`.
  static const _fcmChannelId = 'mako_fcm_v3';
  static const _fcmChannelName = 'Pesan Realtime';
  static const _fcmChannelDesc =
      'Notifikasi push dari server (pesanan QR, dll)';

  /// Custom sound untuk channel FCM. Saat ini **DISABLED** — pakai sound
  /// default OS supaya notif tetap muncul walau file belum di-bundle.
  ///
  /// Cara enable custom sound:
  ///
  ///   1. Letakkan file audio:
  ///      - Android: `android/app/src/main/res/raw/mako_chime.mp3`
  ///        (boleh .ogg/.wav, nama harus lowercase + underscore)
  ///      - iOS:     `ios/Runner/mako_chime.caf` lalu **add ke Xcode
  ///        project** (drag ke Runner > "Add to target Runner")
  ///
  ///   2. Set kedua const di bawah:
  ///        _customSoundResource = 'mako_chime';
  ///        _customSoundIosFile  = 'mako_chime.caf';
  ///
  ///   3. **BUMP** `_fcmChannelId` ke versi baru (mis. `mako_fcm_v4`)
  ///      karena Android cache channel sound di first-create.
  ///
  ///   4. Backend `fcm_service.go`: update `ChannelID` + tambah
  ///      `Sound: "mako_chime"` di `AndroidNotification` & APNs.
  ///
  ///   5. **Uninstall + install ulang app** di device (atau bump channel
  ///      sudah cukup; uninstall lebih bersih).
  static const String? _customSoundResource = null; // null → default OS
  static const String? _customSoundIosFile = null;

  Future<void> init() async {
    if (_initialized) return;
    // Pakai drawable monochrome (silhouette) khusus notifikasi, BUKAN
    // mipmap launcher full-color. Sejak Android 5.0, status bar menampilkan
    // icon notifikasi sebagai silhouette putih — kalau pakai logo color
    // hasilnya jadi kotak putih solid. File di-generate via
    // `tool/generate_notif_icon.dart`.
    const android = AndroidInitializationSettings('@drawable/ic_notification');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const macos = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linux = LinuxInitializationSettings(defaultActionName: 'Open');
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: android,
        iOS: ios,
        macOS: macos,
        linux: linux,
      ),
      // User tap local notif (foreground FCM yang sudah dirender di sini, atau
      // notif transaksi lokal). Payload-nya JSON dari `data` FCM — kalau
      // bukan JSON valid, dilewat dengan diam.
      onDidReceiveNotificationResponse: _onLocalNotifTap,
    );

    // Daftarkan channel FCM secara eksplisit di Android. Tanpa ini, OS
    // akan pakai channel "Misc" default dengan importance Low → notif
    // foreground tidak muncul sebagai banner.
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    // Sound: kalau `_customSoundResource` di-set, pakai itu — kalau null,
    // OS akan pakai default. Penting: kalau resource ditulis tapi file
    // belum di-bundle, channel sound jadi broken & notif bisa tidak muncul
    // sama sekali. Itu sebabnya default-nya null.
    final channelSound = _customSoundResource == null
        ? null
        : RawResourceAndroidNotificationSound(_customSoundResource);
    await androidImpl?.createNotificationChannel(
      AndroidNotificationChannel(
        _fcmChannelId,
        _fcmChannelName,
        description: _fcmChannelDesc,
        importance: Importance.high,
        sound: channelSound,
        playSound: true,
      ),
    );

    await _requestPermissions();
    await _attachFcmListeners();
    _initialized = true;
  }

  /// FCM foreground listener — convert RemoteMessage jadi local-notif banner
  /// karena di state foreground OS tidak otomatis menampilkan banner.
  ///
  /// Background & terminated state otomatis di-handle OS (banner muncul,
  /// dan tap akan trigger `onMessageOpenedApp` saat app foreground lagi).
  Future<void> _attachFcmListeners() async {
    if (_fcmListenersAttached) return;
    // Permission FCM (iOS / Android 13+) — backend bisa kirim notif sebelum
    // user grant, tapi tidak akan tampil sampai di-allow.
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    // Penting di iOS — supaya FCM token aktif walau app foreground.
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    // User tap notif saat app di background → app ke foreground; emit ke
    // tap stream supaya widget tree bisa navigasi.
    FirebaseMessaging.onMessageOpenedApp.listen(_emitTap);
    _fcmListenersAttached = true;
  }

  /// Cek apakah app diluncurkan via tap notif (state terminated → tap).
  /// PANGGIL setelah widget tree pertama kali ter-mount supaya navigasi
  /// punya context. Idempotent — message yang sama tidak akan dobel emit.
  Future<void> consumeInitialMessage() async {
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      // Pastikan notif yang me-launch app juga masuk inbox lokal (bisa jadi
      // background handler isolate sudah save, tapi kalau race condition
      // belum jalan, save di sini sebagai safety net — addStandalone
      // idempotent by id).
      await _persistToHistory(initial);
      _emitTap(initial);
    }
  }

  void _emitTap(RemoteMessage message) {
    if (_tapController.isClosed) return;
    final data = <String, String>{};
    message.data.forEach((k, v) => data[k] = v?.toString() ?? '');
    if (data.isNotEmpty) _tapController.add(data);
  }

  void _onLocalNotifTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        final asString = <String, String>{};
        decoded.forEach((k, v) {
          asString[k.toString()] = v?.toString() ?? '';
        });
        if (!_tapController.isClosed) _tapController.add(asString);
      }
    } catch (_) {
      // payload bukan JSON — lewat saja (mis. notif transaksi lokal lama).
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final notif = message.notification;
    final title =
        notif?.title ?? message.data['title'] as String? ?? 'Notifikasi';
    final body = notif?.body ?? message.data['body'] as String? ?? '';
    // ID stabil dari messageId supaya update notif (mis. status pesanan
    // berubah) replace baris yang sama, bukan stack baru.
    // Mask ke int32 positif: ID notifikasi Android wajib muat di int32.
    // microsecondsSinceEpoch (~1.7e15) & String.hashCode bisa melebihi batas
    // → notifikasi gagal tampil / id terpotong & tabrakan.
    final id =
        (message.messageId?.hashCode ??
            DateTime.now().microsecondsSinceEpoch) &
        0x7fffffff;
    // Encode `data` map ke JSON supaya bisa dipulihkan saat user tap local
    // notif → `_onLocalNotifTap` decode lagi & emit ke tap stream. Tanpa
    // payload, tap dari foreground notif tidak bisa di-navigasi-kan.
    final payload = message.data.isEmpty ? null : jsonEncode(message.data);
    // Persist ke inbox lokal — fire-and-forget; kegagalan write tidak boleh
    // membatalkan rendering notif.
    unawaited(_persistToHistory(message));
    // Emit ke foreground stream untuk side-effect (auto-print struk, dll).
    // Bedakan dari `_tapController` yang hanya emit saat USER TAP — listener
    // di sini fire setiap message arrive (terlepas user tap atau tidak).
    if (!_foregroundController.isClosed) {
      _foregroundController.add(message);
    }
    // Per-notif sound override — null berarti pakai channel default
    // (yang sendiri-nya null = sound default OS).
    final androidSound = _customSoundResource == null
        ? null
        : RawResourceAndroidNotificationSound(_customSoundResource);
    _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _fcmChannelId,
          _fcmChannelName,
          channelDescription: _fcmChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          sound: androidSound,
          // Tint warna brand di icon notif saat user expand. Status bar
          // tetap silhouette putih (Android tidak izinkan warna di status
          // bar) — color ini muncul di shade panel & lock screen.
          color: Color(0xFF1B4FD8),
          colorized: true,
        ),
        iOS: DarwinNotificationDetails(sound: _customSoundIosFile),
        macOS: DarwinNotificationDetails(sound: _customSoundIosFile),
      ),
    );
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  Future<void> showTransactionSuccess({
    required String saleId,
    String? invoiceId,
    required double total,
    required String paymentMethod,
    String? customerName,
    bool isPaid = true,
  }) async {
    if (!_initialized) await init();
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Transaksi berhasil',
      color: Color(0xFF1B4FD8),
      colorized: true,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );
    final who = (customerName != null && customerName.isNotEmpty)
        ? ' • $customerName'
        : '';
    final title = isPaid ? 'Transaksi Berhasil' : 'Pesanan Disimpan';
    final status = isPaid ? 'Lunas' : 'Belum Bayar';
    final idDisplay = (invoiceId != null && invoiceId.isNotEmpty)
        ? invoiceId
        : saleId;

    await _plugin.show(
      id: saleId.hashCode,
      title: title,
      body:
          '#$idDisplay • ${formatRupiah(total)} • $status • $paymentMethod$who',
      notificationDetails: details,
    );
  }

  /// Persist `RemoteMessage` ke inbox lokal supaya kasir bisa lihat ulang
  /// di halaman "Notifikasi" walau banner OS sudah di-swipe. Dipanggil dari:
  ///   - foreground listener (`_handleForegroundMessage`)
  ///   - initial message (`consumeInitialMessage`)
  /// Background handler isolate tidak punya akses ke instance ini —
  /// di sana panggil `NotificationHistory.addStandalone(...)` langsung.
  Future<void> _persistToHistory(RemoteMessage message) async {
    final notif = message.notification;
    final data = message.data;
    final id =
        message.messageId ??
        // Kalau FCM tidak provide messageId, generate dari konten +
        // timestamp supaya idempotent dalam window kecil.
        '${data['order_id'] ?? ''}-${DateTime.now().microsecondsSinceEpoch}';
    final entry = AppNotification(
      id: id,
      title: notif?.title ?? data['title'] as String? ?? 'Notifikasi',
      body: notif?.body ?? data['body'] as String? ?? '',
      type: data['type'] as String?,
      orderId: data['order_id'] as String?,
      invoiceNo: data['invoice_no'] as String?,
      table: data['table'] as String?,
      receivedAt: DateTime.now(),
    );
    // Write disk DULU (safety net kalau Notifier belum mount, mis. saat
    // cold-start via initial message), baru emit ke stream supaya listener
    // bisa update state in-memory tanpa baca disk lagi.
    await NotificationHistory.addStandalone(entry);
    if (!_newNotifController.isClosed) {
      _newNotifController.add(entry);
    }
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});
