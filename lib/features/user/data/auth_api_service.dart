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
