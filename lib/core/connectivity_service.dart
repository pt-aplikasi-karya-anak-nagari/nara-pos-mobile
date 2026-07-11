import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

import 'config/app_config.dart';

enum ConnectionStatus { online, unstable, offline }

final connectivityProvider = StreamProvider<ConnectionStatus>((ref) async* {
  final connectivity = Connectivity();
  // PENTING: "online" untuk app ini = BACKEND bisa dijangkau, BUKAN internet
  // publik. Default internet_connection_checker_plus nge-ping URL publik
  // (icanhazip.com, cloudflare, dll) — pada jaringan dev LAN/hotspot di mana
  // backend reachable tapi internet publik tidak, itu keliru melaporkan OFFLINE
  // → semua sale masuk antrian & auto-sync (yang menunggu status online) TAK
  // PERNAH trigger. Karena itu kita probe langsung ke backend: respons HTTP apa
  // pun (bahkan 404) = server hidup = online. Hanya gagal koneksi = offline.
  final checker = InternetConnection.createInstance(
    useDefaultOptions: false,
    customCheckOptions: [
      InternetCheckOption(
        uri: Uri.parse(AppConfig.apiHost),
        timeout: const Duration(seconds: 4),
        responseStatusFn: (_) => true,
      ),
    ],
  );

  DateTime? lastChange;
  int flipCount = 0;

  // Emit status AWAL: onConnectivityChanged (connectivity_plus 7.x) tidak
  // emit nilai saat subscribe, jadi tanpa ini value awal null → cold-start
  // keliru dianggap online & banner offline tak muncul.
  {
    final initial = await connectivity.checkConnectivity();
    if (initial.contains(ConnectivityResult.none)) {
      yield ConnectionStatus.offline;
    } else {
      final hasInternet = await checker.hasInternetAccess;
      yield hasInternet ? ConnectionStatus.online : ConnectionStatus.offline;
    }
  }

  // Listen to connectivity changes
  await for (final result in connectivity.onConnectivityChanged) {
    final now = DateTime.now();
    if (lastChange != null) {
      final diff = now.difference(lastChange);
      // If flipping faster than 2 seconds, consider unstable
      if (diff.inSeconds < 2) {
        flipCount++;
      } else {
        flipCount = 0;
      }
    }
    lastChange = now;

    if (result.contains(ConnectivityResult.none)) {
      yield ConnectionStatus.offline;
    } else {
      if (flipCount > 2) {
        yield ConnectionStatus.unstable;
      } else {
        final hasInternet = await checker.hasInternetAccess;
        yield hasInternet ? ConnectionStatus.online : ConnectionStatus.offline;
      }
    }
  }
});

/// Provider to watch if we are currently offline
final isOfflineProvider = Provider<bool>((ref) {
  final status = ref.watch(connectivityProvider).value;
  return status == ConnectionStatus.offline;
});
