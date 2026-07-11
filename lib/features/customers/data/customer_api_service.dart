import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';
import '../domain/customer.dart';

class CustomerApiService extends BaseApiService {
  CustomerApiService(super.dio);

  // Ambil semua customer untuk outlet tertentu
  Future<List<Customer>> getCustomers(String outletId) async {
    final response = await get<List<dynamic>>(
      '/outlets/$outletId/customers',
      converter: (res) => res as List<dynamic>,
    );

    return response.map((json) => Customer.fromJson(json as Map<String, dynamic>)).toList();
  }

  // Ambil 1 customer berdasarkan ID
  Future<Customer> getCustomer(String customerId) async {
    final response = await get<Map<String, dynamic>>(
      '/customers/$customerId',
      converter: (res) => res as Map<String, dynamic>,
    );
    return Customer.fromJson(response);
  }

  // Tambah customer baru ke backend
  Future<Customer> createCustomer(String outletId, Customer customer) async {
    final response = await post<Map<String, dynamic>>(
      '/outlets/$outletId/customers',
      data: customer.toJson(),
      converter: (res) => res as Map<String, dynamic>,
    );
    
    return Customer.fromJson(response);
  }

  // Update customer
  Future<Customer> updateCustomer(String customerId, Customer customer) async {
    final response = await put<Map<String, dynamic>>(
      '/customers/$customerId',
      data: customer.toJson(),
      converter: (res) => res as Map<String, dynamic>,
    );
    return Customer.fromJson(response);
  }

  // Delete customer
  Future<void> deleteCustomer(String customerId) async {
    await delete<Map<String, dynamic>>(
      '/customers/$customerId',
      converter: (res) => res as Map<String, dynamic>,
    );
  }
}

// Provider untuk API Service
final customerApiServiceProvider = Provider<CustomerApiService>((ref) {
  return CustomerApiService(ref.watch(dioProvider));
});
