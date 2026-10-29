import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/connectivity_service.dart';
import '../../../core/offline/sale_outbox.dart' show isOfflineError;
import '../../../core/offline/shift_outbox.dart';
import '../../../core/outlet_scope.dart';
import '../../payments/data/payment_method_repository.dart';
import '../../payments/domain/payment_method.dart';
import '../../shifts/data/kas_shift.dart';
import '../../shifts/data/shift_repository.dart';
import '../../user/data/auth_service.dart';
import '../domain/sale.dart';

/// Pelunasan "Bayar Nanti" saat offline.
///
/// # MASALAHNYA
///
/// Melunasi bill/meja dulu dikunci "butuh online". Di gerai F&B yang dine-in-
/// nya Bayar Nanti, internet putus = pelanggan tak bisa membayar: kasir
/// terpaksa membuat transaksi baru (omzet dobel) atau membiarkan pelanggan
/// pulang tanpa catatan bayar.
///
/// # CARANYA
///
/// Pelunasan masuk antrian (op `lunas`) dan langsung tampil lunas di tablet.
/// Server melunasi HANYA tagihan yang disebut — bukan seluruh tab meja, yang
/// bisa sudah bertambah ronde baru selagi offline — di shift & waktu saat uang
/// diterima. Tagihan yang ternyata sudah dilunasi di tempat lain ditolak dan
/// muncul di "Perlu dipulihkan" (pelanggan mungkin membayar dua kali).
///
/// Penjualan Bayar Nanti yang juga dibuat offline (belum terkirim) dirujuk
/// dengan ID lokalnya; pelunasannya menunggu penjualannya terkirim dulu, lalu
/// memakai ID server-nya (lihat ShiftOutbox.petakanIdPenjualan).

/// Tandai sebuah tagihan lunas di tampilan perangkat (pelunasannya belum
/// sampai di server).
Sale tandaiLunasLokal(Sale s) {
  s.isPaid = true;
  s.paymentStatus = 'paid';
  s.pendingSync = true;
  return s;
}

/// ID tagihan yang sudah dilunasi di perangkat tapi pelunasannya belum
/// (atau gagal) terkirim. MURNI.
Set<String> idDilunasiDi(Iterable<PendingOp> ops) => {
  for (final op in ops)
    for (final id in (op.payload['transaction_ids'] as List? ?? const []))
      id.toString(),
};

/// Meja yang seluruh tagihannya sudah dilunasi di perangkat (pelunasan
/// bertanda `meja_kosong`). MURNI.
Set<String> mejaKosongDari(Iterable<PendingOp> ops) => {
  for (final op in ops)
    if (op.payload['meja_kosong'] == true &&
        (op.payload['table_id']?.toString() ?? '').isNotEmpty)
      op.payload['table_id'].toString(),
};

/// Meja yang tampil KOSONG di peta meja walau server (yang belum menerima
/// pelunasannya) masih menganggapnya terisi. Hilang sendiri begitu
/// pelunasannya terkirim — status meja lalu kembali dari server.
final mejaKosongLokalProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(pendingShiftSyncCountProvider);
  try {
    return mejaKosongDari(
      await ref.read(shiftOutboxProvider).semuaBelumSelesai(opLunas),
    );
  } catch (_) {
    return const {};
  }
});

/// Tagihan yang dilunasi di perangkat, untuk menimpa tampilan dari server
/// (yang belum tahu) — supaya kasir tak menagih dua kali.
final idDilunasiLokalProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(pendingShiftSyncCountProvider);
  ref.watch(shiftDeadLetterCountProvider);
  try {
    return idDilunasiDi(
      await ref.read(shiftOutboxProvider).semuaBelumSelesai(opLunas),
    );
  } catch (_) {
    return const {};
  }
});

class PelunasanOffline {
  PelunasanOffline(this.ref);
  final Ref ref;

