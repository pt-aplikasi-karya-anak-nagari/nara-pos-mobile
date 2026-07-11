import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sizer/sizer.dart';
import 'package:toastification/toastification.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import '../shared/widgets/connectivity_banner.dart';
import '../shared/widgets/pending_sync_banner.dart';
import '../core/i18n.dart';
import '../core/offline/offline_sync_service.dart';
import '../core/notifications.dart';
import '../features/notifications/data/notification_history.dart';
import '../features/printer/data/printer_service.dart';
import '../features/printer/data/printer_settings.dart';
import '../features/subscription/ui/subscription_banner.dart';
import '../features/transactions/data/transaction_repository.dart';
import 'app_routes.dart';
import 'router.dart';
import 'theme.dart';
import 'theme_mode_provider.dart';

class NaraApp extends ConsumerWidget {
  const NaraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);
    // Aktifkan auto-sync transaksi offline sepanjang sesi: men-drain outbox
    // saat koneksi kembali online + sekali saat app start.
    ref.watch(offlineAutoSyncProvider);

    // Sinkronkan global brightness notifier sebelum subtree dibangun
    // ulang dengan theme baru. Tanpa langkah ini, getter `kBg/kCard/...`
    // bisa kembalikan nilai brightness lama saat MaterialApp rebuild
    // pertama setelah user toggle.
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final effectiveBrightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platformBrightness,
    };
    setAppBrightness(effectiveBrightness);

    return Sizer(
      builder: (context, orientation, deviceType) {
        return ToastificationWrapper(
          child: MaterialApp.router(
            // Key di-bind ke effectiveBrightness supaya entire widget
            // tree di bawah MaterialApp di-rebuild dari awal saat user
            // toggle tema. Tanpa ini, widget yang HARDCODE konstanta
            // `kBg/kCard/...` (tanpa dependency Theme.of) tidak akan
            // ikut rebuild — UI jadi mixed warna lama+baru sampai user
            // pindah halaman. GoRouter mempertahankan location, jadi
            // user tetap di halaman yang sama setelah switch.
            key: ValueKey(effectiveBrightness),
            title: 'NARA',
            debugShowCheckedModeBanner: false,
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            themeMode: themeMode,
            routerConfig: router,
            locale: locale.toLocale(),
            supportedLocales: const [Locale('id'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              final Widget app = _NotificationTapListener(
                child: _OrderRefreshListener(
                  child: _AutoPrintListener(
                    child: SubscriptionExpiryDialogListener(
                      child: Column(
                        children: [
                          const ConnectivityBanner(),
                          const PendingSyncBanner(),
                          Expanded(child: child!),
                        ],
                      ),
                    ),
                  ),
                ),
              );
              // Ribbon environment (flutter_flavor). FlavorBanner menampilkan
              // ribbon hanya bila FlavorConfig.name tidak kosong — di PROD name
              // dikosongkan (lihat main.dart), jadi app produksi bersih.
              return FlavorBanner(child: app);
            },
          ),
        );
      },
    );
  }
}

/// Mendengarkan event tap notif (FCM background/terminated, atau local
/// notif foreground yang kita render sendiri) lalu menavigasi ke detail
/// terkait. Diletakkan di `MaterialApp.builder` supaya state-nya tetap
/// hidup selama app berjalan, terlepas dari rute apa yang ditampilkan.
///
/// Konvensi payload data dari backend (lihat `transaction_service.go`
/// CreateGuestTransaction):
///   `type=new_menu_order`, `order_id=<txID>`, `invoice_no=...`, `table=...`
class _NotificationTapListener extends ConsumerStatefulWidget {
  final Widget child;
  const _NotificationTapListener({required this.child});

  @override
  ConsumerState<_NotificationTapListener> createState() =>
      _NotificationTapListenerState();
}

