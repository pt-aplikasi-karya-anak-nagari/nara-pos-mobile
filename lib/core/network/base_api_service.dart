import 'package:dio/dio.dart';
import 'api_response.dart';

abstract class BaseApiService {
  final Dio dio;

  BaseApiService(this.dio);

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? converter,
  }) async {
    return _request(
      () => dio.get(path, queryParameters: queryParameters),
      converter: converter,
    );
  }

  Future<T> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? converter,
  }) async {
    return _request(
      () => dio.post(path, data: data, queryParameters: queryParameters),
      converter: converter,
    );
  }

  Future<T> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? converter,
  }) async {
    return _request(
      () => dio.put(path, data: data, queryParameters: queryParameters),
      converter: converter,
    );
  }

  Future<T> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? converter,
  }) async {
    return _request(
      () => dio.delete(path, data: data, queryParameters: queryParameters),
      converter: converter,
    );
  }

  /// HTTP PATCH — untuk endpoint partial update (mis. ubah satu field saja
  /// tanpa kirim ulang seluruh resource). Bedanya dengan PUT: PUT idiomatik
  /// "replace seluruh resource", PATCH "ubah sebagian".
  Future<T> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? converter,
  }) async {
    return _request(
      () => dio.patch(path, data: data, queryParameters: queryParameters),
      converter: converter,
    );
  }

  /// Versi GET yang ikut mengembalikan metadata pagination (page, limit, total).
  /// Pakai ini bila UI butuh tahu total halaman / infinite scroll. Kalau hanya
  /// butuh data list, [get] sudah otomatis unwrap `data.items`.
  Future<Paginated<T>> getPaginated<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(dynamic) itemConverter,
  }) async {
    try {
      final response = await dio.get(path, queryParameters: queryParameters);
      final apiResponse = ApiResponse<List<T>>.fromJson(
        response.data,
        (raw) => (raw as List).map(itemConverter).toList(),
      );

      if (!apiResponse.success) {
        throw apiResponse.message ?? 'Terjadi kesalahan pada server';
      }

      return Paginated<T>(
        items: apiResponse.data ?? <T>[],
        pagination: apiResponse.pagination,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw e.toString();
    }
  }

  Future<T> _request<T>(
    Future<Response> Function() call, {
    T Function(dynamic)? converter,
  }) async {
    try {
      final response = await call();
      final apiResponse = ApiResponse.fromJson(response.data, converter);

      if (apiResponse.success) {
        if (T == Null) return null as T;
        return apiResponse.data as T;
      } else {
        throw apiResponse.message ?? 'Terjadi kesalahan pada server';
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw e.toString();
    }
  }

  String _handleDioError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final message = data['message'];
      if (message != null && message.toString().isNotEmpty) {
        return message.toString();
      }
      // Backend validator mengirim { success: false, errors: [...] }.
      // Tampilkan supaya user tahu field mana yang gagal validasi.
      final errors = data['errors'];
      if (errors is List && errors.isNotEmpty) {
        return errors.map((e) => e.toString()).join(', ');
      }
      if (errors is Map && errors.isNotEmpty) {
        return errors.entries.map((e) => '${e.key}: ${e.value}').join(', ');
      }
      if (errors is String && errors.isNotEmpty) {
        return errors;
      }
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Koneksi timeout, silakan coba lagi';
      case DioExceptionType.connectionError:
        return 'Tidak ada koneksi internet';
      default:
        return 'Gagal terhubung ke server (${e.response?.statusCode ?? "unknown"})';
    }
  }
}
