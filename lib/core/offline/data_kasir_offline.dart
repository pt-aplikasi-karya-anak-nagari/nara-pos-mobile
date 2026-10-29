import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/discounts/data/promo_repository.dart';
import '../../features/order_types/data/order_type_repository.dart';
import '../../features/order_types/domain/order_type.dart';
import '../../features/payments/data/payment_method_repository.dart';
import '../../features/products/data/modifier_repository.dart';
import '../../features/settings/data/app_settings.dart';
import '../../features/printer/data/receipt_settings_repository.dart';
import '../../features/payments/domain/payment_method.dart';
import '../../features/subscription/data/subscription_repository.dart';
import '../../features/tables/data/table_repository.dart';
import '../../features/transactions/data/transaction_repository.dart';
import '../../features/user/data/auth_service.dart';
import '../connectivity_service.dart';
import '../outlet_scope.dart';
import 'product_cache.dart';

// Data yang WAJIB ada supaya kasir bisa menyelesaikan transaksi saat offline:
// metode bayar dan tipe pesanan (tombol "Konfirmasi Pembayaran" mensyaratkan
// keduanya), meja untuk pesanan Dine In, dan add-on (ukuran, topping) seluruh
// produk.
//
// # MASALAH YANG DISELESAIKAN
//
// Ketiganya punya cache offline, tapi cache itu baru terisi saat layarnya
// DIBUKA sambil online. Tablet yang baru di-install lalu kehilangan internet
// sebelum kasir sempat membuka layar bayar tak punya salinan apa pun: daftar
// metode bayar kosong (hanya "Bayar Nanti"), tipe pesanan kosong, dan tombol
// konfirmasi tak pernah aktif — transaksi offline mustahil.
//
// Dua lapis perbaikan:
//   1. [dataKasirOfflineProvider] mengunduh ketiganya begitu online (login,
//      ganti outlet, koneksi kembali, dan berkala), tanpa menunggu layarnya
//      dibuka.
//   2. Bila tetap tak ada salinan (mis. belum pernah online sejak install),
//      [metodeBayarKasirProvider] dan [tipePesananKasirProvider] memberi
//      pilihan bawaan: Tunai, serta Take Away / Dine In. Server menerima
//      keduanya — "Tunai" dikenali sebagai tunai, dan tipe pesanan berupa
//      teks bebas — jadi transaksinya tetap tersinkron dengan benar.

/// Metode bayar bawaan saat tak ada salinan dan perangkat offline.
List<PaymentMethod> metodeBayarCadangan() => [
  PaymentMethod(name: 'Tunai', type: 'cash', code: 'CASH', isActive: true),
];

/// Tipe pesanan bawaan saat tak ada salinan. Take Away menjadi bawaan karena
/// Dine In mensyaratkan memilih meja, dan daftar meja pun bisa belum tersimpan.
List<OrderType> tipePesananCadangan() => [
  OrderType(
    name: 'Take Away',
    isDefault: true,
    iconName: 'shopping_bag',
    isSystem: true,
  ),
  OrderType(name: 'Dine In', iconName: 'restaurant', isSystem: true),
];

/// Metode bayar aktif untuk layar bayar kasir. Saat offline tanpa salinan
/// (atau server gagal menjawab), jatuh ke [metodeBayarCadangan].
///
/// Tidak dipakai halaman kelola metode bayar: di sana pilihan bawaan ini akan
/// tampak seperti data sungguhan.
final metodeBayarKasirProvider = Provider<List<PaymentMethod>>((ref) {
  final async = ref.watch(paymentMethodsFutureProvider);
  final aktif = (async.value ?? const <PaymentMethod>[])
      .where((m) => m.isActive)
      .toList();
  if (aktif.isNotEmpty) return aktif;
  if (async.isLoading && !async.hasError) return const [];
  // Online dengan nol metode aktif = keputusan pemilik; jangan ditimpa.
  if (async.hasError || ref.watch(isOfflineProvider)) {
    return metodeBayarCadangan();
  }
  return const [];
});

/// Tipe pesanan untuk kasir, dengan [tipePesananCadangan] bila tak ada data
/// sama sekali (tipe Dine In & Take Away bawaan sistem tak bisa dihapus,
/// jadi daftar kosong selalu berarti datanya tak tersedia).
final tipePesananKasirProvider = Provider<List<OrderType>>((ref) {
  final async = ref.watch(orderTypesFutureProvider);
  final daftar = async.value ?? const <OrderType>[];
  if (daftar.isNotEmpty) return daftar;
  if (async.isLoading && !async.hasError) return const [];
  return tipePesananCadangan();
});

