import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/transactions/domain/sale.dart';

// Struk daring mencetak Subtotal PASCA-diskon lalu menguranginya lagi.
//
// # KEJADIANNYA
//
// Sale.fromJson menyalin subtotal_amount ke originalSubtotal. Tapi
// subtotal_amount dari server SUDAH pasca-diskon baris — kasir mengirimkannya
// sebagai Σ effectivePrice × qty.
//
// Struk lalu mencetak angka itu di baris "Subtotal" dan MENGURANGI Total Diskon
// di baris berikutnya, jadi penjumlahannya tak nyambung: pelanggan yang
// menghitung sendiri tidak akan ketemu.
//
// # YANG MEMBUATNYA ANEH
//
// Struk yang SAMA tercetak berbeda tergantung koneksi. Jalur luring mengisi
// field ini dari originalSubtotalProvider yang memang pra-diskon; hanya jalur
// daring yang salah. Cetak ulang dari riwayat ikut terkena.
//
// # YANG DIJAGA
//
// Bukan "originalSubtotal lebih besar", melainkan ARITMETIKANYA TERTUTUP:
//   Subtotal − Diskon + Layanan + Pajak = TOTAL

Map<String, dynamic> _payload({
  required double subtotal,
  required double diskonHeader,
  required double diskonBaris,
  double pajak = 0,
  double layanan = 0,
  required double total,
  bool denganItem = true,
}) => {
      'id': 'TRX1',
      'subtotal_amount': subtotal,
      'discount_amount': diskonHeader,
      'tax_amount': pajak,
      'service_charge': layanan,
      'final_amount': total,
      if (denganItem)
        'items': [
          {
            'product_name': 'Kopi',
            'quantity': 1,
            'price_at_time': subtotal,
            'original_price': subtotal + diskonBaris,
            'discount_amount': diskonBaris,
          },
        ],
    };

void main() {
  test('Subtotal di struk adalah PRA-diskon', () {
    // 1 item Rp100.000, diskon baris 10%. Server menyimpan subtotal 90.000.
    final s = Sale.fromJson(_payload(
      subtotal: 90000,
      diskonHeader: 10000,
      diskonBaris: 10000,
      total: 90000,
    ));

    expect(
      s.originalSubtotal,
      100000,
      reason: 'struk mencetak 90.000 lalu mengurangi diskon 10.000 lagi — '
          'pelanggan melihat penjumlahan yang tidak nyambung',
    );
  });

  test('aritmetika struk tertutup: Subtotal − Diskon + Layanan + Pajak = TOTAL', () {
    // Inti seluruh perbaikan. Angka apa pun boleh, asal ketiga barisnya
    // konsisten satu sama lain.
    final s = Sale.fromJson(_payload(
      subtotal: 90000,
      diskonHeader: 10000,
      diskonBaris: 10000,
      layanan: 4500,
      pajak: 9900,
      total: 104400,
    ));

    final hasil = s.originalSubtotal - s.discountTotal + s.serviceCharge + s.tax;
    expect(hasil, s.total,
        reason: 'Subtotal ${s.originalSubtotal} − Diskon ${s.discountTotal} '
            '+ Layanan ${s.serviceCharge} + Pajak ${s.tax} = $hasil, '
            'tapi TOTAL tertulis ${s.total}');
  });

  test('promo order-level ikut benar — bukan cuma diskon baris', () {
    // discount_amount header memuat diskon baris (10.000) DAN promo (5.000).
    // Yang ditambahkan kembali ke Subtotal hanya bagian barisnya.
    final s = Sale.fromJson(_payload(
      subtotal: 90000,
      diskonHeader: 15000,
      diskonBaris: 10000,
      total: 85000,
    ));

    expect(s.originalSubtotal, 100000);
    expect(s.originalSubtotal - s.discountTotal, s.total);
  });

  test('tanpa diskon apa pun, Subtotal tetap sama seperti sebelumnya', () {
    // Mayoritas transaksi. Perbaikan yang menggeser angka di sini akan mengubah
    // struk yang selama ini sudah benar.
    final s = Sale.fromJson(_payload(
      subtotal: 50000,
      diskonHeader: 0,
      diskonBaris: 0,
      total: 50000,
    ));

    expect(s.originalSubtotal, 50000);
  });

  test('respons TANPA items tidak dipaksa dihitung', () {
    // Endpoint DAFTAR transaksi tak mengirim items. Merekonstruksi dari daftar
    // kosong akan menghasilkan Subtotal = subtotal apa adanya — perilaku lama,
    // dan di sana struknya memang tak dicetak.
    final s = Sale.fromJson(_payload(
      subtotal: 90000,
      diskonHeader: 10000,
      diskonBaris: 10000,
      total: 90000,
      denganItem: false,
    ));

    expect(s.originalSubtotal, 90000);
  });
}