  /// Lunasi lewat server bila bisa; offline, koneksi putus di tengah, atau
  /// ada tagihan yang belum terkirim → antrian. Mengembalikan true bila
  /// pelunasannya masuk antrian.
  ///
  /// Koneksi yang putus di tengah permintaan membuat hasilnya tak pasti
  /// (mungkin sudah tercatat). Mengantri tetap aman: server menolak pelunasan
  /// kedua dan menampilkannya di "Perlu dipulihkan", bukan mencatatnya dua kali.
  Future<bool> lunasiOnlineAtauAntrikan({
    required List<Sale> tagihan,
    required Future<void> Function() online,
    String? tableId,
    bool mejaKosong = false,
    required String paymentMethod,
    required double cashAmount,
    required double changeAmount,
    String? paymentProofUrl,
  }) async {
    Future<bool> antrikan() async {
      await lunasi(
        tagihan: tagihan,
        tableId: tableId,
        mejaKosong: mejaKosong,
        paymentMethod: paymentMethod,
        cashAmount: cashAmount,
        changeAmount: changeAmount,
        paymentProofUrl: paymentProofUrl,
      );
      return true;
    }

    if (ref.read(isOfflineProvider) || tagihan.any((t) => t.pendingSync)) {
      return antrikan();
    }
    try {
      await online();
      return false;
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      return antrikan();
    }
  }

  /// Antrikan pelunasan [tagihan]. [tableId] diisi untuk tutup meja.
  /// [mejaKosong] — pelunasan ini menghabiskan seluruh tagihan meja, jadi
  /// meja tampil kosong di perangkat sampai pelunasannya terkirim.
  Future<void> lunasi({
    required List<Sale> tagihan,
    String? tableId,
    bool mejaKosong = false,
    required String paymentMethod,
    required double cashAmount,
    required double changeAmount,
    String? paymentProofUrl,
  }) async {
    if (tagihan.isEmpty) throw 'Tidak ada tagihan untuk dilunasi';
    final shift = ref.read(activeShiftProvider).value;
    if (shift == null) {
      throw 'Buka shift kasir dulu sebelum melunasi tagihan';
    }
    final outletId = ref.read(activeOutletIdProvider) ?? '';
    if (outletId.isEmpty) throw 'Outlet aktif belum dipilih';

    final metode = await ref
        .read(paymentMethodsFutureProvider.future)
        .catchError((_) => <PaymentMethod>[]);
    final total = tagihan.fold<double>(0, (s, t) => s + t.total);
    final tunai = tunaiDari(metode)(paymentMethod);

    final outbox = ref.read(shiftOutboxProvider);
    final localShift = shift.localShiftId;
    await outbox.enqueueOp(
      opType: opLunas,
      outletId: outletId,
      clientRef:
          'lns_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(0x7fffffff)}',
      occurredAt: DateTime.now(),
      serverShiftId: (shift.remoteId ?? '').isEmpty ? null : shift.remoteId,
      localShiftId: localShift,
      dependsOn: localShift == null
          ? null
          : await outbox.openLocalIdFor(localShift),
      payload: {
        'transaction_ids': [for (final t in tagihan) t.id],
        if ((tableId ?? '').isNotEmpty) 'table_id': tableId,
        if (mejaKosong && (tableId ?? '').isNotEmpty) 'meja_kosong': true,
        'payment_method': paymentMethod,
        'cash_amount': cashAmount,
        'change_amount': changeAmount,
        if ((paymentProofUrl ?? '').isNotEmpty)
          'payment_proof_url': paymentProofUrl,
        'total': total,
        // Uang tunai yang masuk laci — untuk ekspektasi kas shift.
        'porsi_tunai': tunai ? total : 0,
        'shift_client_ref': shift.clientRef ?? '',
        'cashier_id': ref.read(authProvider).user?.remoteId ?? '',
      },
    );
    await ref.read(pendingShiftSyncCountProvider.notifier).refresh();
    ref.invalidate(idDilunasiLokalProvider);
    ref.invalidate(mejaKosongLokalProvider);
  }
}

final pelunasanOfflineProvider = Provider<PelunasanOffline>(
  PelunasanOffline.new,
);
