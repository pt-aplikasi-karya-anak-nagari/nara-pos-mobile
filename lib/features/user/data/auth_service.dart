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

/// Peran yang masuk lewat Dashboard Web, bukan aplikasi kasir.
///
/// Cerminan entity.PeranDashboard di server (nara-pos-be). Server-lah yang
/// otoritatif dan menolaknya sebelum sesi terbit; pemeriksaan di klien ini
/// lapis kedua, supaya sesi tak sempat tersimpan bila backend versi lama yang
/// dihubungi.
///
/// Huruf kecil semua karena dicocokkan dengan role yang sudah di-toLowerCase.
/// 'manager' & 'coowner' ikut disebut walau perannya sudah dihapus: barisnya
/// bisa tertinggal di suatu environment akibat `migrate down` atau restore
/// snapshot, dan membiarkannya masuk persis kebalikan dari maksud menghapusnya.
const _peranDashboard = {'owner', 'superadminsystem', 'manager', 'coowner'};

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

  /// Langkah 1 registrasi: minta backend mengirim OTP ke email + WhatsApp.
  /// Return `null` bila sukses, atau pesan error dari backend (mis. email/
  /// username/phone sudah dipakai) untuk ditampilkan di form.
  Future<String?> requestRegistrationOtp({
    required String email,
    required String phone,
    required String username,
  }) async {
    try {
      await _authApi.requestRegistrationOtp(
        email: email,
        phone: phone,
        username: username,
      );
      return null;
    } catch (e) {
      return e.toString();
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
    required String emailOtp,
    required String phoneOtp,
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
        emailOtp: emailOtp,
        phoneOtp: phoneOtp,
      );

      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      final userData = data['user'] as Map<String, dynamic>?;
      final outlets = data['outlets'] as List<dynamic>?;

      if (userData == null) {
        return "Invalid response from server";
      }

      // Blokir role Owner & Manager dari aplikasi mobile (case-insensitive).
      final regRole = (userData['role'] as String?)?.trim() ?? '';
      final regRoleLower = regRole.toLowerCase();
      if (_peranDashboard.contains(regRoleLower)) {
        return 'Registrasi berhasil, namun Role "$regRole" hanya dapat login melalui Dashboard Web.';
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

  // ── Sesi staf di perangkat kasir bersama ────────────────────────────
  //
  // Pemilik/Manajer membuktikan kehadiran, memilih staf yang bertugas, lalu
  // menyetujui lewat kode email atau PIN. Sesi terbit ATAS NAMA STAF, sehingga
  // jejak transaksi & shift menunjuk orang yang benar-benar bekerja.

  /// Langkah 1. Melempar pesan error apa adanya dari server supaya alasan
  /// penolakan (kredensial salah, bukan penyelia, outlet bukan miliknya)
  /// sampai ke layar tanpa disamarkan jadi "gagal".
  Future<StaffSessionStart> startStaffSession({
    required String email,
    required String password,
    required String outletId,
    String deviceLabel = '',
  }) {
    return _authApi.startStaffSession(
      email: email.trim(),
      password: password,
      outletId: outletId,
      deviceLabel: deviceLabel,
    );
  }

  /// Langkah 1 alternatif — perangkat yang sudah disahkan melewati password
  /// pengelola. Sesi tetap hanya terbit setelah OTP/PIN di langkah 3.
  Future<StaffSessionStart> resumeStaffSession({required String deviceToken}) {
    return _authApi.resumeStaffSession(deviceToken: deviceToken);
  }

  /// Langkah 2 — kirim kode ke email pengotorisasi.
  Future<String> requestStaffSessionOtp({
    required String challengeId,
    required String staffUserId,
  }) {
    return _authApi.requestStaffSessionOtp(
      challengeId: challengeId,
      staffUserId: staffUserId,
    );
  }

  /// Langkah 3 — verifikasi kode/PIN lalu simpan sesi staf.
  /// Mengembalikan null bila berhasil, atau pesan error.
  Future<String?> verifyStaffSession({
    required String challengeId,
    required String staffUserId,
    required String code,
  }) async {
    try {
      final data = await _authApi.verifyStaffSession(
        challengeId: challengeId,
        staffUserId: staffUserId,
        code: code.trim(),
      );
      // Payload-nya sesi biasa, jadi disimpan lewat jalur yang sama —
      // termasuk blokade role-nya, yang tak akan terpicu karena yang terbit
      // adalah sesi STAF, bukan pengotorisasi.
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

      // Blokir role Owner & Manager dari aplikasi mobile — keduanya hanya boleh
      // login lewat Dashboard Web. Case-insensitive karena role dari server
      // memakai huruf kapital (mis. "Owner"/"Manager"). Backend juga menolak
      // (lewat header X-Client-Platform); cek klien ini defense-in-depth agar
      // sesi tidak sempat tersimpan bila backend versi lama.
      final roleName = (userData['role'] as String?)?.trim() ?? '';
      final roleLower = roleName.toLowerCase();
      if (_peranDashboard.contains(roleLower)) {
        return 'Role "$roleName" hanya dapat login melalui Dashboard Web.';
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
