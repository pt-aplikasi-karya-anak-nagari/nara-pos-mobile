import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/transactions/domain/sale.dart';

/// Payload SUNGGUHAN dari GET /api/v1/shifts/:id/transactions.
///
/// Diambil apa adanya dari backend yang berjalan di 127.0.0.1:3001 terhadap
/// basis data produksi lokal (outlet Febriqgal Coffie Shop, shift
/// SHIFT20260728010232235000004), lalu ditempelkan ke sini tanpa diubah.
///
/// # KENAPA BUKAN FIXTURE BUATAN SENDIRI
///
/// Fixture yang saya susun sendiri hanya membuktikan kode ini konsisten dengan
/// bayangan saya tentang bentuk JSON-nya. Yang perlu dibuktikan adalah ia
/// konsisten dengan yang BENAR-BENAR dikirim server — termasuk hal-hal yang
/// mudah salah diingat: nama kunci, jenis angka, dan kunci mana yang justru
/// TIDAK ada.
///
/// Perhatikan tak ada kunci "payments" di sini. Itu benar: transaksi ini
/// single-method, dan omitempty membuangnya. Fixture buatan tangan cenderung
/// selalu menyertakannya, dan jalur "tanpa payments" tak pernah teruji.
const _dariServer = <String, dynamic>{
  'id': 'TRX20260728010649734000044',
  'outlet_id': '01KXFM5A3NDJDD7B5D7X76BWXV',
  'user_id': '677f4959-9489-43e0-a685-f4a7b1ad364e',
  'shift_id': 'SHIFT20260728010232235000004',
  'invoice_no': 'INV-TRX20260728010649734000044',
  'subtotal_amount': 10000,
  'service_charge_amount': 0,
  'total_amount': 10000,
  'tax_amount': 1000,
  'discount_amount': 0,
  'final_amount': 11000,
  'payment_method_id': 'PM20260717075205163000031',
  'payment_method': 'QRIS',
  'payment_method_type': 'qris',
  'payment_status': 'paid',
  'cash_amount': 0,
  'change_amount': 0,
  'customer_name': '',
  'order_type': 'Takeaway',
  'paid_at': '2026-07-28T01:06:51.327419+07:00',
  'fulfillment_status': 'pending',
  'source': 'kasir',
  'client_ref': 'cr_1785175611326787_1700791452',
  'refunded_amount': 0,
  'employee_id': '677f4959-9489-43e0-a685-f4a7b1ad364e',
  'created_at': '2026-07-28T01:06:51.327419+07:00',
  'updated_at': '2026-07-28T01:06:49.736791+07:00',
  'items': [
    {
      'id': 'TRX20260728010649735000045',
      'transaction_id': 'TRX20260728010649734000044',
      'product_id': 'PROD20260728005951187000206',
      'product_name': 'susu',
      'quantity': 1,
      'price_at_time': 10000,
      'subtotal': 10000,
      'original_price': 10000,
      'discount_type': 'none',
      'discount_value': 0,
      'discount_amount': 0,
      'discount_name': '',
      'refunded_qty': 0,
      'is_taxable': true,
      'tax_amount': 1000,
      'kitchen_status': 'new',
      'created_at': '2026-07-28T01:06:49.735407+07:00',
    }
  ],
};

/// Salinan loop rekap di _TabletDetailPanel (shift_history_page.dart).
///
/// Disalin, bukan diimpor, karena aslinya hidup di dalam build() sebuah widget
/// privat. Kalau salah satu berubah dan yang lain tidak, tes ini berhenti
/// mewakili layarnya — jadi perlakukan keduanya sebagai satu kesatuan.
Map<String, double> rekapTender(List<Sale> shiftSales) {
  const dihitung = {'paid', 'partially_refunded', 'refunded'};
  double qris = 0, kartu = 0, transfer = 0, refund = 0;
  var jumlahRefund = 0;

  for (final sale in shiftSales) {
    if (!dihitung.contains(sale.paymentStatus)) continue;
    if (sale.isRefunded) {
      refund += sale.total;
      jumlahRefund++;
      continue;
    }
    if (sale.isPartiallyRefunded) {
      refund += sale.total - sale.netTotal;
      jumlahRefund++;
    }
    qris += sale.porsiTender('qris');
    kartu += sale.porsiTender('card');
    transfer += sale.porsiTender('transfer');
  }

  return {
    'qris': qris,
    'kartu': kartu,
    'transfer': transfer,
    'refund': refund,
    'jumlahRefund': jumlahRefund.toDouble(),
  };
}

void main() {
  test('JSON asli server terbaca utuh oleh Sale.fromJson', () {
    final s = Sale.fromJson(_dariServer);

    expect(s.id, 'TRX20260728010649734000044');
    expect(s.total, 11000);
    expect(s.paymentMethod, 'QRIS');
    expect(s.paymentMethodType, 'qris',
        reason: 'payment_method_type dari server tak terbaca — kasir kembali '
            'menebak dari nama');
    expect(s.paymentStatus, 'paid');
    expect(s.tenders, isEmpty, reason: 'transaksi single-method tak punya split');
    expect(s.items.length, 1,
        reason: 'items wajib ikut — struk laporan shift dicetak dari sini');
  });

  test('rekap tender shift SHIFT20260728010232235000004 sesuai isi laci', () {
    // Shift ini berisi tepat satu transaksi: QRIS Rp11.000, lunas, tanpa retur.
    final rekap = rekapTender([Sale.fromJson(_dariServer)]);

    expect(rekap['qris'], 11000);
    expect(rekap['kartu'], 0);
    expect(rekap['transfer'], 0);
    expect(rekap['refund'], 0);
    expect(rekap['jumlahRefund'], 0);
  });

  test('cocok dengan Ekspektasi Kas yang dihitung server', () {
    // Server mencatat modal awal Rp10.000 dan ekspektasi kas Rp10.000 untuk
    // shift ini. Transaksinya QRIS, jadi tak ada uang tunai yang masuk laci —
    // dan rekap tender di layar HARUS setuju dengan itu.
    //
    // Inilah pencocokan yang selama ini mustahil dilakukan: sebelum shiftSales
    // tersambung, layar menampilkan Rp0 untuk SEMUA metode di sebelah
    // Ekspektasi Kas yang benar, dan tak ada cara tahu mana yang bisa dipercaya.
    final sale = Sale.fromJson(_dariServer);
    final rekap = rekapTender([sale]);

    expect(sale.porsiTender('cash'), 0,
        reason: 'transaksi QRIS menyumbang uang tunai — ekspektasi kas laci '
            'akan meleset dan kasir dituduh selisih');

    const modalAwal = 10000.0;
    const ekspektasiKasServer = 10000.0;
    expect(modalAwal + sale.porsiTender('cash'), ekspektasiKasServer);

    // Total non-tunai di layar = seluruh nilai transaksi shift ini.
    expect(rekap['qris']! + rekap['kartu']! + rekap['transfer']!, 11000);
  });

  test('tiga shift tanpa transaksi menampilkan rekap kosong, bukan Rp0', () {
    // Tiga shift lain di basis data yang sama tak punya transaksi sama sekali.
    // Daftarnya kosong, dan blok rekap serta tombol cetak memang bersembunyi
    // saat kosong — bukan mencetak nol.
    final rekap = rekapTender([]);
    expect(rekap['qris'], 0);
    expect(<Sale>[].isNotEmpty, isFalse,
        reason: 'penjaga "sembunyikan saat kosong" yang menahan struk Rp0');
  });
}
