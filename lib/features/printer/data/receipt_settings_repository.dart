import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/offline/entity_cache.dart';

import '../../../core/outlet_scope.dart';
import '../../outlet/data/outlet_service.dart';
import '../domain/receipt_settings.dart';
import 'logo_struk.dart';

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

/// Pengaturan struk mentah dari server, disimpan di perangkat supaya struk
/// yang dicetak saat offline tetap memakai branding outlet (nama usaha,
/// logo, footer) — bukan default kosong.
final _receiptSettingsCache = EntityCache<Map<String, dynamic>>(
  'receipt_settings',
  toJson: (m) => m,
  fromJson: (m) => m,
);

/// Auto-fetch settings untuk outlet aktif. Kasir tinggal `ref.watch`
/// provider ini — auto-rebuild saat owner ubah dari web (kalau kita
/// invalidate setelah background refresh) atau saat outlet aktif
/// berpindah.
///
/// Offline → pengaturan terakhir yang tersimpan di perangkat; belum pernah
/// tersimpan → default, supaya printer tetap bisa mencetak.
final receiptSettingsFutureProvider =
    FutureProvider<OutletReceiptSettings?>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return null;
  final outletService = ref.watch(outletServiceProvider);
  Map<String, dynamic>? raw;
  try {
    raw = await readThroughCacheOne<Map<String, dynamic>>(
      cache: _receiptSettingsCache,
      outletId: outletId,
      fetch: () => outletService.getReceiptSettings(outletId),
    );
  } catch (_) {
    try {
      final ada = await _receiptSettingsCache.getAll(outletId);
      raw = ada.isEmpty ? null : ada.first;
    } catch (_) {}
  }
  if (raw == null) return OutletReceiptSettings.defaults(outletId);
  final rs = OutletReceiptSettings.fromJson(raw);
  // Unduh logo selagi online, supaya struk pertama saat offline sudah
  // berlogo. Gagal = tak apa; dicoba lagi saat mencetak.
  unawaited(
    ref
        .read(logoStrukStoreProvider)
        .ambil(outletId, rs.headerShowLogo ? rs.headerLogoUrl : '')
        .then((_) {}, onError: (_) {}),
  );
  return rs;
});
