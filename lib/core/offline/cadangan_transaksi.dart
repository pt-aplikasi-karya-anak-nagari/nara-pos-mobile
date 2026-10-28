import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../connectivity_service.dart';
import '../outlet_scope.dart';
import 'offline_sync_service.dart';
import 'product_folder_store.dart';
import 'sale_outbox.dart';
import 'shift_outbox.dart';
import 'transaksi_folder.dart';

/// Folder cadangan sudah dipilih dan izinnya masih ada.
final folderCadanganAktifProvider = FutureProvider<bool>(
  (ref) => ref.watch(productFolderStoreProvider).aktif(),
);

/// Pulihkan transaksi offline outlet aktif dari folder cadangan ke antrian,
/// segarkan hitungannya, lalu kirim bila sedang online.
///
/// Aman dipanggil berulang: transaksi yang sudah ada di antrian dilewati, dan
/// transaksi yang ternyata sudah sampai di server dikenali lewat client_ref.
Future<HasilPulih> pulihkanTransaksiOffline(
  T Function<T>(ProviderListenable<T>) baca,
) async {
  final outletId = baca(activeOutletIdProvider);
  if (outletId == null || outletId.isEmpty) return const HasilPulih();
  final hasil = await baca(cerminTransaksiProvider).pulihkan(outletId);
  if (hasil.total > 0) {
    await baca(pendingSyncCountProvider.notifier).refresh();
    await baca(deadLetterCountProvider.notifier).refresh();
    await baca(pendingShiftSyncCountProvider.notifier).refresh();
    await baca(shiftDeadLetterCountProvider.notifier).refresh();
    if (!baca(isOfflineProvider)) {
      unawaited(baca(offlineSyncServiceProvider).sync());
    }
  }
  return hasil;
}

/// Pemulihan otomatis setiap outlet aktif diketahui (mis. tepat setelah
/// login). Di-watch sekali di shell aplikasi.
///
/// Pemulihan juga MEMBUKA KUNCI penghapusan file outlet itu: sebelum dipulihkan,
/// cermin hanya menulis, tak pernah menghapus (lihat CerminTransaksiOffline).
final cadanganTransaksiOtomatisProvider = Provider<void>((ref) {
  void jalan() => unawaited(pulihkanTransaksiOffline(ref.read));
  ref.listen<String?>(activeOutletIdProvider, (_, _) => jalan());
  Future.microtask(jalan);
});
