import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/auth_storage.dart';
import 'auth_api_service.dart';
import '../domain/user.dart';
import '../../fcm/data/fcm_service.dart';
import '../../outlet/domain/outlet_type.dart';

class AuthState {
  final User? user;
  final String? token;
  const AuthState({this.user, this.token});

  bool get isAuthenticated => user != null && token != null;
}

class AuthNotifier extends Notifier<AuthState> {
  late AuthStorage _authStorage;
  late AuthApiService _authApi;

  @override
  AuthState build() {
    _authStorage = ref.read(authStorageProvider);
    _authApi = ref.read(authApiServiceProvider);

    final token = _authStorage.accessToken;
    final userJson = _authStorage.userData;

    if (token == null || userJson == null) return const AuthState();

    try {
      final user = User.fromJson(jsonDecode(userJson));
      // Auto-sync FCM token saat app start dengan sesi yang masih valid —
      // misal user kemarin login terus app di-killed. Token mungkin sudah
      // rotate (Firebase otomatis rotate ~6 bulan sekali) atau user reinstall
      // app tapi server masih punya token lama.
      _syncFcmAfterAuth();
      return AuthState(user: user, token: token);
    } catch (_) {
      return const AuthState();
    }
  }

  Future<List<OutletType>> getOutletTypes() async {
    try {
      return await _authApi.getOutletTypes();
    } catch (e) {
      return [];
    }
  }

  Future<String?> register({
    required String username,
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required int outletTypeId,
    required String outletName,
    required String outletAddress,
    required String outletPhone,
  }) async {
    try {
      final data = await _authApi.register(
        username: username,
        fullName: fullName,
        email: email,
        phone: phone,
        password: password,
        outletTypeId: outletTypeId,
        outletName: outletName,
        outletAddress: outletAddress,
        outletPhone: outletPhone,
      );

      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      final userData = data['user'] as Map<String, dynamic>?;
      final outlets = data['outlets'] as List<dynamic>?;

      if (userData == null) {
        return "Invalid response from server";
      }

      // Blokir role 'owner' dari aplikasi mobile
      if (userData['role'] == 'owner') {
        return 'Registrasi berhasil, namun Role "Owner" hanya dapat login melalui Dashboard Admin Web.';
      }

      if (accessToken == null || refreshToken == null) {
        return "Invalid response from server";
      }

      final user = User.fromJson(userData, outlets: outlets);

      await _authStorage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      await _authStorage.saveUserData(jsonEncode(user.toJson()));
      state = AuthState(user: user, token: accessToken);
      _syncFcmAfterAuth();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> login(String email, String password) async {
    try {
      final data = await _authApi.login(email, password);

      return await _storeLoginPayload(data);
    } catch (e) {
      return e.toString();
    }
  }

  Future<LoginOtpRequestResult> requestLoginOtp(
    String email,
    String password,
  ) async {
    try {
      return await _authApi.requestLoginOtp(email.trim(), password);
    } catch (e) {
      if (e is LoginOtpRequestException) {
        return LoginOtpRequestResult(
          message: e.message,
          retryAfterSeconds: e.retryAfterSeconds,
        );
      }
      return LoginOtpRequestResult(message: e.toString());
    }
  }

  Future<String?> loginWithOtp(
    String email,
    String password,
    String code,
  ) async {
    try {
      final data = await _authApi.loginWithOtp(
        email.trim(),
        password,
        code.trim(),
      );
      return await _storeLoginPayload(data);
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> _storeLoginPayload(Map<String, dynamic> data) async {
    try {
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      final userData = data['user'] as Map<String, dynamic>?;
      final outlets = data['outlets'] as List<dynamic>?;

      if (accessToken == null || refreshToken == null || userData == null) {
        return "Invalid response from server";
      }

      final user = User.fromJson(userData, outlets: outlets);

      // Blokir role 'owner' dari aplikasi mobile sesuai permintaan
      if (userData['role'] == 'owner') {
        return 'Role "Owner" hanya dapat login melalui Dashboard Admin Web.';
      }

      await _authStorage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      await _authStorage.saveUserData(jsonEncode(user.toJson()));

      state = AuthState(user: user, token: accessToken);

      // Sync FCM token ke backend setelah session aktif. Fire-and-forget —
      // jangan blokir UI login kalau request lambat / gagal.
      // Token re-sync otomatis di-handle FcmService.syncForCurrentUser().
      _syncFcmAfterAuth();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> logout() async {
    // Lepas FCM mapping di backend DULU (selama token Bearer masih aktif).
    // Kalau dijalankan setelah token di-clear, request unregister-nya akan
    // tertolak 401 dan token tetap aktif di backend → notif user lama
    // bocor ke user baru yang nanti login di device ini.
    try {
      await ref.read(fcmServiceProvider).unregisterAndDispose();
    } catch (_) {
      // ignore — penghapusan local tetap jalan supaya logout berhasil
      // walau backend tidak reachable.
    }

    final refreshToken = _authStorage.refreshToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _authApi.logout(refreshToken);
      } catch (_) {
        // ignore — local logout tetap harus berhasil.
      }
    }

    await _authStorage.clear();
    state = const AuthState();
  }

  void _syncFcmAfterAuth() {
    Future.microtask(() async {
      try {
        await ref.read(fcmServiceProvider).syncForCurrentUser();
      } catch (_) {
        // ignore — non-fatal
      }
    });
  }

  void refresh() {
    final token = _authStorage.accessToken;
    final userJson = _authStorage.userData;
    if (token == null || userJson == null) {
      state = const AuthState();
      return;
    }
    try {
      state = AuthState(
        user: User.fromJson(jsonDecode(userJson)),
        token: token,
      );
    } catch (_) {
      state = const AuthState();
    }
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
