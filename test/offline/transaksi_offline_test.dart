import 'package:flutter_test/flutter_test.dart';

import 'package:nara_pos_mobile/core/offline/sale_outbox.dart';
import 'package:nara_pos_mobile/features/transactions/data/transaction_repository.dart';
import 'package:nara_pos_mobile/features/transactions/data/transaksi_offline.dart';
import 'package:nara_pos_mobile/features/transactions/domain/sale.dart';

PendingSale antrian({Map<String, dynamic>? struk, String? galat}) =>
    PendingSale(
      localId: 'offline_1',
      outletId: 'o1',
      createdAt: DateTime(2026, 10, 29, 9),
      attempts: galat == null ? 0 : 5,
      lastError: galat,
      payload: {
        'payment_method': 'Tunai',
        'occurred_at': '2026-10-29T02:15:00Z',
        'subtotal_amount': 37000,
        'tax_amount': 3700,
        'final_amount': 40700,
        'cash_amount': 50000,
        'change_amount': 9300,
        'customer_name': 'Rina',
        'order_type': 'Take Away',
        'is_paid': true,
        'offline_ref': 'OFF-3FA9C2-00042',
        'cashier_id': 'kasir-A',
        'items': [
          {
            'product_id': 'p1',
            'quantity': 2,
            'name': 'Teh Telur (Large)',
            'price': 15000,
            'base_price': 12000,
          },
          {
            'product_id': 'p2',
            'quantity': 1,
            'name': 'Air',
            'price': 7000,
            'base_price': 7000,
          },
        ],
        'struk_lokal': ?struk,
      },
    );

void main() {
  group('struk dari antrian offline', () {
    test('lengkap dengan data struk lokal', () {
      final s = saleDariAntrian(
        antrian(
          struk: {
            'cashier_name': 'Kasir A',
            'outlet_name': 'Febriqgal Coffee',
            'original_subtotal': 31000,
            'items': [
              {
                'product_name': 'Teh Telur',
                'variant': 'Large',
                'emoji': '🍵',
                'original_price': 12000,
                'modifiers_label': 'Boba',
              },
              {
                'product_name': 'Air',
                'variant': '',
                'emoji': '💧',
                'original_price': 7000,
                'modifiers_label': '',
              },
            ],
          },
        ),
      );
      expect(s.invoiceId, 'OFF-3FA9C2-00042');
      expect(s.pendingSync, isTrue);
      expect(s.gagalTerkirim, isFalse);
      expect(s.total, 40700);
      expect(s.cashierName, 'Kasir A');
      expect(s.outletName, 'Febriqgal Coffee');
      expect(s.orderType, 'Take Away');
      expect(s.items.first.productName, 'Teh Telur');
      expect(s.items.first.variant, 'Large');
      expect(s.items.first.modifiersLabel, 'Boba');
      expect(s.items.first.qty, 2);
    });

    test('antrian lama tanpa data struk tetap tampil', () {
      final s = saleDariAntrian(antrian());
      expect(s.items.first.productName, 'Teh Telur (Large)');
      expect(s.items.first.originalPrice, 12000);
      expect(s.originalSubtotal, 37000);
    });

    test('yang ditolak server membawa alasannya', () {
      final s = saleDariAntrian(antrian(galat: 'Stok habis'), gagal: true);
      expect(s.gagalTerkirim, isTrue);
      expect(s.galatSinkron, 'Stok habis');
    });

    test('ID offline dikenali', () {
      expect(SaleOutbox.idOffline(SaleOutbox.idLokalBaru()), isTrue);
      expect(SaleOutbox.idOffline('TRX-000123'), isFalse);
    });
  });

  group('riwayat tersimpan saat offline', () {
    Sale sale(
      String inv,
      String pelanggan,
      DateTime t, {
      String status = 'paid',
    }) => Sale(
      createdAt: t,
      subtotal: 1,
      tax: 0,
      total: 1,
      paymentMethod: 'Tunai',
      invoiceId: inv,
      customerName: pelanggan,
      isPaid: status == 'paid',
      paymentStatus: status,
    );

    final semua = [
      sale('INV-1', 'Rina', DateTime(2026, 10, 27, 10)),
      sale('INV-2', 'Budi', DateTime(2026, 10, 28, 23, 30), status: 'unpaid'),
      sale('INV-3', 'Sari', DateTime(2026, 10, 29, 8)),
    ];

    test('urut terbaru dulu', () {
      expect(saringRiwayatTersimpan(semua).map((s) => s.invoiceId), [
        'INV-3',
        'INV-2',
        'INV-1',
      ]);
    });

    test('cari invoice atau pelanggan', () {
      expect(
        saringRiwayatTersimpan(semua, cari: 'budi').single.invoiceId,
        'INV-2',
      );
      expect(
        saringRiwayatTersimpan(semua, cari: 'inv-3').single.invoiceId,
        'INV-3',
      );
    });

    test('status', () {
      expect(
        saringRiwayatTersimpan(semua, status: 'unpaid').single.invoiceId,
        'INV-2',
      );
      expect(saringRiwayatTersimpan(semua, status: 'paid').length, 2);
    });

    test('rentang tanggal inklusif sampai akhir hari', () {
      final hasil = saringRiwayatTersimpan(
        semua,
        dari: DateTime(2026, 10, 28),
        sampai: DateTime(2026, 10, 28),
      );
      expect(hasil.single.invoiceId, 'INV-2', reason: '23:30 masih hari itu');
    });
  });
}
