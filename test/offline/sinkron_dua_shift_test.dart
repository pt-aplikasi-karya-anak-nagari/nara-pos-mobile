import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nara_pos_mobile/core/offline/offline_sync_service.dart';
import 'package:nara_pos_mobile/core/offline/sale_outbox.dart';
import 'package:nara_pos_mobile/core/offline/shift_outbox.dart';
import 'package:nara_pos_mobile/features/shifts/data/shift_api_service.dart';
import 'package:nara_pos_mobile/features/shifts/domain/shift.dart';
import 'package:nara_pos_mobile/features/transactions/data/transaction_repository.dart';

// Sinkron antrian offline yang melewati LEBIH DARI SATU shift.
//
// # KEJADIANNYA
//
// Kasir berjualan dua hari tanpa sinyal: buka shift, jualan, tutup; besoknya
// buka lagi, jualan lagi, tutup lagi. Semuanya menumpuk di outbox. Lalu sinyal
// kembali.
//
// Penyinkron menguras per FASE, bukan per shift: SELURUH op buka, lalu SELURUH
// sale, lalu SELURUH op tutup. Untuk dua shift urutan itu tak bisa selesai
// dalam satu lintasan:
//
//	FASE A  buka hari-1 → sukses
//	        buka hari-2 → DITOLAK, server melihat hari-1 masih terbuka
//	FASE B  35 sale hari-2 → shift tujuannya belum ada
//	FASE C  tutup hari-1 → sukses
//
// Prasyarat buka hari-2 baru terpenuhi SESUDAH sync-nya selesai. Lintasan
// berikutnya menunggu koneksi putus lalu tersambung lagi.
//
// # KENAPA INI SOAL UANG, BUKAN SOAL KERAPIAN
//
// Sebelum perbaikan sisi server, sale hari-2 yang shift-nya gagal di-resolve
// TIDAK ditolak: server diam-diam mengikatnya ke shift mana pun yang kebetulan
// terbuka — yaitu shift HARI-1 — lalu membalas 200. Outbox menghapusnya, tak
// ada galat di mana pun, dan Z-Report hari-1 menanggung omzet dua hari dengan
// uang laci sehari. Kasir hari-1 tampak menggelapkan seluruh omzet hari-2.
//
// Sesudah server menolak, bahayanya berpindah bentuk: penolakan itu menaikkan
// attempts, dan lima kali sambung-ulang tanpa sempat ter-drain membuat seluruh
// omzet hari-2 jadi dead-letter.
//
// Yang dijaga tes ini: satu panggilan sync menyelesaikan KEDUA shift, tiap sale
// mendarat di shift yang benar, dan tak ada yang menumpuk attempts.

/// Server tiruan yang menegakkan satu aturan yang menyebabkan seluruh kejadian
/// di atas: satu outlet hanya boleh punya SATU shift terbuka.
class ServerPalsu {
  final Map<String, String> refKeShift = {}; // client_ref → id shift server
  final Set<String> terbuka = {};
  final Map<String, List<String>> salePerShift = {}; // id shift → localId sale
  int tolakBuka = 0;
  int tolakSale = 0;

  String buka(String outletId, String clientRef) {
    if (refKeShift.containsKey(clientRef)) return refKeShift[clientRef]!;
    if (terbuka.any((id) => id.startsWith('$outletId/'))) {
      tolakBuka++;
      throw Exception('anda masih memiliki shift yang belum ditutup');
    }
    final id = '$outletId/${refKeShift.length + 1}';
    refKeShift[clientRef] = id;
    terbuka.add(id);
    return id;
  }

  void tutup(String shiftId) => terbuka.remove(shiftId);

  /// Cermin cabang server sesudah perbaikan: sale yang MENYEBUT shift lewat
  /// client-ref dan tak bisa di-resolve ditolak, tidak ditebak.
  void jual(String localId, String clientRef) {
    final shiftId = refKeShift[clientRef];
    if (shiftId == null || !terbuka.contains(shiftId)) {
      tolakSale++;
      throw Exception('shift transaksi ini belum tersedia di server');
    }
    salePerShift.putIfAbsent(shiftId, () => []).add(localId);
  }
}

class ShiftApiPalsu extends ShiftApiService {
  final ServerPalsu srv;
  ShiftApiPalsu(this.srv) : super(Dio());

