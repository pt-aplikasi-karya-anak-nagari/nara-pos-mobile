import 'package:flutter_test/flutter_test.dart';

import 'package:nara_pos_mobile/core/offline/shift_outbox.dart';
import 'package:nara_pos_mobile/features/payments/domain/payment_method.dart';
import 'package:nara_pos_mobile/features/shifts/data/kas_shift.dart';
import 'package:nara_pos_mobile/features/transactions/data/pelunasan_offline.dart';
import 'package:nara_pos_mobile/features/transactions/domain/sale.dart';

// Kas masuk/keluar, pelunasan Bayar Nanti, dan ekspektasi kas tutup shift
// saat offline. Yang dijaga: uang yang benar-benar berpindah tangan terhitung
// tepat sekali di shift yang benar.

PendingOp _op(
  String type,
  Map<String, dynamic> payload, {
  String? serverShiftId,
  String? localShiftId,
  String status = 'pending',
}) => PendingOp(
  localId: 'op_${payload.hashCode}',
  opType: type,
  outletId: 'o1',
  clientRef: 'ref',
  payload: payload,
  serverShiftId: serverShiftId,
  localShiftId: localShiftId,
  status: status,
  createdAt: DateTime(2026, 10, 29, 10),
  occurredAt: '2026-10-29T03:00:00Z',
);

final _tunai = tunaiDari([
  PaymentMethod(id: 'pm1', name: 'Uang Tunai', type: 'cash', code: 'CASH'),
  PaymentMethod(id: 'pm2', name: 'QRIS', type: 'qris', code: 'QRIS'),
]);

