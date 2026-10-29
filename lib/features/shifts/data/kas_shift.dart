import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/connectivity_service.dart';
import '../../../core/offline/entity_cache.dart';
import '../../../core/offline/offline_sync_service.dart';
import '../../../core/offline/sale_outbox.dart';
import '../../../core/offline/shift_outbox.dart';
import '../../../core/outlet_scope.dart';
import '../../payments/data/payment_method_repository.dart';
import '../../payments/domain/payment_method.dart';
import '../../user/data/auth_service.dart';
import '../domain/shift.dart';
import 'shift_api_service.dart';
import 'shift_repository.dart';

/// Buku kas shift di perangkat: kas masuk/keluar dan ekspektasi uang laci.
///
/// # MASALAH YANG DITUTUP
///
///  1. Kas masuk/keluar dulu langsung dikirim ke server. Saat offline gagal
///     ("Gagal mencatat kas"), uang belanja es batu tak tercatat, dan saat
///     tutup shift laci terlihat KURANG — kasir yang disalahkan.
///  2. Ekspektasi kas saat tutup shift hanya dari server. Shift yang dibuka
///     offline tak punya angka sama sekali; shift yang dibuka online lalu
///     internet putus tak menghitung penjualan offline-nya — laci terlihat
///     LEBIH padahal pas.
///
/// Kini kas dicatat ke antrian bila tak bisa langsung terkirim, dan ekspektasi
/// kas = bagian yang sudah diketahui server + bagian yang masih di antrian
/// perangkat. Yang sudah terkirim dihapus dari antrian, jadi tak terhitung
/// dua kali.

/// Identitas sebuah shift di perangkat. Shift dari server punya [remoteId];
/// shift yang dibuka offline punya [localShiftId] & [clientRef] (open
/// client ref) sampai buka-nya terkirim.
typedef KunciShift = ({
  String? remoteId,
  String? localShiftId,
  String? clientRef,
});

KunciShift kunciShift(Shift s) => (
  remoteId: s.remoteId,
  localShiftId: s.localShiftId,
  clientRef: s.clientRef,
);

bool _sama(String? a, Object? b) =>
    a != null && a.isNotEmpty && b != null && b.toString() == a;

/// Op antrian (kas/pelunasan) milik shift [k]?
bool opMilikShift(PendingOp op, KunciShift k) =>
    _sama(k.remoteId, op.serverShiftId) ||
    _sama(k.localShiftId, op.localShiftId) ||
    _sama(k.clientRef, op.payload['shift_client_ref']);

/// Penjualan di antrian milik shift [k]? (lihat checkout: shift_id /
/// shift_client_ref di payload)
bool penjualanMilikShift(Map<String, dynamic> payload, KunciShift k) =>
    _sama(k.remoteId, payload['shift_id']) ||
    _sama(k.clientRef, payload['shift_client_ref']);

/// Pengenal metode bayar tunai: tipe 'cash' dari daftar metode outlet, atau
/// bernama "Tunai" (sama dengan aturan server).
bool Function(String) tunaiDari(List<PaymentMethod> metode) {
  final nama = {
    for (final m in metode)
      if (m.type.toLowerCase() == 'cash') ...[
        m.name.toLowerCase(),
        if (m.code.isNotEmpty) m.code.toLowerCase(),
      ],
  };
  return (method) {
    final x = method.trim().toLowerCase();
    return x == 'tunai' || x == 'cash' || nama.contains(x);
  };
}

