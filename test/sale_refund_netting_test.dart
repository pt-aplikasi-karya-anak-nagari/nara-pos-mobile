import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/transactions/domain/sale.dart';
import 'package:nara_pos_mobile/features/transactions/domain/sale_item.dart';
import 'package:nara_pos_mobile/features/laporan/data/export_service.dart';

// Aturan netting retur di sisi mobile. Ini logika UANG, dan harus memberi angka
// yang SAMA dengan server (nara-pos-be/internal/report/refund_netting.go) —
// kalau tidak, kasir dan owner melihat dua angka berbeda untuk hari yang sama.
//
// Retur TIDAK mengubah `total` (nilai jual asli dipertahankan server); yang
// dikembalikan dicatat terpisah di `refundedAmount` dan `SaleItem.refundedQty`.
// Jadi setiap agregasi omzet/qty WAJIB lewat netTotal/netQty.

Sale _sale({
  required double total,
  double refundedAmount = 0,
  bool isRefunded = false,
  bool isPartiallyRefunded = false,
  bool isPaid = true,
  List<SaleItem> items = const [],
}) =>
    Sale(
      createdAt: DateTime(2026, 7, 20),
      subtotal: total,
      tax: 0,
      total: total,
      paymentMethod: 'Tunai',
      isPaid: isPaid,
      isRefunded: isRefunded,
      isPartiallyRefunded: isPartiallyRefunded,
      refundedAmount: refundedAmount,
    )..items = List<SaleItem>.from(items);

SaleItem _item({required int qty, required int refundedQty}) => SaleItem(
      productName: 'Kopi',
      productEmoji: '',
      qty: qty,
      price: 50000,
      refundedQty: refundedQty,
    );

void main() {
  group('Sale.netTotal', () {
    test('struk lunas penuh tidak berubah', () {
      expect(_sale(total: 100000).netTotal, 100000);
    });

    test('retur sebagian menyisakan porsi yang benar-benar dibayar', () {
      // Inti bug: struk 100rb yang diretur 40rb dulu dihitung 100rb penuh di
      // agregasi offline, padahal server melaporkan 60rb.
      final s = _sale(
        total: 100000,
        refundedAmount: 40000,
        isPartiallyRefunded: true,
      );
      expect(s.netTotal, 60000);
    });

    test('retur penuh bernilai nol walau kolom refundedAmount masih 0', () {
      // Struk yang diretur lewat jalur lama menyimpan 0 di refunded_amount.
      // Mengandalkan kolom itu akan menghitungnya sebagai omzet PENUH.
      expect(_sale(total: 100000, isRefunded: true, isPaid: false).netTotal, 0);
      expect(
        _sale(total: 100000, refundedAmount: 100000, isRefunded: true, isPaid: false).netTotal,
        0,
      );
    });

    test('akumulasi pembulatan tidak membuat omzet negatif', () {
      final s = _sale(
        total: 100000,
        refundedAmount: 100003,
        isPartiallyRefunded: true,
      );
      expect(s.netTotal, 0);
    });

    test('retur kecil tidak menghapus seluruh struk', () {
      // Faktor kesalahan rumus lama berbanding TERBALIK dengan besar retur.
      final s = _sale(
        total: 1000000,
        refundedAmount: 10000,
        isPartiallyRefunded: true,
      );
      expect(s.netTotal, 990000);
    });
  });

  group('Sale.netQty', () {
    test('unit yang diretur tidak dihitung terjual', () {
      final s = _sale(
        total: 500000,
        refundedAmount: 200000,
        isPartiallyRefunded: true,
        items: [_item(qty: 10, refundedQty: 4)],
      );
      expect(s.netQty, 6);
      expect(s.totalQty, 10, reason: 'totalQty tetap kuantitas asli');
    });

    test('retur penuh bernilai nol', () {
      final s = _sale(
        total: 500000,
        isRefunded: true,
        isPaid: false,
        items: [_item(qty: 10, refundedQty: 0)],
      );
      expect(s.netQty, 0,
          reason: 'struk lama yang diretur penuh punya refundedQty 0');
    });

    test('beberapa baris item dijumlahkan', () {
      final s = _sale(
        total: 300000,
        isPartiallyRefunded: true,
        items: [_item(qty: 5, refundedQty: 2), _item(qty: 3, refundedQty: 3)],
      );
      expect(s.netQty, 3);
    });
  });

  group('Sale.countsAsSale', () {
    test('retur sebagian tetap dihitung sebagai transaksi', () {
      // Pelanggannya nyata dan tetap membayar sesuatu.
      expect(_sale(total: 100000, isPartiallyRefunded: true, isPaid: false).countsAsSale, true);
    });

    test('retur penuh tidak dihitung sebagai transaksi', () {
      expect(_sale(total: 100000, isRefunded: true, isPaid: false).countsAsSale,
          false);
    });

    test('bill yang belum dibayar tidak dihitung sebagai omzet', () {
      // Riwayat dari server memuat SEMUA status karena mobile memanggilnya
      // tanpa filter; predikat `!isRefunded` saja akan meloloskan bill ini.
      expect(_sale(total: 100000, isPaid: false).countsAsSale, false);
    });

    test('struk offline yang sudah dibayar tetap dihitung', () {
      // Transaksi yang dibuat offline men-set isPaid true di klien walau
      // paymentStatus lokalnya belum tersinkron; ia harus tetap masuk omzet.
      final s = _sale(total: 100000, isPaid: true)..pendingSync = true;
      expect(s.countsAsSale, true);
    });
  });

  _mainEkspor();

  // Invariant yang sama dikunci di sisi server: omzet + retur harus kembali ke
  // nilai jual asli, kalau tidak laporan tak bisa direkonsiliasi dengan struk.
  //
  // Nilai retur yang diharapkan ditulis EKSPLISIT, tidak diturunkan dari
  // netTotal. Kalau diturunkan (`diretur = total - netTotal`), penjumlahannya
  // selalu kembali ke total apa pun isi netTotal — tautologi yang tetap lulus
  // walau implementasinya mengembalikan angka asal.
  test('netTotal + nilai yang diretur = nilai jual asli', () {
    final kasus = <({Sale sale, double returDiharapkan})>[
      (sale: _sale(total: 100000), returDiharapkan: 0),
      (
        sale: _sale(
          total: 100000,
          refundedAmount: 40000,
          isPartiallyRefunded: true,
          isPaid: false,
        ),
        returDiharapkan: 40000,
      ),
      (
        sale: _sale(
          total: 100000,
          refundedAmount: 100000,
          isRefunded: true,
          isPaid: false,
        ),
        returDiharapkan: 100000,
      ),
      // Struk warisan: kolom refundedAmount masih 0, tapi seluruh nilainya
      // memang sudah dikembalikan.
      (
        sale: _sale(total: 100000, isRefunded: true, isPaid: false),
        returDiharapkan: 100000,
      ),
    ];
    for (final k in kasus) {
      expect(
        k.sale.netTotal + k.returDiharapkan,
        closeTo(k.sale.total, 0.01),
        reason: 'netTotal=${k.sale.netTotal} retur=${k.returDiharapkan}',
      );
    }
  });
}