  @override
  Future<Shift> openShift(
    String outletId,
    double startingCash,
    String notes, {
    String? clientRef,
    DateTime? occurredAt,
  }) async {
    final id = srv.buka(outletId, clientRef ?? '');
    return Shift(
      remoteId: id,
      startTime: DateTime(2026),
      startingCash: startingCash,
      cashierName: 'Kasir',
      cashierRemoteId: 'kasir-1',
    );
  }

  @override
  Future<Shift> closeShift(
    String outletId,
    String shiftId,
    double closingCash,
    String notes, {
    String? clientRef,
    DateTime? occurredAt,
  }) async {
    srv.tutup(shiftId);
    return Shift(
      remoteId: shiftId,
      startTime: DateTime(2026),
      startingCash: 0,
      cashierName: 'Kasir',
      cashierRemoteId: 'kasir-1',
      isOpen: false,
    );
  }
}

class TrxApiPalsu extends TransactionApiService {
  final ServerPalsu srv;
  final Map<String, String> localIdPerPayload;
  TrxApiPalsu(this.srv, this.localIdPerPayload) : super(Dio());

  @override
  Future<Map<String, dynamic>> checkout(
    String outletId,
    Map<String, dynamic> data,
  ) async {
    final ref = data['shift_client_ref']?.toString() ?? '';
    srv.jual(localIdPerPayload[ref + data['tanda'].toString()] ?? '?', ref);
    return {'id': 'ok'};
  }
}

/// Outbox shift in-memory. Semua metode yang disentuh penyinkron ditimpa, jadi
/// sqflite tak pernah tersentuh.
class ShiftOutboxPalsu extends ShiftOutbox {
  final List<PendingOp> ops;
  ShiftOutboxPalsu(this.ops);

  List<PendingOp> _aktif(String tipe) => ops
      .where(
        (o) =>
            o.opType == tipe &&
            o.status == 'pending' &&
            o.attempts < ShiftOutbox.maxSyncAttempts,
      )
      .toList();

  @override
  Future<List<PendingOp>> opensPending() async => _aktif(opShiftOpen);
  @override
  Future<List<PendingOp>> closesPending() async => _aktif(opShiftClose);

  PendingOp _salin(
    PendingOp o, {
    String? serverShiftId,
    String? status,
    int? attempts,
    String? lastError,
  }) => PendingOp(
    localId: o.localId,
    opType: o.opType,
    outletId: o.outletId,
    clientRef: o.clientRef,
    payload: o.payload,
    localShiftId: o.localShiftId,
    serverShiftId: serverShiftId ?? o.serverShiftId,
    status: status ?? o.status,
    createdAt: o.createdAt,
    attempts: attempts ?? o.attempts,
    lastError: lastError ?? o.lastError,
  );

  void _ubah(bool Function(PendingOp) cocok, PendingOp Function(PendingOp) f) {
    for (var i = 0; i < ops.length; i++) {
      if (cocok(ops[i])) ops[i] = f(ops[i]);
    }
  }

  @override
  Future<void> setServerShiftId(String localShiftId, String serverId) async =>
      _ubah(
        (o) => o.localShiftId == localShiftId,
        (o) => _salin(o, serverShiftId: serverId),
      );

  @override
  Future<void> markDeadCascade(String localShiftId, String reason) async =>
      _ubah(
        (o) => o.localShiftId == localShiftId,
        (o) => _salin(o, status: 'dead', lastError: reason),
      );

  @override
  Future<void> remove(String localId) async =>
      ops.removeWhere((o) => o.localId == localId);

  @override
  Future<void> markError(String localId, String error) async => _ubah(
    (o) => o.localId == localId,
    (o) => _salin(o, attempts: o.attempts + 1, lastError: error),
  );

  @override
  Future<int> count() async =>
      _aktif(opShiftOpen).length + _aktif(opShiftClose).length;
  @override
  Future<int> deadLetterCount() async => ops
      .where(
        (o) => o.status == 'dead' || o.attempts >= ShiftOutbox.maxSyncAttempts,
      )
      .length;
}

class SaleOutboxPalsu extends SaleOutbox {
  final List<PendingSale> sales;
  SaleOutboxPalsu(this.sales);

  @override
  Future<List<PendingSale>> pending() async =>
      sales.where((s) => s.attempts < SaleOutbox.maxSyncAttempts).toList();