double _angka(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

/// Uang tunai yang masuk laci dari satu penjualan di antrian. Belum dibayar
/// (Bayar Nanti) = 0; uangnya masuk saat dilunasi (op pelunasan).
double porsiTunai(Map<String, dynamic> payload, bool Function(String) tunai) {
  if (payload['is_paid'] == false) return 0;
  final tender = payload['payments'];
  if (tender is List && tender.isNotEmpty) {
    return tender.fold<double>(0, (s, t) {
      if (t is! Map) return s;
      final tipe = t['payment_type']?.toString().toLowerCase() ?? '';
      final cash = tipe.isNotEmpty
          ? tipe == 'cash'
          : tunai(t['payment_method']?.toString() ?? '');
      return cash ? s + _angka(t['amount']) : s;
    });
  }
  return tunai(payload['payment_method']?.toString() ?? '')
      ? _angka(payload['final_amount'])
      : 0;
}

/// Satu baris kas masuk/keluar untuk ditampilkan.
class KasShift {
  const KasShift({
    required this.type,
    required this.amount,
    required this.note,
    required this.waktu,
    this.menunggu = false,
    this.gagal = false,
  });

  final String type; // 'in' | 'out'
  final double amount;
  final String note;
  final DateTime waktu;

  /// Belum sampai di server (antrian).
  final bool menunggu;

  /// Ditolak server — perlu dipulihkan.
  final bool gagal;

  bool get masuk => type == 'in';
}

/// Ringkasan uang laci satu shift.
class RingkasanKasShift {
  const RingkasanKasShift({
    required this.modalAwal,
    required this.penjualanTunai,
    required this.kasMasuk,
    required this.kasKeluar,
    required this.belumTerkirim,
  });

  final double modalAwal;
  final double penjualanTunai;
  final double kasMasuk;
  final double kasKeluar;

  /// Jumlah transaksi/kas/pelunasan yang ikut dihitung tapi belum terkirim.
  final int belumTerkirim;

  double get ekspektasi => modalAwal + penjualanTunai + kasMasuk - kasKeluar;
}

/// Hitung ringkasan kas. MURNI — bagian server + bagian antrian perangkat.
///
/// [penjualanTunaiServer] = total_sales shift dari server (penjualan tunai
/// yang sudah sampai, termasuk pelunasan). 0 untuk shift yang dibuka offline.
RingkasanKasShift hitungRingkasanKas({
  required KunciShift shift,
  required double modalAwal,
  required double penjualanTunaiServer,
  required List<Map<String, dynamic>> kasServer,
  required List<Map<String, dynamic>> penjualanAntrian,
  required List<PendingOp> kasAntrian,
  required List<PendingOp> lunasAntrian,
  required bool Function(String) tunai,
}) {
  var penjualan = penjualanTunaiServer;
  var masuk = 0.0, keluar = 0.0;
  var belum = 0;
  for (final k in kasServer) {
    if (k['type'] == 'in') {
      masuk += _angka(k['amount']);
    } else {
      keluar += _angka(k['amount']);
    }
  }
  for (final p in penjualanAntrian) {
    if (!penjualanMilikShift(p, shift)) continue;
    penjualan += porsiTunai(p, tunai);
    belum++;
  }
  for (final op in kasAntrian) {
    if (!opMilikShift(op, shift)) continue;
    if (op.payload['type'] == 'in') {
      masuk += _angka(op.payload['amount']);
    } else {
      keluar += _angka(op.payload['amount']);
    }
    belum++;
  }
  for (final op in lunasAntrian) {
    if (!opMilikShift(op, shift)) continue;
    penjualan += _angka(op.payload['porsi_tunai']);
    belum++;
  }
  return RingkasanKasShift(
    modalAwal: modalAwal,
    penjualanTunai: penjualan,
    kasMasuk: masuk,
    kasKeluar: keluar,
    belumTerkirim: belum,
  );
}

String _refBaru(String awalan) =>
    '${awalan}_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(0x7fffffff)}';

/// Kas masuk/keluar dari server, disimpan supaya tetap terhitung saat offline.
final _kasServerCache = EntityCache<Map<String, dynamic>>(
  'kas_shift',
  toJson: (m) => m,
  fromJson: (m) => m,
);

Future<List<Map<String, dynamic>>> _kasServer(Ref ref, String? remoteId) async {
  if (remoteId == null || remoteId.isEmpty) return const [];
  try {
    return await readThroughCache<Map<String, dynamic>>(
      cache: _kasServerCache,
      outletId: remoteId,
      fetch: () => ref.read(shiftApiServiceProvider).getCashMovements(remoteId),
    );
  } catch (_) {
    try {
      return await _kasServerCache.getAll(remoteId);
    } catch (_) {
      return const [];
    }
  }
}

/// Catat kas masuk/keluar. Online → langsung ke server; offline (atau gagal
/// karena koneksi) → antrian, terkirim otomatis nanti. Mengembalikan true bila
/// sudah sampai di server.
class KasShiftService {
  KasShiftService(this.ref);
  final Ref ref;

  Future<bool> catat(
    Shift shift, {
    required String type,
    required double amount,
    String note = '',
  }) => catatKas(ref, shift, type: type, amount: amount, note: note);
}

final kasShiftServiceProvider = Provider<KasShiftService>(KasShiftService.new);

Future<bool> catatKas(
  Ref ref,
  Shift shift, {
  required String type,
  required double amount,
  String note = '',
}) async {
  final clientRef = _refBaru('kas');
  final waktu = DateTime.now();
  final remoteId = shift.remoteId ?? '';
  if (remoteId.isNotEmpty && !ref.read(isOfflineProvider)) {
    try {
      await ref
          .read(shiftApiServiceProvider)
          .addCashMovement(
            remoteId,
            type: type,
            amount: amount,
            note: note,
            clientRef: clientRef,
            occurredAt: waktu,
          );
      return true;
    } catch (e) {
      // Galat koneksi: mungkin sudah tercatat, mungkin belum — antrian dengan
      // client_ref yang sama aman untuk keduanya.
      if (!isOfflineError(e)) rethrow;
    }
  }
  final outletId = shift.outletRemoteId ?? ref.read(activeOutletIdProvider);
  if (outletId == null || outletId.isEmpty) throw 'Outlet aktif belum dipilih';
  final outbox = ref.read(shiftOutboxProvider);
  final localShift = shift.localShiftId;
  await outbox.enqueueOp(
    opType: opKas,
    outletId: outletId,
    clientRef: clientRef,
    occurredAt: waktu,
    serverShiftId: remoteId.isEmpty ? null : remoteId,
    localShiftId: localShift,
    dependsOn: localShift == null
        ? null
        : await outbox.openLocalIdFor(localShift),
    payload: {
      'type': type,
      'amount': amount,
      'note': note,
      'shift_client_ref': shift.clientRef ?? '',
      'cashier_id': ref.read(authProvider).user?.remoteId ?? '',
    },
  );
  await ref.read(pendingShiftSyncCountProvider.notifier).refresh();
  return false;
}

/// Kas masuk/keluar satu shift: dari server + yang masih di antrian.
final daftarKasShiftProvider =
    FutureProvider.family<List<KasShift>, KunciShift>((ref, k) async {
      ref.watch(pendingShiftSyncCountProvider);
      ref.watch(shiftDeadLetterCountProvider);
      final server = await _kasServer(ref, k.remoteId);
      final ops = await ref.read(shiftOutboxProvider).semuaBelumSelesai(opKas);
      return [
        for (final m in server)
          KasShift(
            type: m['type']?.toString() ?? 'out',
            amount: _angka(m['amount']),
            note: m['note']?.toString() ?? '',
            waktu:
                DateTime.tryParse('${m['created_at']}')?.toLocal() ??
                DateTime.now(),
          ),
        for (final op in ops)
          if (opMilikShift(op, k))
            KasShift(
              type: op.payload['type']?.toString() ?? 'out',
              amount: _angka(op.payload['amount']),
              note: op.payload['note']?.toString() ?? '',
              waktu:
                  DateTime.tryParse(op.occurredAt ?? '')?.toLocal() ??
                  op.createdAt,
              menunggu: true,
              gagal:
                  op.status == 'dead' ||
                  op.attempts >= ShiftOutbox.maxSyncAttempts,
            ),
      ]..sort((a, b) => b.waktu.compareTo(a.waktu));
    });

/// Ringkasan kas shift aktif untuk dialog tutup shift.
final ringkasanKasShiftProvider =
    FutureProvider.family<RingkasanKasShift, KunciShift>((ref, k) async {
      ref.watch(pendingSyncCountProvider);
      ref.watch(pendingShiftSyncCountProvider);
      ref.watch(progresSinkronProvider.select((p) => p.berjalan));

      // Angka server terbaru untuk shift ini (offline → yang tersimpan).
      Shift? shift = ref.read(activeShiftProvider).value;
      final outletId = ref.read(activeOutletIdProvider);
      if ((k.remoteId ?? '').isNotEmpty && outletId != null) {
        try {
          final s = await ref
              .read(shiftRepositoryProvider)
              .getActiveShift(outletId);
          if (s?.remoteId == k.remoteId) shift = s;
        } catch (_) {}
      }
      final metode = await ref
          .read(paymentMethodsFutureProvider.future)
          .catchError((_) => <PaymentMethod>[]);
      final saleOutbox = ref.read(saleOutboxProvider);
      final shiftOutbox = ref.read(shiftOutboxProvider);
      return hitungRingkasanKas(
        shift: k,
        modalAwal: shift?.startingCash ?? 0,
        penjualanTunaiServer: (k.remoteId ?? '').isNotEmpty
            ? (shift?.totalSales ?? 0)
            : 0,
        kasServer: await _kasServer(ref, k.remoteId),
        penjualanAntrian: [
          for (final ps in await saleOutbox.pending()) ps.payload,
          for (final ps in await saleOutbox.deadLetters()) ps.payload,
        ],
        kasAntrian: await shiftOutbox.semuaBelumSelesai(opKas),
        lunasAntrian: await shiftOutbox.semuaBelumSelesai(opLunas),
        tunai: tunaiDari(metode),
      );
    });
