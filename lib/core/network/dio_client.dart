import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show Alignment, Text, TextDirection;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../auth_storage.dart';
import '../config/app_config.dart';
import '../../features/user/data/auth_service.dart';
import 'api_endpoint.dart';
import 'package:toastification/toastification.dart';

/// Host backend (tanpa trailing slash). Dipakai untuk membangun URL absolut
/// dari path relatif yang dikembalikan API (mis. `/uploads/products/abc.jpg`).
String get kApiHost => AppConfig.apiHost;

/// Konversi path relatif gambar/asset jadi URL absolut.
/// Toleran terhadap input yang sudah berupa URL absolut.
String resolveAssetUrl(String? path) {
  if (path == null || path.isEmpty) return '';
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  final host = AppConfig.apiHost;
  if (path.startsWith('/')) return '$host$path';
  return '$host/$path';
}

final dioProvider = Provider<Dio>((ref) {
  final apiSecret = AppConfig.apiSecret;
  final apiBasePath = AppConfig.apiBasePath;
  final authStorage = ref.read(authStorageProvider);
  Future<bool>? refreshInFlight;

  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = authStorage.accessToken;
        if (token != null && !_isBearerSkipped(options.path)) {
          options.headers['Authorization'] = 'Bearer $token';
        }

        _applySecurityHeaders(options, apiSecret, apiBasePath);

        return handler.next(options);
      },
      onError: (e, handler) async {
        var authToastShown = false;
        if (_shouldAttemptRefresh(e, authStorage)) {
          refreshInFlight ??= _refreshTokens(
            baseOptions: dio.options,
            authStorage: authStorage,
            apiSecret: apiSecret,
            apiBasePath: apiBasePath,
          ).whenComplete(() => refreshInFlight = null);

          final refreshed = await refreshInFlight!;
          final newAccessToken = authStorage.accessToken;
          if (refreshed && newAccessToken != null) {
            try {
              ref.read(authProvider.notifier).refresh();
              final retryResponse = await _retryRequest(
                dio,
                e.requestOptions,
                newAccessToken,
              );
              return handler.resolve(retryResponse);
            } on DioException catch (retryError) {
              e = retryError;
              if (retryError.response?.statusCode == 401) {
                await _clearAuth(ref, authStorage);
                _showErrorToast('Sesi berakhir, silakan login ulang.');
                authToastShown = true;
              }
            }
          } else {
            await _clearAuth(ref, authStorage);
            _showErrorToast('Sesi berakhir, silakan login ulang.');
            authToastShown = true;
          }
        } else if (_shouldClearAuth(e)) {
          await _clearAuth(ref, authStorage);
        }

        // Error koneksi (offline/timeout) TIDAK perlu toast: sudah ada banner
        // konektivitas global, dan checkout offline menangani sendiri
        // (di-queue + snackbar "tersimpan offline"). Toast "gagal terhubung"
        // di sini hanya membingungkan saat transaksi sebenarnya tersimpan.
        final isConnError =
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout;
        if (!authToastShown && !isConnError) {
          _showErrorToast(_errorMessage(e));
        }
        return handler.next(e);
      },
    ),
  );

  // Add logging in debug mode
  dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));

  return dio;
});

void _applySecurityHeaders(
  RequestOptions options,
  String apiSecret,
  String apiBasePath,
) {
  options.headers.addAll(
    _signatureHeaders(
      method: options.method,
      path: options.path,
      data: options.data,
      apiSecret: apiSecret,
      apiBasePath: apiBasePath,
    ),
  );
}

Map<String, String> _signatureHeaders({
  required String method,
  required String path,
  required dynamic data,
  required String apiSecret,
  required String apiBasePath,
}) {
  final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  final signedPath = _signedPath(path, apiBasePath);
  final body = _signatureBody(data);
  final message = timestamp + method.toUpperCase() + signedPath + body;
  final hmacSha256 = Hmac(sha256, utf8.encode(apiSecret));
  final signature = hmacSha256.convert(utf8.encode(message)).toString();

  return {'X-TIMESTAMP': timestamp, 'X-SIGNATURE': signature};
}

String _signatureBody(dynamic data) {
  if (data == null || data is FormData) return '';
  try {
    return jsonEncode(data);
  } catch (_) {
    return '';
  }
}

String _signedPath(String rawPath, String apiBasePath) {
  var path = rawPath;
  final uri = Uri.tryParse(rawPath);
  if (uri != null && uri.hasScheme) {
    path = uri.path;
  }
  if (!path.startsWith('/')) path = '/$path';
  if (!path.startsWith(apiBasePath)) path = apiBasePath + path;
  return path;
}

bool _isBearerSkipped(String path) {
  final normalized = _normalizedPath(path);
  return normalized == ApiEndpoint.login ||
      normalized == ApiEndpoint.loginOtpRequest ||
      normalized == ApiEndpoint.loginOtpVerify ||
      normalized == ApiEndpoint.register ||
      normalized == ApiEndpoint.refresh;
}

