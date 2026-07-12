import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/network/api_endpoint.dart';
import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/outlet_scope.dart';
import '../domain/subscription.dart';

class SubscriptionRepository extends BaseApiService {
  SubscriptionRepository(super.dio);

  Future<List<SubscriptionPlan>> getPlans() {
    return get(
      ApiEndpoint.subscriptionPlans,
      converter: (data) {
        final list = data as List<dynamic>? ?? const [];
        return list
            .map(
              (json) => SubscriptionPlan.fromJson(json as Map<String, dynamic>),
            )
            .toList();
      },
    );
  }

  Future<OutletSubscription?> getOutletSubscription(String outletId) {
    return get<OutletSubscription?>(
      ApiEndpoint.outletSubscription(outletId),
      converter: (data) {
        if (data == null) return null;
        return OutletSubscription.fromJson(data as Map<String, dynamic>);
      },
    );
  }
}

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return SubscriptionRepository(ref.watch(dioProvider));
});

final activeOutletSubscriptionProvider = FutureProvider<OutletSubscription?>((
  ref,
) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null || outletId.isEmpty) return null;
  return ref
      .watch(subscriptionRepositoryProvider)
      .getOutletSubscription(outletId);
});

final subscriptionPlansProvider = FutureProvider<List<SubscriptionPlan>>((
  ref,
) async {
  return ref.watch(subscriptionRepositoryProvider).getPlans();
});

/// Set key fitur katalog yang termasuk dalam plan langganan outlet aktif.
///
/// Kosong bila langganan belum termuat / sedang loading / error / outlet
/// belum punya langganan → caller melakukan fail-open (anggap semua fitur ada).
final outletFeatureKeysProvider = Provider<Set<String>>((ref) {
  final async = ref.watch(activeOutletSubscriptionProvider);
  return async.maybeWhen(
    data: (sub) => sub?.featureKeys.toSet() ?? const <String>{},
    orElse: () => const <String>{},
  );
});

/// Extension untuk gating fitur berbasis PLAN langganan outlet aktif.
///
/// Penggunaan:
/// ```dart
/// if (ref.hasFeature('modifiers')) { ... }
/// ```
///
/// FAIL-OPEN: bila daftar fitur belum termuat / kosong (mis. sedang loading,
/// error/offline, atau outlet belum punya langganan), SEMUA fitur dianggap
/// tersedia — agar tidak ada menu yang hilang saat load dan outlet tanpa data
/// langganan tetap bisa mencapai billing/langganan.
///
/// Gating ini bersifat TAMBAHAN terhadap role/permission: sebuah menu tampil
/// hanya bila role mengizinkan DAN plan menyertakan fiturnya.
extension FeatureCheckRef on WidgetRef {
  bool hasFeature(String key) {
    final keys = watch(outletFeatureKeysProvider);
    if (keys.isEmpty) return true; // fail-open
    return keys.contains(key);
  }
}
