import '../../../core/outlet_scope.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/offline/entity_cache.dart';
import '../../outlet/data/outlet_service.dart';
import '../domain/payment_method.dart';

/// Cache offline metode bayar per outlet. Checkout-blocking: tanpa ini hanya
/// metode virtual "Bayar Nanti" yang tersedia saat offline.
final _paymentMethodCache = EntityCache<PaymentMethod>(
  'payment_methods',
  toJson: (m) => m.toCacheJson(),
  fromJson: PaymentMethod.fromJson,
);

class PaymentMethodRepository {
  final Ref _ref;
  PaymentMethodRepository(this._ref);

  Future<List<PaymentMethod>> getAll(String outletId) async {
    return readThroughCache(
      cache: _paymentMethodCache,
      outletId: outletId,
      fetch: () async {
        final list =
            await _ref.read(outletServiceProvider).getPaymentMethods(outletId);
        return list.map((json) => PaymentMethod.fromJson(json)).toList();
      },
    );
  }

  Future<void> save(PaymentMethod method) async {
    if (method.outletRemoteId == null) throw 'Outlet ID tidak boleh kosong';
    await _ref.read(outletServiceProvider).savePaymentMethod(
          method.outletRemoteId!,
          method.toJson(),
        );
  }

  Future<void> remove(String id) async {
    await _ref.read(outletServiceProvider).deletePaymentMethod(id);
  }

  // Toggle aktif tanpa kirim full body — backend punya PATCH endpoint
  // khusus untuk operasi ini.
  Future<void> setActive(String id, bool active) async {
    await _ref.read(outletServiceProvider).setPaymentMethodActive(id, active);
  }

  // Tandai metode jadi default outlet. Backend otomatis unset semua
  // entri lain di outlet sama, jadi UI tidak perlu dua kali fetch /
  // dua kali update.
  Future<void> setDefault(String id) async {
    await _ref.read(outletServiceProvider).setPaymentMethodDefault(id);
  }
}

final paymentMethodRepositoryProvider = Provider<PaymentMethodRepository>((ref) {
  return PaymentMethodRepository(ref);
});

final paymentMethodsFutureProvider = FutureProvider<List<PaymentMethod>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return [];
  return ref.watch(paymentMethodRepositoryProvider).getAll(outletId);
});
