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
