import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';

class TableGroupApiService extends BaseApiService {
  TableGroupApiService(super.dio);

  Future<List<dynamic>> getTableGroups(String outletId) async {
    final response = await get<List<dynamic>>(
      '/outlets/$outletId/tablegroups',
      converter: (res) => res as List<dynamic>,
    );
    return response;
  }

  Future<dynamic> createTableGroup(String outletId, Map<String, dynamic> data) async {
    final response = await post<Map<String, dynamic>>(
      '/outlets/$outletId/tablegroups',
      data: data,
      converter: (res) => res as Map<String, dynamic>,
    );
    return response;
  }

  Future<void> updateTableGroup(String id, Map<String, dynamic> data) async {
    // Tanpa explicit T & converter — backend Update mengembalikan
    // data: null pada body. Casting null ke Map<String,dynamic> melempar
    // "type 'Null' is not a subtype of type 'Map<String, dynamic>'" walau
    // request-nya 200 OK. Pakai dynamic supaya null dilewati tanpa error.
    await put('/tablegroups/$id', data: data);
  }

  Future<void> deleteTableGroup(String id) async {
    // Sama seperti update: backend kembalikan data: null.
    await delete('/tablegroups/$id');
  }
}

final tableGroupApiServiceProvider = Provider<TableGroupApiService>((ref) {
  return TableGroupApiService(ref.watch(dioProvider));
});