// ── Agregat turunan di ekspor (top produk & kinerja kasir) ──────────────
//
// Dokumen ekspor sudah punya kolom "Total Bersih" per baris; kalau tabel
// turunannya masih memakai kuantitas/nilai bruto, satu dokumen yang sama
// memuat dua angka yang saling bertentangan.

void _mainEkspor() {
  group('computeTopProducts', () {
    test('unit yang diretur tidak dihitung terjual', () {
      final s = _sale(
        total: 150000,
        refundedAmount: 50000,
        isPartiallyRefunded: true,
        isPaid: false,
        items: [_item(qty: 3, refundedQty: 1)],
      );
      final top = computeTopProducts([s]);
      expect(top.single.qty, 2);
      expect(top.single.revenue, 100000, reason: 'price 50rb × 2 unit tersisa');
    });

    test('struk yang diretur penuh tidak muncul sama sekali', () {
      final s = _sale(
        total: 150000,
        isRefunded: true,
        isPaid: false,
        items: [_item(qty: 3, refundedQty: 3)],
      );
      expect(computeTopProducts([s]), isEmpty);
    });

    test('bill belum dibayar tidak dihitung terjual', () {
      final s = _sale(
        total: 150000,
        isPaid: false,
        items: [_item(qty: 3, refundedQty: 0)],
      );
      expect(computeTopProducts([s]), isEmpty);
    });
  });

  group('computeCashierSummaries', () {
    test('omzet kasir dihitung bersih', () {
      final s = _sale(
        total: 1000000,
        refundedAmount: 400000,
        isPartiallyRefunded: true,
        isPaid: false,
        items: [_item(qty: 10, refundedQty: 4)],
      );
      final rows = computeCashierSummaries([s]);
      expect(rows.single.revenue, 600000);
      expect(rows.single.itemsSold, 6);
      expect(rows.single.transactions, 1,
          reason: 'struk retur sebagian tetap satu transaksi');
    });
  });

  group('ExportService.refundLabel', () {
    test('tiga arah, bukan dua', () {
      expect(ExportService.refundLabel(_sale(total: 1)), 'Normal');
      expect(
        ExportService.refundLabel(
            _sale(total: 1, isPartiallyRefunded: true, isPaid: false)),
        'Retur sebagian',
      );
      expect(
        ExportService.refundLabel(
            _sale(total: 1, isRefunded: true, isPaid: false)),
        'Refund',
      );
    });
  });
}
