import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';

class PosTableApiService extends BaseApiService {
  PosTableApiService(super.dio);

  Future<List<dynamic>> getPosTables(String outletId) async {
    final response = await get<List<dynamic>>(
      '/outlets/$outletId/postables',
      converter: (res) => res as List<dynamic>,
    );
    return response;
  }

  Future<dynamic> createPosTable(String outletId, Map<String, dynamic> data) async {
    final response = await post<Map<String, dynamic>>(
      '/outlets/$outletId/postables',
      data: data,
      converter: (res) => res as Map<String, dynamic>,
    );
    return response;
  }

  Future<void> updatePosTable(String id, Map<String, dynamic> data) async {
    // Tanpa explicit T & converter — backend Update mengembalikan
    // data: null. Casting null ke Map<String,dynamic> melempar error
    // walau request-nya 200 OK.
    await put('/postables/$id', data: data);
  }

  Future<void> deletePosTable(String id) async {
    // Sama seperti update: backend kembalikan data: null.
    await delete('/postables/$id');
  }

  /// Toggle status meja saja (tanpa kirim ulang field lain).
  /// Backend memvalidasi status_index harus 0..2.
  Future<void> updateStatus(String id, int statusIndex) async {
    await patch('/postables/$id/status', data: {'status_index': statusIndex});
  }
}

final posTableApiServiceProvider = Provider<PosTableApiService>((ref) {
  return PosTableApiService(ref.watch(dioProvider));
});
