import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/network/api_response.dart';
import '../../../core/network/api_endpoint.dart';
import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../outlet/domain/outlet_type.dart';

class LoginOtpRequestResult {
  final int retryAfterSeconds;
  final String? message;

  const LoginOtpRequestResult({this.retryAfterSeconds = 60, this.message});

  bool get success => message == null;
}

class LoginOtpRequestException implements Exception {
  final String message;
  final int retryAfterSeconds;

  const LoginOtpRequestException(this.message, {this.retryAfterSeconds = 0});

  @override
  String toString() => message;
}

class AuthApiService extends BaseApiService {
  AuthApiService(super.dio);

  Future<List<OutletType>> getOutletTypes() async {
    return get(
      ApiEndpoint.outletTypes,
      converter: (data) {
        final List list = data;
        return list.map((e) => OutletType.fromJson(e)).toList();
      },
    );
  }

  /// Minta OTP registrasi dikirim ke [email] (via email) DAN [phone] (via
  /// WhatsApp). Dipakai pada langkah 1 form daftar sebelum submit akun.
  /// Backend menolak (409) bila email/username/phone sudah dipakai, atau
  /// (400) bila validasi gagal — pesannya di-surface lewat [post] yang
  /// melempar String message pada respons non-sukses.
  Future<void> requestRegistrationOtp({
    required String email,
    required String phone,
    required String username,
  }) async {
    await post<dynamic>(
      ApiEndpoint.registerRequestOtp,
      data: {'email': email, 'phone': phone, 'username': username},
      converter: (res) => res,
    );
  }

  Future<Map<String, dynamic>> register({
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
    return post<Map<String, dynamic>>(
      ApiEndpoint.register,
      data: {
        'username': username,
        'email': email,
        'full_name': fullName,
        'phone': phone,
        'password': password,
        'outlet_type_id': outletTypeId,
        'outlet_name': outletName,
        'outlet_address': outletAddress,
        'outlet_phone': outletPhone,
        'email_otp': emailOtp,
        'phone_otp': phoneOtp,
      },
    );
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    return post<Map<String, dynamic>>(
      ApiEndpoint.login,
      data: {'email': email, 'password': password},
    );
  }

  /// Minta link reset password dikirim ke [email]. Backend selalu
  /// merespons sukses (generic) supaya tidak membocorkan apakah email
  /// terdaftar. Token reset dikirim via link email → diselesaikan di web
  /// halaman /reset-password.
  Future<void> requestPasswordReset(String email) async {
    await post<dynamic>(
      '/password/forgot',
      data: {'email': email},
      converter: (res) => res,
    );
  }

  /// Reset password dengan [token] (dari link email) + password baru.
  /// Disediakan agar user yang menyalin token dari email bisa menyelesaikan
  /// reset langsung di aplikasi tanpa membuka web.
  Future<void> resetPassword(String token, String password) async {
    await post<dynamic>(
      '/password/reset',
      data: {'token': token, 'password': password},
      converter: (res) => res,
    );
  }

  Future<LoginOtpRequestResult> requestLoginOtp(
    String email,
    String password,
  ) async {
    try {
      final response = await dio.post(
        ApiEndpoint.loginOtpRequest,
        data: {'email': email, 'password': password},
      );
      final body = _asMap(response.data);
      final apiResponse = ApiResponse<Map<String, dynamic>>.fromJson(
        body,
        (data) => _asMap(data),
      );

      if (!apiResponse.success) {
        throw LoginOtpRequestException(
          apiResponse.message ?? 'Gagal mengirim kode OTP',
          retryAfterSeconds: _readRetryAfterSeconds(
            apiResponse.data,
            fallback: 0,
          ),
        );
      }

      return LoginOtpRequestResult(
        retryAfterSeconds: _readRetryAfterSeconds(apiResponse.data),
      );
    } on DioException catch (e) {
      final body = _asMapOrNull(e.response?.data);
      if (body != null) {
        final message = body['message']?.toString();
        final data = _asMapOrNull(body['data']);
        throw LoginOtpRequestException(
          message?.isNotEmpty == true ? message! : 'Gagal mengirim kode OTP',
          retryAfterSeconds: _readRetryAfterSeconds(data, fallback: 0),
        );
      }
      throw LoginOtpRequestException('Gagal mengirim kode OTP');
    }
  }

  Future<Map<String, dynamic>> loginWithOtp(
    String email,
    String password,
    String code,
  ) async {
    return post<Map<String, dynamic>>(
      ApiEndpoint.loginOtpVerify,
      data: {'email': email, 'password': password, 'code': code},
    );
  }

  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    return post<Map<String, dynamic>>(
      ApiEndpoint.refresh,
      data: {'refresh_token': refreshToken},
    );
  }

  Future<void> logout(String refreshToken) async {
    await dio.post(ApiEndpoint.logout, data: {'refresh_token': refreshToken});
  }

  /// Set/ubah/hapus PIN otorisasi milik user yang sedang login. [pin] berupa
  /// 4-6 digit angka; string kosong = hapus PIN. Endpoint terproteksi JWT
  /// (POST /me/pin) — interceptor Dio otomatis melampirkan Bearer token.
  Future<void> setMyPin(String pin) async {
    await post<dynamic>(
      ApiEndpoint.mePin,
      data: {'pin': pin},
      converter: (res) => res,
    );
  }