void main() {
  group('porsiTunai', () {
    test('penjualan tunai lunas = total', () {
      expect(
        porsiTunai({
          'payment_method': 'Uang Tunai',
          'final_amount': 50000,
        }, _tunai),
        50000,
      );
      expect(
        porsiTunai({'payment_method': 'Tunai', 'final_amount': 10000}, _tunai),
        10000,
      );
    });

    test('non-tunai & Bayar Nanti tak menambah uang laci', () {
      expect(
        porsiTunai({'payment_method': 'QRIS', 'final_amount': 50000}, _tunai),
        0,
      );
      expect(
        porsiTunai({
          'payment_method': 'Tunai',
          'final_amount': 50000,
          'is_paid': false,
        }, _tunai),
        0,
        reason: 'uangnya masuk saat dilunasi',
      );
    });

    test('split: hanya porsi tunai', () {
      expect(
        porsiTunai({
          'payment_method': 'split',
          'final_amount': 100000,
          'payments': [
            {
              'payment_method': 'Tunai',
              'payment_type': 'cash',
              'amount': 30000,
            },
            {'payment_method': 'QRIS', 'payment_type': 'qris', 'amount': 70000},
          ],
        }, _tunai),
        30000,
      );
    });
  });

  group('milik shift', () {
    const online = (remoteId: 'SHIFT-1', localShiftId: null, clientRef: null);
    const offline = (
      remoteId: null,
      localShiftId: 'localshift_1',
      clientRef: 'osr_1',
    );

    test('op kas/pelunasan', () {
      expect(
        opMilikShift(_op(opKas, {}, serverShiftId: 'SHIFT-1'), online),
        isTrue,
      );
      expect(
        opMilikShift(_op(opKas, {}, serverShiftId: 'SHIFT-2'), online),
        isFalse,
      );
      expect(
        opMilikShift(_op(opKas, {}, localShiftId: 'localshift_1'), offline),
        isTrue,
      );
      // Buka-nya sudah terkirim: op mendapat server_shift_id, shift di
      // perangkat masih versi lokal — tetap dikenali lewat open client ref.
      expect(
        opMilikShift(
          _op(opLunas, {'shift_client_ref': 'osr_1'}, serverShiftId: 'SHIFT-9'),
          offline,
        ),
        isTrue,
      );
    });

    test('penjualan antrian', () {
      expect(penjualanMilikShift({'shift_id': 'SHIFT-1'}, online), isTrue);
      expect(
        penjualanMilikShift({
          'shift_client_ref': 'osr_1',
          'shift_id': '',
        }, offline),
        isTrue,
      );
      expect(
        penjualanMilikShift({'shift_id': '', 'shift_client_ref': ''}, online),
        isFalse,
      );
    });
  });

  group('ekspektasi kas tutup shift', () {
    test(
      'shift online lalu internet putus: penjualan & kas offline ikut terhitung',
      () {
        const k = (remoteId: 'SHIFT-1', localShiftId: null, clientRef: null);
        final r = hitungRingkasanKas(
          shift: k,
          modalAwal: 200000,
          penjualanTunaiServer: 500000, // sudah sampai di server
          kasServer: [
            {'type': 'out', 'amount': 20000},
          ],
          penjualanAntrian: [
            {
              'shift_id': 'SHIFT-1',
              'payment_method': 'Tunai',
              'final_amount': 75000,
            },
            {
              'shift_id': 'SHIFT-1',
              'payment_method': 'QRIS',
              'final_amount': 40000,
            },
            // Shift lain di perangkat yang sama — tak boleh ikut.
            {
              'shift_id': 'SHIFT-0',
              'payment_method': 'Tunai',
              'final_amount': 99000,
            },
          ],
          kasAntrian: [
            _op(opKas, {
              'type': 'out',
              'amount': 15000,
            }, serverShiftId: 'SHIFT-1'),
          ],
          lunasAntrian: [
            _op(opLunas, {'porsi_tunai': 60000}, serverShiftId: 'SHIFT-1'),
          ],
          tunai: _tunai,
        );
        expect(r.penjualanTunai, 500000 + 75000 + 60000);
        expect(r.kasKeluar, 35000);
        expect(r.ekspektasi, 200000 + 635000 - 35000);
        expect(r.belumTerkirim, 4);
      },
    );

    test('shift dibuka offline: ekspektasi tetap ada (dulu kosong)', () {
      const k = (
        remoteId: null,
        localShiftId: 'localshift_1',
        clientRef: 'osr_1',
      );
      final r = hitungRingkasanKas(
        shift: k,
        modalAwal: 100000,
        penjualanTunaiServer: 0,
        kasServer: const [],
        penjualanAntrian: [
          {
            'shift_client_ref': 'osr_1',
            'payment_method': 'Tunai',
            'final_amount': 45000,
          },
        ],
        kasAntrian: [
          _op(opKas, {
            'type': 'in',
            'amount': 50000,
          }, localShiftId: 'localshift_1'),
        ],
        lunasAntrian: const [],
        tunai: _tunai,
      );
      expect(r.ekspektasi, 195000);
    });

    test('kas yang gagal terkirim tetap terhitung — uangnya sudah keluar', () {
      const k = (remoteId: 'SHIFT-1', localShiftId: null, clientRef: null);
      final r = hitungRingkasanKas(
        shift: k,
        modalAwal: 0,
        penjualanTunaiServer: 0,
        kasServer: const [],
        penjualanAntrian: const [],
        kasAntrian: [
          _op(
            opKas,
            {'type': 'out', 'amount': 5000},
            serverShiftId: 'SHIFT-1',
            status: 'dead',
          ),
        ],
        lunasAntrian: const [],
        tunai: _tunai,
      );
      expect(r.ekspektasi, -5000);
    });
  });

  group('pelunasan di perangkat', () {
    test(
      'tagihan yang dilunasi offline dikenali, termasuk penjualan offline',
      () {
        final ids = idDilunasiDi([
          _op(opLunas, {
            'transaction_ids': ['TRX-1', 'offline_abc'],
          }),
          _op(opLunas, {
            'transaction_ids': ['TRX-2'],
          }),
        ]);
        expect(ids, {'TRX-1', 'offline_abc', 'TRX-2'});
      },
    );

    test('tampil lunas & menunggu terkirim', () {
      final s = tandaiLunasLokal(
        Sale.fromJson({
          'id': 'TRX-1',
          'created_at': '2026-10-29T03:00:00Z',
          'final_amount': 10000,
          'payment_status': 'unpaid',
          'is_paid': false,
        }),
      );
      expect(s.isUnpaid, isFalse);
      expect(s.isPaid, isTrue);
      expect(s.isUnpaid, isFalse, reason: 'tak boleh ditagih lagi di tab meja');
      expect(s.pendingSync, isTrue);
    });
  });
}
