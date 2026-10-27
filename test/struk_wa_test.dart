import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/customers/domain/customer.dart';
import 'package:nara_pos_mobile/features/transactions/domain/sale.dart';
import 'package:nara_pos_mobile/features/transactions/domain/struk_wa.dart';

// Kirim struk digital via WhatsApp dari detail transaksi.

Sale _sale({
  bool isPaid = true,
  bool partial = false,
  bool pendingSync = false,
  String customerPhone = '',
  Customer? customer,
}) => Sale(
  createdAt: DateTime(2026, 10, 27),
  subtotal: 50000,
  tax: 0,
  total: 50000,
  paymentMethod: 'Tunai',
  isPaid: isPaid,
  isPartiallyRefunded: partial,
  customerPhone: customerPhone,
  pendingSync: pendingSync,
)..customer = customer;

void main() {
  group('nomor awal', () {
    test('HP di transaksi lebih dulu, lalu HP pelanggan terdaftar', () {
      final pelanggan = Customer(name: 'Andi', phone: '0899');
      expect(
        nomorAwalStrukWa(_sale(customerPhone: ' 0812 ', customer: pelanggan)),
        '0812',
      );
      expect(nomorAwalStrukWa(_sale(customer: pelanggan)), '0899');
      expect(nomorAwalStrukWa(_sale()), '');
    });
  });

  group('normalisasi nomor (sama dengan backend)', () {
    test('format umum Indonesia diterima', () {
      expect(normalkanNomorWa('0812-3456-7890'), '6281234567890');
      expect(normalkanNomorWa('+62 812 3456 789'), '628123456789');
      expect(normalkanNomorWa('81234567890'), '6281234567890');
    });
    test('nomor tak wajar ditolak', () {
      for (final salah in ['', '0812', '+1 415 555 0100', 'abc']) {
        expect(normalkanNomorWa(salah), isNull, reason: salah);
      }
    });
  });

  group('kapan tombol tampil', () {
    test('lunas atau diretur sebagian', () {
      expect(bisaKirimStrukWa(_sale()), isTrue);
      expect(bisaKirimStrukWa(_sale(isPaid: false, partial: true)), isTrue);
    });
    test('belum lunas atau masih offline', () {
      expect(bisaKirimStrukWa(_sale(isPaid: false)), isFalse);
      expect(bisaKirimStrukWa(_sale(pendingSync: true)), isFalse);
    });
  });
}
