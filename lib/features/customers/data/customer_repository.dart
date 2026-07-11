import '../../../core/outlet_scope.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/offline/entity_cache.dart';
import '../domain/customer.dart';
import 'customer_api_service.dart';

/// Cache offline daftar customer per outlet (loyalty selector kasir).
final _customerCache = EntityCache<Customer>(
  'customers',
  toJson: (c) => c.toJson(),
  fromJson: Customer.fromJson,
);

class CustomerRepository {
  final CustomerApiService apiService;

  CustomerRepository(this.apiService);

  Future<List<Customer>> getAll(String outletId) async {
    return readThroughCache(
      cache: _customerCache,
      outletId: outletId,
      fetch: () async {
        try {
          return await apiService.getCustomers(outletId);
        } catch (e) {
          if (e.toString().contains('relation') &&
              e.toString().contains('exist')) {
            return <Customer>[];
          }
          rethrow;
        }
      },
    );
  }

  /// Ambil 1 customer dari backend.
  Future<Customer> getDetail(String id) async {
    return apiService.getCustomer(id);
  }

  /// Sinkron lookup dari cache list (`customersFutureProvider`).
  /// Berguna saat halaman edit hanya butuh data yang sudah ada di list.
  /// Mengembalikan null kalau belum ada di cache.
  Customer? getById(String id) => null;

  Future<Customer> save(Customer customer, {String? outletId}) async {
    if (customer.id.isNotEmpty) {
      return apiService.updateCustomer(customer.id, customer);
    }
    // Tanpa outletId, URL POST akan jadi /outlets//customers yang ditolak
    // backend dan dapat memicu interceptor 401 → logout. Fail fast di sini.
    if (outletId == null || outletId.isEmpty) {
      throw 'Outlet aktif belum dipilih';
    }
    return apiService.createCustomer(outletId, customer);
  }

  Future<void> remove(String customerId) async {
    await apiService.deleteCustomer(customerId);
  }
}

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(ref.watch(customerApiServiceProvider));
});

final customersFutureProvider = FutureProvider<List<Customer>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return [];
  return ref.watch(customerRepositoryProvider).getAll(outletId);
});

/// Detail satu customer dari backend. Auto-refetch saat di-invalidate
/// (mis. setelah update).
final customerDetailProvider =
    FutureProvider.family<Customer, String>((ref, id) async {
  return ref.watch(customerRepositoryProvider).getDetail(id);
});
