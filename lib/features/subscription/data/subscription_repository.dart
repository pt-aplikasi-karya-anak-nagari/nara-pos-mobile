import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/network/api_endpoint.dart';
import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/offline/entity_cache.dart';
import '../../../core/offline/sale_outbox.dart' show isOfflineError;
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

  /// Respons mentah — disimpan di perangkat apa adanya.
  Future<Map<String, dynamic>?> getOutletSubscriptionRaw(String outletId) {
    return get<Map<String, dynamic>?>(
      ApiEndpoint.outletSubscription(outletId),
      converter: (data) =>
          data is Map ? Map<String, dynamic>.from(data) : null,
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

/// Langganan outlet terakhir dari server, disimpan di perangkat. Tanpanya,
/// saat offline aplikasi tak tahu apa-apa soal langganan: menu paket terbuka
/// semua (fail-open) dan penjualan offline jalan terus walau langganan sudah
/// lama habis.
final _langgananCache = EntityCache<Map<String, dynamic>>(
  'langganan',
  toJson: (m) => m,
  fromJson: (m) => m,
);

/// Langganan yang tersimpan di perangkat, tanpa jaringan. Null bila belum
/// pernah tersimpan.
Future<OutletSubscription?> bacaLanggananTersimpan(String outletId) async {
  try {
    final ada = await _langgananCache.getAll(outletId);
    return ada.isEmpty ? null : OutletSubscription.fromJson(ada.first);
  } catch (_) {
    return null;
  }
}

final activeOutletSubscriptionProvider = FutureProvider<OutletSubscription?>((
  ref,
) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null || outletId.isEmpty) return null;
  try {
    final raw = await ref
        .watch(subscriptionRepositoryProvider)
        .getOutletSubscriptionRaw(outletId);
    await _langgananCache.replaceAll(outletId, raw == null ? const [] : [raw]);
    return raw == null ? null : OutletSubscription.fromJson(raw);
  } catch (e) {
    // Offline: status terakhir yang diketahui — paket & masa berlakunya tetap
    // berlaku tanpa internet.
    if (!isOfflineError(e)) rethrow;
    return bacaLanggananTersimpan(outletId);
  }
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
