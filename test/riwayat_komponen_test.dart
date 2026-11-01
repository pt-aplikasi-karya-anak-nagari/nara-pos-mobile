import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/transactions/data/transaction_repository.dart';
import 'package:nara_pos_mobile/features/transactions/domain/sale.dart';
import 'package:nara_pos_mobile/features/transactions/domain/sale_item.dart';
import 'package:nara_pos_mobile/features/transactions/ui/widgets/riwayat_komponen.dart';

Sale jual({
  String nama = '',
  int? antrian,
  List<(int, String)> items = const [],
  String status = 'paid',
}) {
  final s = Sale(
    createdAt: DateTime(2026, 11, 1, 10, 31),
    subtotal: 0,
    tax: 0,
    total: 0,
    paymentMethod: 'Tunai',
    customerName: nama,
    queueNo: antrian,
    paymentStatus: status,
    isPaid: status == 'paid',
  );
  s.items = [
    for (final it in items)
      SaleItem(productName: it.$2, productEmoji: '', price: 1, qty: it.$1),
  ];
  return s;
}

void main() {
  test('judul: nama pelanggan → antrian → pelanggan umum', () {
    expect(judulTransaksi(jual(nama: 'Rina', antrian: 8)), 'Rina');
    expect(judulTransaksi(jual(antrian: 9)), 'Antrian 009');
    expect(judulTransaksi(jual()), 'Pelanggan umum');
  });

  test('ringkasan item dipotong dua baris + sisa', () {
    expect(ringkasItem(jual(items: [(1, 'Kopi')])), '1× Kopi');
    expect(
      ringkasItem(
        jual(items: [(2, 'Nasi'), (2, 'Teh'), (1, 'Kentang'), (1, 'Roti')]),
      ),
      '2× Nasi, 2× Teh +2 lainnya',
    );
    expect(ringkasItem(jual()), '');
  });

  test('status kartu', () {
    expect(statusTransaksi(jual()).label, 'Lunas');
    expect(statusTransaksi(jual(status: 'unpaid')).label, 'Belum bayar');
    expect(statusTransaksi(jual(status: 'cancelled')).label, 'Dibatalkan');
    final retur = jual(status: 'refunded')..isRefunded = true;
    expect(statusTransaksi(retur).label, 'Diretur');
  });

  test('label tanggal: hari ini, kemarin, lalu tanggal lengkap', () {
    final now = DateTime(2026, 11, 1, 13, 0);
    expect(
      labelTanggalRiwayat(DateTime(2026, 11, 1, 8), sekarang: now),
      'Hari ini',
    );
    expect(
      labelTanggalRiwayat(DateTime(2026, 10, 31, 23), sekarang: now),
      'Kemarin',
    );
    expect(
      labelTanggalRiwayat(DateTime(2026, 10, 29, 9), sekarang: now),
      'Kam, 29 Okt 2026',
    );
    expect(
      hariSama(DateTime(2026, 11, 1, 1), DateTime(2026, 11, 1, 23)),
      isTrue,
    );
  });

  test('ringkasan riwayat dari JSON server', () {
    final r = RingkasanRiwayat.fromJson({
      'total_transactions': 9,
      'total_revenue': 248955,
      'average_ticket': 27661.5,
      'unpaid_count': 1,
      'refunded_count': 2,
    });
    expect(r.jumlah, 9);
    expect(r.omzet, 248955);
    expect(r.belumBayar, 1);
    expect(r.diretur, 2);
  });
}
