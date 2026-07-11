import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../outlet/data/outlet_service.dart';

/// Service untuk mutasi preferensi tampilan outlet
/// (PUT /outlets/:id/display-settings). Saat ini hanya satu toggle:
/// `show_sold_count` — tampilkan badge "Terjual: N" di card produk.
class DisplaySettingsService {
  final Ref ref;
  DisplaySettingsService(this.ref);

  Future<void> save({
    required String outletId,
    required bool showSoldCount,
  }) async {
    final dio = ref.read(dioProvider);
    await dio.put(
      '/outlets/$outletId/display-settings',
      data: {'show_sold_count': showSoldCount},
    );
    // Refresh daftar outlet → activeOutletProvider ikut update sehingga
    // ProductCard di kasir page langsung re-render dengan nilai baru.
    ref.invalidate(outletsProvider);
  }
}

final displaySettingsServiceProvider = Provider<DisplaySettingsService>((ref) {
  return DisplaySettingsService(ref);
});
