import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/outlet_scope.dart';
import '../../outlet/data/outlet_service.dart';
import '../domain/receipt_settings.dart';

/// Repository untuk OutletReceiptSettings — wraps OutletService API
/// calls dengan domain conversion. Pattern sama dengan
/// PaymentMethodRepository.
class ReceiptSettingsRepository {
  final Ref _ref;
  ReceiptSettingsRepository(this._ref);

  Future<OutletReceiptSettings> get(String outletId) async {
    final raw = await _ref
        .read(outletServiceProvider)
        .getReceiptSettings(outletId);
    return OutletReceiptSettings.fromJson(raw);
  }

  Future<OutletReceiptSettings> save(
    String outletId,
    OutletReceiptSettings settings,
  ) async {
    final raw = await _ref
        .read(outletServiceProvider)
        .updateReceiptSettings(outletId, settings.toJson());
    return OutletReceiptSettings.fromJson(raw);
  }

  Future<void> deleteLogo(String outletId) async {
    await _ref.read(outletServiceProvider).deleteReceiptLogo(outletId);
  }
}

final receiptSettingsRepositoryProvider =
    Provider<ReceiptSettingsRepository>((ref) {
  return ReceiptSettingsRepository(ref);
});

/// Auto-fetch settings untuk outlet aktif. Kasir tinggal `ref.watch`
/// provider ini — auto-rebuild saat owner ubah dari web (kalau kita
/// invalidate setelah background refresh) atau saat outlet aktif
/// berpindah.
final receiptSettingsFutureProvider =
    FutureProvider<OutletReceiptSettings?>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return null;
  try {
    return await ref.watch(receiptSettingsRepositoryProvider).get(outletId);
  } catch (_) {
    // Fallback ke default supaya printer tetap bisa cetak walaupun
    // backend unreachable.
    return OutletReceiptSettings.defaults(outletId);
  }
});