  @override
  Future<void> remove(String localId) async =>
      sales.removeWhere((s) => s.localId == localId);

  @override
  Future<void> markError(String localId, String error) async {
    for (var i = 0; i < sales.length; i++) {
      if (sales[i].localId != localId) continue;
      sales[i] = PendingSale(
        localId: sales[i].localId,
        outletId: sales[i].outletId,
        payload: sales[i].payload,
        createdAt: sales[i].createdAt,
        attempts: sales[i].attempts + 1,
        lastError: error,
      );
    }
  }

  @override
  Future<int> count() async => (await pending()).length;
  @override
  Future<int> deadLetterCount() async =>
      sales.where((s) => s.attempts >= SaleOutbox.maxSyncAttempts).length;
}

const outlet = 'OUT-1';

PendingOp opBuka(String n, String ref) => PendingOp(
  localId: 'op-buka-$n',
  opType: opShiftOpen,
  outletId: outlet,
  clientRef: ref,
  payload: const {'start_balance': 100000, 'notes': 'buka'},
  localShiftId: 'lokal-$n',
  createdAt: DateTime(2026, 1, int.parse(n)),
);

PendingOp opTutup(String n, String ref, {String? serverShiftId}) => PendingOp(
  localId: 'op-tutup-$n',
  opType: opShiftClose,
  outletId: outlet,
  clientRef: ref,
  payload: const {'actual_balance': 500000, 'notes': 'tutup'},
  localShiftId: 'lokal-$n',
  serverShiftId: serverShiftId,
  createdAt: DateTime(2026, 1, int.parse(n)),
);

PendingSale sale(String id, String refShift) => PendingSale(
  localId: id,
  outletId: outlet,
  payload: {'shift_client_ref': refShift, 'tanda': id, 'final_amount': 80000},
  createdAt: DateTime(2026),
);

/// Bangun container + jalankan satu sync, kembalikan servernya untuk diperiksa.
Future<(ServerPalsu, ShiftOutboxPalsu, SaleOutboxPalsu, SyncResult)> jalankan({
  required List<PendingOp> ops,
  required List<PendingSale> sales,
}) async {
  final srv = ServerPalsu();
  final so = ShiftOutboxPalsu(ops);
  final salesOut = SaleOutboxPalsu(sales);
  final peta = {
    for (final s in sales)
      s.payload['shift_client_ref'].toString() + s.localId: s.localId,
  };

  final c = ProviderContainer(
    overrides: [
      shiftOutboxProvider.overrideWithValue(so),
      saleOutboxProvider.overrideWithValue(salesOut),
      shiftApiServiceProvider.overrideWithValue(ShiftApiPalsu(srv)),
      transactionApiServiceProvider.overrideWithValue(TrxApiPalsu(srv, peta)),
    ],
  );
  addTearDown(c.dispose);
  final hasil = await c.read(offlineSyncServiceProvider).sync();
  return (srv, so, salesOut, hasil);
}

