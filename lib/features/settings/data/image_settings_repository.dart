import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/outlet_scope.dart';
import '../../outlet/data/outlet_service.dart';
import '../domain/image_settings.dart';

/// Repository untuk OutletImageSettings — wraps OutletService dengan
/// domain conversion. Pattern sama dengan ReceiptSettingsRepository.
class ImageSettingsRepository {
  final Ref _ref;
  ImageSettingsRepository(this._ref);

  Future<OutletImageSettings> get(String outletId) async {
    final raw = await _ref
        .read(outletServiceProvider)
        .getImageSettings(outletId);
    return OutletImageSettings.fromJson(raw);
  }

  Future<OutletImageSettings> save(
    String outletId,
    OutletImageSettings settings,
  ) async {
    final raw = await _ref
        .read(outletServiceProvider)
        .updateImageSettings(outletId, settings.toJson());
    return OutletImageSettings.fromJson(raw);
  }
}

final imageSettingsRepositoryProvider =
    Provider<ImageSettingsRepository>((ref) {
  return ImageSettingsRepository(ref);
});

/// Auto-fetch settings untuk outlet aktif. Kasir tinggal `ref.watch`
/// provider ini sebelum upload (mis. set ImagePicker.imageQuality)
/// supaya gambar yang dikirim ke backend sudah pre-compressed.
final imageSettingsFutureProvider =
    FutureProvider<OutletImageSettings?>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return null;
  try {
    return await ref.watch(imageSettingsRepositoryProvider).get(outletId);
  } catch (_) {
    return OutletImageSettings.defaults(outletId);
  }
});