bool _isAuthEndpoint(String path) {
  final normalized = _normalizedPath(path);
  return normalized == ApiEndpoint.login ||
      normalized == ApiEndpoint.loginOtpRequest ||
      normalized == ApiEndpoint.loginOtpVerify ||
      normalized == ApiEndpoint.register ||
      normalized == ApiEndpoint.refresh ||
      normalized == ApiEndpoint.logout;
}

String _normalizedPath(String rawPath) {
  final uri = Uri.tryParse(rawPath);
  final path = uri != null && uri.hasScheme ? uri.path : rawPath;
  if (!path.startsWith('/')) return '/$path';
  return path;
}

bool _isUploadPath(String path) {
  return path.contains('/image') || path.contains('/upload');
}

bool _shouldAttemptRefresh(DioException e, AuthStorage authStorage) {
  if (e.response?.statusCode != 401) return false;
  if (e.requestOptions.extra['authRetry'] == true) return false;
  if (_isAuthEndpoint(e.requestOptions.path)) return false;
  if (_isUploadPath(e.requestOptions.path)) return false;
  final refreshToken = authStorage.refreshToken;
  return refreshToken != null && refreshToken.isNotEmpty;
}

bool _shouldClearAuth(DioException e) {
  if (e.response?.statusCode != 401) return false;
  if (_isUploadPath(e.requestOptions.path)) return false;
  return !_isAuthEndpoint(e.requestOptions.path);
}

Future<bool> _refreshTokens({
  required BaseOptions baseOptions,
  required AuthStorage authStorage,
  required String apiSecret,
  required String apiBasePath,
}) async {
  final refreshToken = authStorage.refreshToken;
  if (refreshToken == null || refreshToken.isEmpty) return false;

  final refreshDio = Dio(
    BaseOptions(
      baseUrl: baseOptions.baseUrl,
      connectTimeout: baseOptions.connectTimeout,
      receiveTimeout: baseOptions.receiveTimeout,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  final data = {'refresh_token': refreshToken};
  try {
    final response = await refreshDio.post<dynamic>(
      ApiEndpoint.refresh,
      data: data,
      options: Options(
        headers: _signatureHeaders(
          method: 'POST',
          path: ApiEndpoint.refresh,
          data: data,
          apiSecret: apiSecret,
          apiBasePath: apiBasePath,
        ),
      ),
    );

    final body = response.data;
    final tokenData = body is Map ? body['data'] : null;
    if (tokenData is! Map) return false;

    final accessToken = tokenData['access_token'] as String?;
    final rotatedRefreshToken = tokenData['refresh_token'] as String?;
    if (accessToken == null || rotatedRefreshToken == null) return false;

    await authStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: rotatedRefreshToken,
    );
    return true;
  } catch (_) {
    return false;
  }
}

Future<Response<dynamic>> _retryRequest(
  Dio dio,
  RequestOptions requestOptions,
  String accessToken,
) {
  final headers = Map<String, dynamic>.from(requestOptions.headers);
  headers['Authorization'] = 'Bearer $accessToken';
  headers.remove(Headers.contentLengthHeader);

  return dio.request<dynamic>(
    requestOptions.path,
    data: requestOptions.data,
    queryParameters: requestOptions.queryParameters,
    cancelToken: requestOptions.cancelToken,
    options: Options(
      method: requestOptions.method,
      headers: headers,
      responseType: requestOptions.responseType,
      contentType: requestOptions.contentType,
      followRedirects: requestOptions.followRedirects,
      receiveDataWhenStatusError: requestOptions.receiveDataWhenStatusError,
      validateStatus: requestOptions.validateStatus,
      sendTimeout: requestOptions.sendTimeout,
      receiveTimeout: requestOptions.receiveTimeout,
      extra: {...requestOptions.extra, 'authRetry': true},
    ),
    onReceiveProgress: requestOptions.onReceiveProgress,
    onSendProgress: requestOptions.onSendProgress,
  );
}

Future<void> _clearAuth(Ref ref, AuthStorage authStorage) async {
  try {
    await authStorage.clear();
    ref.invalidate(authProvider);
  } catch (_) {
    // ignore
  }
}

String _errorMessage(DioException e) {
  if (e.response?.data != null && e.response?.data is Map) {
    final data = e.response?.data as Map;
    if (data.containsKey('errors')) {
      return data['errors'].toString();
    }
    if (data.containsKey('message')) {
      return data['message'].toString();
    }
  } else if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout) {
    return 'Koneksi terputus. Silakan cek internet Anda.';
  } else if (e.type == DioExceptionType.connectionError) {
    return 'Gagal terhubung ke server.';
  }

  return 'Terjadi kesalahan sistem';
}

void _showErrorToast(String message) {
  toastification.show(
    type: ToastificationType.error,
    style: ToastificationStyle.fillColored,
    title: Text(message),
    autoCloseDuration: const Duration(seconds: 4),
    showIcon: false,
    alignment: Alignment.bottomCenter,
    direction: TextDirection.ltr,
    closeButton: ToastCloseButton(showType: CloseButtonShowType.none),
    animationDuration: const Duration(milliseconds: 300),
    showProgressBar: false,
    pauseOnHover: false,
    dragToClose: false,
  );
}
