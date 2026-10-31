import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/outlet_scope.dart';
import '../../../core/realtime/realtime_service.dart';
import '../domain/antrian.dart';

/// API antrian (backend internal/antrian).
class AntrianService extends BaseApiService {
  AntrianService(super.dio);

  Future<RingkasanAntrian> ringkasan(String outletId) => get(
    '/outlets/$outletId/antrian',
    converter: (d) => d is Map
        ? RingkasanAntrian.fromJson(Map<String, dynamic>.from(d))
        : const RingkasanAntrian(),
  );

  /// Panggil nomor menunggu paling awal. Melempar bila antrian kosong.
  Future<ItemAntrian> panggilBerikutnya(String outletId) => post(
    '/outlets/$outletId/antrian/panggil-berikutnya',
    converter: (d) => ItemAntrian.fromJson(Map<String, dynamic>.from(d as Map)),
  );

  /// Panggil nomor tertentu (juga untuk panggil ulang).
  Future<ItemAntrian> panggil(String outletId, String transaksiId) => post(
    '/outlets/$outletId/antrian/$transaksiId/panggil',
    converter: (d) => ItemAntrian.fromJson(Map<String, dynamic>.from(d as Map)),
  );
}

final antrianServiceProvider = Provider<AntrianService>(
  (ref) => AntrianService(ref.watch(dioProvider)),
);

/// Event realtime yang mengubah antrian: nomor dipanggil, transaksi baru,
/// pesanan QR dikonfirmasi/dibatalkan.
bool mengubahAntrian(String tipe) =>
    tipe == 'queue.called' ||
    tipe == 'transaction.created' ||
    tipe == 'transaction.voided' ||
    tipe == 'transaction.refunded' ||
    tipe == 'order.confirmed' ||
    tipe == 'order.paid' ||
    tipe == 'order.cancelled';

/// Ringkasan antrian outlet aktif hari ini. Dimuat ulang otomatis saat ada
/// event realtime yang mengubah antrian (dari tablet ini atau perangkat lain).
final ringkasanAntrianProvider = FutureProvider.autoDispose<RingkasanAntrian>((
  ref,
) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null || outletId.isEmpty) return const RingkasanAntrian();
  ref.listen(realtimeEventsProvider, (_, next) {
    final ev = next.value;
    if (ev != null && mengubahAntrian(ev.type)) ref.invalidateSelf();
  });
  return ref.read(antrianServiceProvider).ringkasan(outletId);
});
