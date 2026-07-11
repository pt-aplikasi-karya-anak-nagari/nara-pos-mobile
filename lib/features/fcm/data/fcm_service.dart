import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/shared_prefs.dart';

/// API wrapper untuk endpoint backend `/fcm/...`.
///
/// Backend menyimpan token per (user_id × device) supaya push bisa diarahkan
/// ke device kasir tertentu. Skema lihat migration `000052_create_fcm_tokens`.
class FcmApiService extends BaseApiService {
  FcmApiService(super.dio);

  Future<void> register({
    required String token,
    required String platform,
    String? deviceId,
    String? deviceName,
  }) async {
    await post(
      '/fcm/register',
      data: {
        'token': token,
        'platform': platform,
        'device_id': ?deviceId,
        'device_name': ?deviceName,
      },
    );
  }

  Future<void> unregister(String token) async {
    await delete('/fcm/unregister', data: {'token': token});
  }
}

final fcmApiServiceProvider = Provider<FcmApiService>((ref) {
  return FcmApiService(ref.watch(dioProvider));
});

/// Service tingkat tinggi untuk lifecycle FCM token di sisi client.
///
/// Tugas:
///  * `syncForCurrentUser()` — ambil token aktif & kirim ke backend. Dipanggil
///    setelah login sukses (di [AuthNotifier.login]) dan saat app start.
///  * `unregisterAndDispose()` — hapus token di backend lalu hapus subscription.
///    Dipanggil sebelum logout. Token sengaja TIDAK di-`deleteToken()` di
///    Firebase supaya kalau user login ulang, token-nya konsisten — kita hanya
///    putus mapping user↔token di backend.
///  * Auto-resync saat token rotate (`onTokenRefresh`).
class FcmService {
  FcmService(this._api, this._prefs);

  final FcmApiService _api;
  final SharedPreferences _prefs;

  static const _lastRegisteredKey = 'fcm.last_registered_token';

  StreamSubscription<String>? _refreshSub;

  /// Ambil token saat ini & sinkronkan ke backend kalau berbeda dari yang
  /// terakhir di-register. Idempotent — aman dipanggil berkali-kali.
  Future<String?> syncForCurrentUser() async {
    final token = await _safeGetToken();
    if (token == null || token.isEmpty) return null;
    final last = _prefs.getString(_lastRegisteredKey);
    if (last == token) {
      // Sudah tersinkron — skip request supaya tidak spam endpoint.
      return token;
    }
    try {
      await _api.register(token: token, platform: _platformLabel());
      await _prefs.setString(_lastRegisteredKey, token);
    } catch (_) {
      // Non-fatal: kasir tetap bisa pakai app. Sync akan diulang saat
      // event berikut (token refresh / re-login).
    }

    // Subscribe ke token refresh sekali saja. Kalau Firebase rotate token,
    // backend di-update otomatis tanpa user perlu re-login.
    _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      try {
        await _api.register(token: t, platform: _platformLabel());
        await _prefs.setString(_lastRegisteredKey, t);
      } catch (_) {
        // ignore; akan dicoba ulang saat next sync.
      }
    });
    return token;
  }

  /// Lepas token di backend (kalau ada cache). Dipanggil sebelum logout
  /// supaya notif tidak nyasar ke user berikutnya yang login di device sama.
  Future<void> unregisterAndDispose() async {
    final last = _prefs.getString(_lastRegisteredKey);
    if (last != null && last.isNotEmpty) {
      try {
        await _api.unregister(last);
      } catch (_) {}
    }
    await _prefs.remove(_lastRegisteredKey);
    await _refreshSub?.cancel();
    _refreshSub = null;
  }

  Future<String?> _safeGetToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  String _platformLabel() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }
}

final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService(
    ref.watch(fcmApiServiceProvider),
    ref.watch(sharedPreferencesProvider),
  );
});