  /// Status apakah user sudah punya PIN otorisasi (GET /me/pin → {has_pin}).
  Future<bool> getMyPinStatus() async {
    final data = await get<Map<String, dynamic>>(
      ApiEndpoint.mePin,
      converter: (res) =>
          res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{},
    );
    return data['has_pin'] as bool? ?? false;
  }

  // ── Sesi staf di perangkat kasir bersama ──────────────────────────────

  /// Langkah 1: Pemilik/Manajer membuktikan kehadiran. TIDAK menerbitkan sesi
  /// untuk mereka — hanya mengembalikan daftar staf yang boleh bertugas.
  Future<StaffSessionStart> startStaffSession({
    required String email,
    required String password,
    required String outletId,
    String deviceLabel = '',
  }) async {
    final data = await post<Map<String, dynamic>>(
      ApiEndpoint.staffSessionStart,
      data: {
        'email': email,
        'password': password,
        'outlet_id': outletId,
        'device_label': deviceLabel,
      },
    );
    return _staffSessionStartFromJson(data);
  }

  /// Lanjutkan di perangkat yang sudah disahkan, tanpa password pengelola.
  ///
  /// Server menentukan outlet & pengotorisasi dari baris perangkatnya sendiri —
  /// perangkat tidak boleh menentukan siapa yang menyetujui sesinya.
  Future<StaffSessionStart> resumeStaffSession({
    required String deviceToken,
  }) async {
    final data = await post<Map<String, dynamic>>(
      ApiEndpoint.staffSessionResume,
      data: {'device_token': deviceToken},
    );
    return _staffSessionStartFromJson(data);
  }

  /// Bentuk respons start & resume identik, jadi parsernya satu — supaya
  /// penambahan field tak pernah terpasang hanya di salah satu jalur.
  StaffSessionStart _staffSessionStartFromJson(Map<String, dynamic> data) {
    final list = (data['staff'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(StaffCandidate.fromJson)
        .toList();
    final outlets = (data['outlets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(StaffOutletOption.fromJson)
        .toList();
    return StaffSessionStart(
      challengeId: data['challenge_id']?.toString() ?? '',
      authorizerName: data['authorizer_name']?.toString() ?? '',
      authorizerEmail: data['authorizer_email']?.toString() ?? '',
      outletId: data['outlet_id']?.toString() ?? '',
      outlets: outlets,
      staff: list,
      deviceToken: data['device_token']?.toString() ?? '',
    );
  }

  /// Langkah 3: [code] boleh kode email 6 digit ATAU PIN otorisasi milik
  /// pengotorisasi — server yang membedakan. Balasannya payload sesi biasa,
  /// atas nama STAF.
  Future<Map<String, dynamic>> verifyStaffSession({
    required String challengeId,
    required String staffUserId,
    required String code,
    String cardToken = '',
  }) async {
    return post<Map<String, dynamic>>(
      ApiEndpoint.staffSessionVerify,
      data: {
        'challenge_id': challengeId,
        'staff_user_id': staffUserId,
        'code': code,
        'card_token': cardToken,
      },
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  final map = _asMapOrNull(value);
  if (map == null) return <String, dynamic>{};
  return map;
}

Map<String, dynamic>? _asMapOrNull(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

int _readRetryAfterSeconds(Map<String, dynamic>? data, {int fallback = 60}) {
  final value = data?['retry_after_seconds'];
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

final authApiServiceProvider = Provider<AuthApiService>((ref) {
  return AuthApiService(ref.watch(dioProvider));
});

// ── Sesi staf di perangkat kasir bersama ────────────────────────────────

/// Satu staf yang boleh bertugas di perangkat ini.
class StaffCandidate {
  const StaffCandidate({
    required this.id,
    required this.fullName,
    required this.username,
    required this.role,
    required this.hasPin,
  });

  final String id;
  final String fullName;
  final String username;
  final String role;
  final bool hasPin;

  factory StaffCandidate.fromJson(Map<String, dynamic> j) => StaffCandidate(
    id: j['id']?.toString() ?? '',
    fullName: j['full_name']?.toString() ?? '',
    username: j['username']?.toString() ?? '',
    role: j['role']?.toString() ?? '',
    hasPin: j['has_pin'] == true,
  );
}

/// Hasil langkah 1: pengotorisasi terverifikasi + daftar staf.
class StaffOutletOption {
  const StaffOutletOption({required this.id, required this.name});
  final String id;
  final String name;

  factory StaffOutletOption.fromJson(Map<String, dynamic> j) =>
      StaffOutletOption(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
      );
}

class StaffSessionStart {
  const StaffSessionStart({
    required this.challengeId,
    required this.authorizerName,
    required this.authorizerEmail,
    required this.outletId,
    required this.outlets,
    required this.staff,
    this.deviceToken = '',
  });

  final String challengeId;
  final String authorizerName;

  /// Kosong bila pengotorisasi punya >1 outlet dan belum memilih.
  final String outletId;
  final List<StaffOutletOption> outlets;

  /// Sudah disamarkan server ("bud***@gmail.com"). Layar ini dilihat kasir,
  /// jadi alamat lengkap atasan memang tak dikirim ke perangkat.
  final String authorizerEmail;
  final List<StaffCandidate> staff;

  /// Token perangkat — HANYA terisi pada [startStaffSession] yang outletnya
  /// sudah pasti. Kosong pada resume (perangkat sudah memegang miliknya) dan
  /// saat pengelola masih harus memilih outlet.
  final String deviceToken;
}