class _NotificationTapListenerState
    extends ConsumerState<_NotificationTapListener>
    with WidgetsBindingObserver {
  StreamSubscription<Map<String, String>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = NotificationService.instance.onNotificationTap.listen(_handleTap);
    // Pantau lifecycle app — saat resume dari background, refresh inbox
    // dari disk supaya notif yang ditulis isolate background (FCM
    // background handler di main.dart) langsung muncul tanpa restart.
    WidgetsBinding.instance.addObserver(this);
    // Konsumsi initial message (app diluncurkan dari state killed via tap
    // notif). Pakai post-frame supaya router sudah ter-mount saat di-call.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.instance.consumeInitialMessage();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Background isolate menulis ke SharedPreferences saat app tidak
      // aktif. Provider state in-memory tidak tahu, jadi pas user
      // foreground app, kita re-read disk supaya badge & list sinkron.
      ref.read(notificationHistoryProvider.notifier).refreshFromDisk();
    }
  }

  void _handleTap(Map<String, String> data) {
    if (!mounted) return;
    final type = data['type'] ?? '';
    final orderId = data['order_id'] ?? '';
    // Saat ini hanya pesanan dari menu QR yang punya destinasi spesifik.
    // Type lain di-route ke halaman riwayat umum kalau order_id ada, atau
    // di-abaikan supaya app tidak salah lompat.
    if (orderId.isEmpty) return;
    if (type == 'new_menu_order' ||
        type == 'order_updated' ||
        type == 'proof_uploaded') {
      final router = ref.read(routerProvider);
      router.pushNamed(
        AppRoutes.riwayatDetailName,
        pathParameters: {'id': orderId},
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Subscribe ke FCM foreground message dan auto-cetak struk untuk
/// pesanan baru lewat QR menu (type=`new_menu_order`).
///
/// Diaktifkan hanya kalau:
///   1. Setting `autoPrint` di Profil → Pengaturan Printer = ON.
///   2. Printer Bluetooth sudah di-pair (`hasDevice`).
///
/// Hanya bekerja di app FOREGROUND — karena printer Bluetooth butuh akses
/// ke `print_bluetooth_thermal` plugin yang hanya tersedia di main isolate.
/// Saat app di-background/killed, OS render notif sebagai banner; kasir
/// bisa tap notif → buka detail transaksi → tombol "Cetak Ulang" manual.
///
/// De-dup pakai `Set<String>` di state: order_id yang sama tidak akan
/// di-cetak dua kali walau FCM kirim duplikat (mis. retry).
class _AutoPrintListener extends ConsumerStatefulWidget {
  final Widget child;
  const _AutoPrintListener({required this.child});

  @override
  ConsumerState<_AutoPrintListener> createState() => _AutoPrintListenerState();
}

class _AutoPrintListenerState extends ConsumerState<_AutoPrintListener> {
  StreamSubscription<RemoteMessage>? _sub;
  final _printedOrderIds = <String>{};

  @override
  void initState() {
    super.initState();
    _sub = NotificationService.instance.onForegroundMessage.listen(
      _handleMessage,
    );
  }

  Future<void> _handleMessage(RemoteMessage message) async {
    if (!mounted) return;
    final data = message.data;
    final type = (data['type'] ?? '').toString();
    if (type != 'new_menu_order') return;

    final orderId = (data['order_id'] ?? '').toString();
    if (orderId.isEmpty) return;
    if (_printedOrderIds.contains(orderId)) return;
    _printedOrderIds.add(orderId);

    final settings = ref.read(printerSettingsProvider);
    // User belum aktifkan auto-print → jangan ganggu. Cetak manual via
    // detail page tetap available.
    if (!settings.autoPrint) return;
    // Auto-print ON tapi printer belum pair: kasir tahu via toast supaya
    // tidak penasaran kenapa tidak ada bunyi printer.
    if (!settings.hasDevice) {
      toastification.show(
        type: ToastificationType.warning,
        style: ToastificationStyle.flatColored,
        title: const Text('Pesanan baru — printer belum dipasangkan'),
        description: const Text(
          'Aktifkan & pair printer Bluetooth di Profil → Pengaturan Printer.',
        ),
        autoCloseDuration: const Duration(seconds: 5),
        alignment: Alignment.bottomCenter,
      );
      return;
    }

    try {
      // Fetch detail penuh (items, totals, table) — payload FCM cuma punya
      // ringkasan. Backend `GET /transactions/:id` butuh JWT; sudah otomatis
      // dipasang dio interceptor. Pakai withMappedError supaya non-fatal.
      final sale = await ref
          .read(transactionRepositoryProvider)
          .getDetail(orderId);
      final ok = await ref.read(printerServiceProvider).printReceipt(sale);
      if (!mounted) return;
      if (ok) {
        toastification.show(
          type: ToastificationType.success,
          style: ToastificationStyle.flatColored,
          title: Text('Struk dicetak · ${sale.invoiceId}'),
          description: Text(
            '${sale.tableName ?? '-'} · ${sale.customerName.isEmpty ? "—" : sale.customerName}',
          ),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.bottomCenter,
        );
      } else {
        toastification.show(
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: const Text('Gagal cetak struk otomatis'),
          description: const Text(
            'Cek koneksi Bluetooth printer, atau cetak ulang manual dari detail transaksi.',
          ),
          autoCloseDuration: const Duration(seconds: 5),
          alignment: Alignment.bottomCenter,
        );
      }
    } catch (e) {
      // Fetch atau print exception (jaringan / Bluetooth) — kasih feedback,
      // jangan crash app. Pesanan tetap masuk di DB & inbox notif, kasir
      // bisa cetak ulang manual.
      if (!mounted) return;
      toastification.show(
        type: ToastificationType.error,
        style: ToastificationStyle.flatColored,
        title: const Text('Gagal cetak struk otomatis'),
        description: Text('$e'),
        autoCloseDuration: const Duration(seconds: 5),
        alignment: Alignment.bottomCenter,
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Auto-invalidate Riverpod providers terkait transaksi saat FCM masuk —
/// supaya halaman riwayat / detail kasir refresh tanpa pull-to-refresh
/// manual. Realtime UX: customer upload bukti → kasir di halaman detail
/// langsung lihat bukti baru, badge status berubah ke "Menunggu
/// Konfirmasi", tombol Terima/Tolak aktif.
///
/// Type yang dipantau:
///   * `new_menu_order` — pesanan baru via QR (refresh list)
///   * `proof_uploaded` — bukti pembayaran masuk / re-upload (refresh
///     list + detail spesifik)
///   * `order_updated` — pelunasan dll dari sisi server (kalau ke depan
///     ada)
class _OrderRefreshListener extends ConsumerStatefulWidget {
  final Widget child;
  const _OrderRefreshListener({required this.child});

  @override
  ConsumerState<_OrderRefreshListener> createState() =>
      _OrderRefreshListenerState();
}

class _OrderRefreshListenerState extends ConsumerState<_OrderRefreshListener> {
  StreamSubscription<RemoteMessage>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = NotificationService.instance.onForegroundMessage.listen(_onMessage);
  }

  void _onMessage(RemoteMessage message) {
    if (!mounted) return;
    final data = message.data;
    final type = (data['type'] ?? '').toString();
    if (type != 'new_menu_order' &&
        type != 'proof_uploaded' &&
        type != 'order_updated') {
      return;
    }
    // Refresh list transaksi outlet (riwayat kasir, laporan).
    ref.invalidate(salesFutureProvider);
    // Refresh detail spesifik kalau payload bawa order_id — supaya
    // halaman detail yang sedang dibuka langsung re-fetch.
    final orderId = (data['order_id'] ?? '').toString();
    if (orderId.isNotEmpty) {
      ref.invalidate(transactionDetailProvider(orderId));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
