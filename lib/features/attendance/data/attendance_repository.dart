import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/image_compress.dart';

import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/outlet_scope.dart';
import '../domain/attendance.dart';

class AttendanceApiService extends BaseApiService {
  AttendanceApiService(super.dio);

  Future<Map<String, dynamic>?> checkIn(Map<String, dynamic> data) async {
    return await post(
      '/attendances/check-in',
      data: data,
      converter: (raw) => raw is Map<String, dynamic> ? raw : null,
    );
  }

  Future<void> checkOut(String id, Map<String, dynamic> data) async {
    await post('/attendances/$id/check-out', data: data);
  }

  Future<Map<String, dynamic>?> getActive() async {
    return await get(
      '/attendances/active',
      converter: (raw) => raw is Map<String, dynamic> ? raw : null,
    );
  }

  Future<List<dynamic>> getMyHistory({int page = 1, int limit = 30}) async {
    return await get<List<dynamic>>(
      '/attendances/me',
      queryParameters: {'page': page, 'limit': limit},
      converter: (res) => res as List<dynamic>,
    );
  }

  /// Upload foto absensi via multipart. Endpoint backend tidak menerima
  /// field lain — hanya `image`. Mengembalikan URL relatif (mis.
  /// `/uploads/attendances/xyz.jpg`).
  ///
  /// Kompres dulu (JPEG q=50, max 1600 px) supaya upload cepat & storage
  /// server hemat — foto absensi tidak perlu resolusi full kamera.
  Future<String> uploadPhoto(String filePath) async {
    final compressedPath = await ImageCompress.compressFile(filePath);
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        compressedPath,
        filename: compressedPath.split('/').last,
      ),
    });
    final res = await dio.post<Map<String, dynamic>>(
      '/attendances/photo',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        responseType: ResponseType.json,
      ),
    );
    final body = res.data;
    if (body == null) return '';
    final data = body['data'];
    return (data is Map ? data['photo_url']?.toString() : null) ?? '';
  }
}

final attendanceApiServiceProvider = Provider<AttendanceApiService>((ref) {
  return AttendanceApiService(ref.watch(dioProvider));
});

class AttendanceRepository {
  final AttendanceApiService api;
  AttendanceRepository(this.api);

  Future<Attendance> checkIn({
    required String outletId,
    String? photoUrl,
    String? notes,
  }) async {
    final res = await api.checkIn({
      'outlet_id': outletId,
      'photo_url': photoUrl ?? '',
      'notes': notes ?? '',
    });
    if (res == null) throw 'Response check-in kosong';
    return Attendance.fromJson(res);
  }

  Future<void> checkOut(
    String id, {
    String? photoUrl,
    String? notes,
  }) async {
    await api.checkOut(id, {
      'photo_url': photoUrl ?? '',
      'notes': notes ?? '',
    });
  }

  Future<Attendance?> getActive() async {
    final res = await api.getActive();
    if (res == null) return null;
    return Attendance.fromJson(res);
  }

  Future<List<Attendance>> getMyHistory() async {
    final list = await api.getMyHistory();
    return list
        .map((e) => Attendance.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> uploadPhoto(String filePath) => api.uploadPhoto(filePath);
}

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(ref.watch(attendanceApiServiceProvider));
});

/// Sesi absensi aktif user (null kalau belum check-in atau sudah
/// check-out). Auto-refetch saat di-invalidate (mis. setelah check-in /
/// check-out berhasil).
final activeAttendanceProvider = FutureProvider<Attendance?>((ref) async {
  // Hanya fetch kalau user sudah login (token & outlet ada). Tanpa ini,
  // hit endpoint sebelum login akan return 401 yang ke-cache sebagai
  // error.
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return null;
  return ref.watch(attendanceRepositoryProvider).getActive();
});

/// Riwayat absensi user yang sedang login.
final myAttendanceHistoryProvider =
    FutureProvider<List<Attendance>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return const [];
  return ref.watch(attendanceRepositoryProvider).getMyHistory();
});
