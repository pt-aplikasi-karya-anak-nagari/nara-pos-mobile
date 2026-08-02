import '../../../core/outlet_scope.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/offline/entity_cache.dart';
import '../../outlet/data/outlet_service.dart';
import '../domain/payment_method.dart';

/// Cache offline metode bayar per outlet. Checkout-blocking: tanpa ini hanya
/// metode virtual "Bayar Nanti" yang tersedia saat offline.
final _paymentMethodCache = EntityCache<PaymentMethod>(
  'payment_methods',
  toJson: (m) => m.toCacheJson(),
  fromJson: PaymentMethod.fromJson,
);

class PaymentMethodRepository {
  final Ref _ref;
  PaymentMethodRepository(this._ref);

  Future<List<PaymentMethod>> getAll(String outletId) async {
    return readThroughCache(
      cache: _paymentMethodCache,
      outletId: outletId,
      fetch: () async {
        final list =
            await _ref.read(outletServiceProvider).getPaymentMethods(outletId);
        return list.map((json) => PaymentMethod.fromJson(json)).toList();
      },
    );
  }

  Future<void> save(PaymentMethod method) async {
    if (method.outletRemoteId == null) throw 'Outlet ID tidak boleh kosong';
    await _ref.read(outletServiceProvider).savePaymentMethod(
          method.outletRemoteId!,
          method.toJson(),
        );
  }

  Future<void> remove(String id) async {
    await _ref.read(outletServiceProvider).deletePaymentMethod(id);
  }

  // Toggle aktif tanpa kirim full body — backend punya PATCH endpoint
  // khusus untuk operasi ini.
  Future<void> setActive(String id, bool active) async {
    await _ref.read(outletServiceProvider).setPaymentMethodActive(id, active);
  }

  // Tandai metode jadi default outlet. Backend otomatis unset semua
  // entri lain di outlet sama, jadi UI tidak perlu dua kali fetch /
  // dua kali update.
  Future<void> setDefault(String id) async {
    await _ref.read(outletServiceProvider).setPaymentMethodDefault(id);
  }
}

final paymentMethodRepositoryProvider = Provider<PaymentMethodRepository>((ref) {
  return PaymentMethodRepository(ref);
});

final paymentMethodsFutureProvider = FutureProvider<List<PaymentMethod>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return [];
  return ref.watch(paymentMethodRepositoryProvider).getAll(outletId);
});

/// Kunci permintaan QRIS dinamis: metode bayar mana, nominal berapa.
///
/// Butuh == dan hashCode sendiri supaya provider family men-cache per
/// (metode, nominal). Tanpa itu setiap rebuild layar bayar — dan layar itu
/// dibangun ulang tiap kali kasir mengetik — menembak server lagi.
class KunciQrisDinamis {
  final String paymentMethodId;
  final double nominal;

  const KunciQrisDinamis(this.paymentMethodId, this.nominal);

  @override
  bool operator ==(Object other) =>
      other is KunciQrisDinamis &&
      other.paymentMethodId == paymentMethodId &&
      other.nominal == nominal;

  @override
  int get hashCode => Object.hash(paymentMethodId, nominal);
}

/// QRIS bernominal untuk satu transaksi, disusun server.
///
/// # KENAPA SERVER YANG MENYUSUN
///
/// Payload hasilnya menentukan ke rekening mana uang pelanggan mengalir.
/// Aturan pembentukannya (urutan tag EMVCo, checksum CRC-16) harus hidup di
/// SATU tempat yang bisa diuji dan diperbaiki tanpa menunggu setiap tablet
/// memperbarui aplikasinya.
///
/// # KENAPA GAGALNYA TIDAK DISEMBUNYIKAN
///
/// Pemanggil menangani `error` secara khusus: ia kembali ke QRIS STATIS milik
/// outlet dan mengatakan terus terang bahwa nominalnya harus diketik pelanggan.
/// Itu jauh lebih baik daripada layar bayar yang kosong — QRIS statis tetap
/// menerima uang, hanya kurang nyaman.
final qrisDinamisProvider =
    FutureProvider.family<Map<String, dynamic>, KunciQrisDinamis>((
  ref,
  kunci,
) async {
  return ref
      .read(outletServiceProvider)
      .buatQrisDinamis(kunci.paymentMethodId, kunci.nominal);
});
