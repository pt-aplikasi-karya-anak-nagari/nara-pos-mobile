import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';

class OrderTypeApiService extends BaseApiService {
  OrderTypeApiService(super.dio);

  Future<List<dynamic>> getOrderTypes(String outletId) async {
    final response = await get<List<dynamic>>(
      '/outlets/$outletId/ordertypes',
      converter: (data) {
        if (data is Map && data.containsKey('items')) {
          return data['items'] as List<dynamic>;
        }
        return data as List<dynamic>;
      },
    );
    return response;
  }

  Future<dynamic> createOrderType(String outletId, Map<String, dynamic> data) async {
    final response = await post<Map<String, dynamic>>(
      '/outlets/$outletId/ordertypes',
      data: data,
      converter: (res) => res as Map<String, dynamic>,
    );
    return response;
  }

  Future<void> updateOrderType(String id, Map<String, dynamic> data) async {
    await put<dynamic>(
      '/ordertypes/$id',
      data: data,
    );
  }

  Future<void> deleteOrderType(String id) async {
    await delete<dynamic>(
      '/ordertypes/$id',
    );
  }
}

final orderTypeApiServiceProvider = Provider<OrderTypeApiService>((ref) {
  return OrderTypeApiService(ref.watch(dioProvider));
});