/// Mengunduh data wajib-transaksi ke cache offline begitu online. Di-watch
/// sekali di shell aplikasi.
final dataKasirOfflineProvider = Provider<void>((ref) {
  var berjalan = false;

  Future<void> siapkan() async {
    if (berjalan) return;
    if (ref.read(authProvider).user == null) return;
    final outletId = ref.read(activeOutletIdProvider);
    if (outletId == null || outletId.isEmpty) return;
    if (ref.read(isOfflineProvider)) return;

    berjalan = true;
    try {
      // getAll/getTables/getGroups menulis ke cache offline saat berhasil.
      // Masing-masing berdiri sendiri: satu gagal tak menghalangi yang lain.
      Future<bool> coba(Future<Object?> Function() f) async {
        try {
          await f();
          return true;
        } catch (_) {
          return false;
        }
      }

      final hasil = await Future.wait([
        coba(() => ref.read(paymentMethodRepositoryProvider).getAll(outletId)),
        coba(() => ref.read(orderTypeRepositoryProvider).getAll(outletId)),
        coba(() => ref.read(tableRepositoryProvider).getTables(outletId)),
        coba(() => ref.read(tableRepositoryProvider).getGroups(outletId)),
        // Batas diskon kasir — diperiksa di perangkat saat berjualan offline.
        coba(() async {
          ref.invalidate(outletAppSettingsProvider);
          return ref.read(outletAppSettingsProvider.future);
        }),
        // Tab meja yang sedang terisi: saat internet putus, tagihannya tetap
        // bisa dilihat & dilunasi (pelunasan masuk antrian).
        coba(() async {
          final meja = await ref
              .read(tableRepositoryProvider)
              .getTables(outletId);
          final repo = ref.read(transactionRepositoryProvider);
          for (final m in meja.where((m) => m.statusIndex == 1).take(60)) {
            await repo.getActiveSalesByTable(m.id);
          }
          return true;
        }),
        // Status langganan & fitur paketnya: tetap berlaku saat offline.
        coba(() async {
          ref.invalidate(activeOutletSubscriptionProvider);
          return ref.read(activeOutletSubscriptionProvider.future);
        }),
        // Promo outlet: kode promo tetap bisa dipakai saat offline.
        coba(
          () => ref.read(promoRepositoryProvider).simpanUntukOffline(outletId),
        ),
        // Pengaturan struk + logonya: struk saat offline tetap memakai
        // branding outlet, dan logo yang baru diganti Pemilik ikut terunduh.
        coba(() async {
          ref.invalidate(receiptSettingsFutureProvider);
          return ref.read(receiptSettingsFutureProvider.future);
        }),
        // Add-on seluruh produk: tanpa ini, sheet pilihan add-on tak muncul
        // saat offline untuk produk yang belum pernah dibuka sambil online.
        coba(() async {
          final produk = await ref.read(productCacheProvider).getAll(outletId);
          return ref
              .read(modifierRepositoryProvider)
              .simpanSemuaUntukOffline(
                outletId,
                idProdukLokal: [
                  for (final p in produk)
                    if (p.remoteId != null) p.remoteId!,
                ],
              );
        }),
      ]);

      // Layar yang sudah terlanjur memuat daftar kosong / galat (mis. dibuka
      // saat offline) dimuat ulang supaya memakai data yang baru diunduh.
      // Yang sudah berisi data dibiarkan — tak perlu permintaan tambahan.
      void segarkanBila<T>(FutureProvider<List<T>> p, bool berhasil) {
        if (!berhasil) return;
        final kini = ref.read(p);
        if (kini.hasError || (kini.value?.isEmpty ?? true)) ref.invalidate(p);
      }

      segarkanBila(paymentMethodsFutureProvider, hasil[0]);
      segarkanBila(orderTypesFutureProvider, hasil[1]);
      segarkanBila(tablesFutureProvider, hasil[2]);
      segarkanBila(tableGroupsFutureProvider, hasil[3]);
    } finally {
      berjalan = false;
    }
  }

  void jalan() => unawaited(siapkan());

  ref.listen<String?>(activeOutletIdProvider, (_, _) => jalan());
  ref.listen<AsyncValue<ConnectionStatus>>(connectivityProvider, (_, next) {
    if (next.value == ConnectionStatus.online) jalan();
  });
  final timer = Timer.periodic(const Duration(minutes: 15), (_) => jalan());
  ref.onDispose(timer.cancel);
  Future.microtask(jalan);
});