void main() {
  test('dua shift offline selesai dalam SATU kali sync', () async {
    // Hari-1 sudah punya server_shift_id? Belum — semuanya offline murni.
    final ops = [
      opBuka('1', 'ref-1'),
      opBuka('2', 'ref-2'),
      opTutup('1', 'tutup-1'),
      opTutup('2', 'tutup-2'),
    ];
    final sales = [
      sale('s1a', 'ref-1'),
      sale('s1b', 'ref-1'),
      sale('s2a', 'ref-2'),
      sale('s2b', 'ref-2'),
    ];

    final (srv, so, salesOut, _) = await jalankan(ops: ops, sales: sales);

    expect(
      salesOut.sales,
      isEmpty,
      reason:
          'masih ada ${salesOut.sales.length} sale tertahan setelah sync — '
          'omzet hari-2 menunggu sambung-ulang berikutnya, dan attempts-nya '
          'sudah mulai naik menuju dead-letter',
    );
    expect(
      so.ops,
      isEmpty,
      reason: 'op shift masih tersisa: ${so.ops.map((o) => o.localId)}',
    );

    // Yang paling penting: tiap sale mendarat di shift yang BENAR.
    final shift1 = srv.refKeShift['ref-1']!;
    final shift2 = srv.refKeShift['ref-2']!;
    expect(shift1, isNot(shift2));
    expect(srv.salePerShift[shift1], unorderedEquals(['s1a', 's1b']));
    expect(
      srv.salePerShift[shift2],
      unorderedEquals(['s2a', 's2b']),
      reason:
          'penjualan hari-2 tidak mendarat di shift hari-2 — inilah bentuk '
          'yang membuat Z-Report menuduh kasir hari-1 kurang setor',
    );
  });

  test('penolakan urutan tidak menaikkan attempts', () async {
    // Buka hari-2 PASTI ditolak sekali; itu urutan, bukan cacat datanya. Kalau
    // attempts-nya ikut naik, lima kali offline-dua-shift sudah cukup untuk
    // mematikan op yang tak pernah bermasalah.
    final ops = [
      opBuka('1', 'ref-1'),
      opBuka('2', 'ref-2'),
      opTutup('1', 'tutup-1'),
      opTutup('2', 'tutup-2'),
    ];
    final (srv, _, _, hasil) = await jalankan(
      ops: ops,
      sales: [sale('s2a', 'ref-2')],
    );

    expect(
      srv.tolakBuka,
      greaterThan(0),
      reason: 'skenarionya tak tereproduksi',
    );
    expect(
      hasil.failed,
      0,
      reason:
          '${hasil.failed} sale dihitung gagal padahal semuanya akhirnya masuk',
    );
  });

  test('satu shift saja tetap selesai, tanpa putaran tambahan', () async {
    // Sisi yang tak boleh ikut berubah — kasus sehari-hari.
    final (srv, so, salesOut, hasil) = await jalankan(
      ops: [opBuka('1', 'ref-1'), opTutup('1', 'tutup-1')],
      sales: [sale('s1a', 'ref-1')],
    );
    expect(hasil.synced, 1);
    expect(salesOut.sales, isEmpty);
    expect(so.ops, isEmpty);
    expect(srv.tolakBuka, 0);
    expect(srv.tolakSale, 0);
  });

  test('sale rusak tidak membakar attempts sekali per putaran', () async {
    // Kasus yang hanya muncul setelah sync jadi berputar: satu sale yang
    // memang rusak akan dicoba ULANG di tiap putaran selama putaran itu masih
    // terjadi karena op LAIN maju. Tiga putaran = tiga attempts dari satu kali
    // sambung. Batas lima percobaan habis dalam dua kali sambung, dan sale itu
    // mati sebagai dead-letter jauh sebelum kasirnya sempat melihat apa pun.
    //
    // Dead-letter memang tujuan akhirnya — tapi lewat lima kali sambung-ulang
    // yang terpisah, bukan lima kali dalam satu tarikan napas.
    final (_, _, salesOut, _) = await jalankan(
      ops: [
        opBuka('1', 'ref-1'),
        opBuka('2', 'ref-2'),
        opTutup('1', 'tutup-1'),
        opTutup('2', 'tutup-2'),
      ],
      sales: [
        sale('s1a', 'ref-1'),
        sale('s2a', 'ref-2'),
        sale('rusak', 'ref-hantu'),
      ],
    );

    // Yang sehat tetap masuk; hanya yang rusak tertinggal.
    expect(salesOut.sales.map((s) => s.localId), ['rusak']);
    expect(
      salesOut.sales.single.attempts,
      1,
      reason:
          'satu kali sync menaikkan attempts '
          '${salesOut.sales.single.attempts} kali — sale ini akan mati '
          'sebagai dead-letter setelah dua kali sambung, bukan lima',
    );
  });

  test(
    'sale yang shift-nya TAK PERNAH datang tetap jadi dead-letter',
    () async {
      // Sisi lain yang harus dijaga: menunggu selamanya sama buruknya dengan
      // salah simpan. Sale yang menyebut shift yang tak ada op buka-nya harus
      // menumpuk attempts sampai muncul di daftar "Perlu dipulihkan", bukan
      // di-skip diam-diam tiap sync.
      final (_, _, salesOut, hasil) = await jalankan(
        ops: [],
        sales: [sale('yatim', 'ref-hantu')],
      );
      expect(hasil.failed, 1);
      expect(
        salesOut.sales.single.attempts,
        1,
        reason:
            'attempts tak naik — sale ini akan dilewati setiap sync sampai '
            'kiamat tanpa pernah terlihat siapa pun',
      );
    },
  );
}
