import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../connectivity_service.dart';
import '../outlet_scope.dart';
import 'offline_sync_service.dart';
import 'product_cache.dart';
import 'product_folder_store.dart';
import 'sale_outbox.dart';
import 'shift_outbox.dart';
import 'transaksi_folder.dart';

/// Izin penyimpanan cadangan sudah diberikan. Tidak reaktif dengan sendirinya
/// (izin diubah di layar sistem) — panggil [IzinCadanganNotifier.periksa]
/// setelah meminta izin.
class IzinCadanganNotifier extends Notifier<bool?> {
  @override
  bool? build() {
    periksa();
    return null;
  }

  Future<bool> periksa() async {
    final ok = await ref.read(productFolderStoreProvider).aktif();
    if (ref.mounted) state = ok;
    return ok;
  }
}

final izinCadanganProvider = NotifierProvider<IzinCadanganNotifier, bool?>(
  IzinCadanganNotifier.new,
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

/// Siapkan cadangan offline outlet aktif: pulihkan transaksi dari cadangan,
/// lalu tulis produk yang belum tercadangkan. Dipanggil setelah login / ganti
/// outlet dan tepat setelah izin penyimpanan diberikan.
Future<HasilPulih> siapkanCadanganOffline(
  T Function<T>(ProviderListenable<T>) baca,
) async {
  final store = baca(productFolderStoreProvider);
  if (!await store.aktif()) return const HasilPulih();
  final hasil = await pulihkanTransaksiOffline(baca);

  final outletId = baca(activeOutletIdProvider);
  if (outletId != null && outletId.isNotEmpty) {
    try {
      // Produk yang sudah ada di aplikasi tapi belum tercadangkan (mis. izin
      // baru saja diberikan). Hanya bila jumlahnya kurang, supaya tak menulis
      // ulang seluruh katalog setiap aplikasi dibuka.
      final cache = baca(productCacheProvider);
      final lokal = await cache.getAll(outletId);
      if (lokal.isNotEmpty && await store.jumlah(outletId) < lokal.length) {
        await cache.salinKeFolder(outletId);
      }
    } catch (_) {
      // Cadangan produk hanya pelengkap; jangan ganggu alur lain.
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
  void jalan() => unawaited(siapkanCadanganOffline(ref.read));
  ref.listen<String?>(activeOutletIdProvider, (_, _) => jalan());
  Future.microtask(jalan);
});
