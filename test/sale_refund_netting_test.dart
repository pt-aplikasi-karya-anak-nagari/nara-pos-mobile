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

// cashierName / cashierRemoteId ditambahkan belakangan untuk menguji cabang
// penggabungan computeCashierSummaries. Keduanya opsional dan default-nya
// string kosong — sama persis dengan default Sale — jadi seluruh pemanggil
// lama tak berubah perilakunya.
Sale _sale({
  required double total,
  double refundedAmount = 0,
  bool isRefunded = false,
  bool isPartiallyRefunded = false,
  bool isPaid = true,
  List<SaleItem> items = const [],
  String cashierName = '',
  String cashierRemoteId = '',
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
      cashierName: cashierName,
      cashierRemoteId: cashierRemoteId,
    )..items = List<SaleItem>.from(items);

// productRemoteId / productName / productSku / price sama: opsional, dengan
// default yang identik dengan nilai yang dulu di-hardcode di sini.
SaleItem _item({
  required int qty,
  required int refundedQty,
  String productRemoteId = '',
  String productName = 'Kopi',
  String productSku = '',
  double price = 50000,
}) => SaleItem(
      productRemoteId: productRemoteId,
      productName: productName,
      productEmoji: '',
      productSku: productSku,
      qty: qty,
      price: price,
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

  // Cabang PENGGABUNGAN kedua fungsi agregasi. Tes di atas sudah mengunci sisi
  // netting returnya; yang di sini soal bagaimana baris dari struk-struk yang
  // berbeda dilebur jadi satu baris laporan.
  //
  // Kuncinya dipilih berjenjang: remote ID kalau ada, nama kalau tidak. Itu
  // dua cabang yang gagalnya berlawanan — kunci yang terlalu longgar melebur
  // dua produk berbeda jadi satu, kunci yang terlalu ketat memecah satu produk
  // jadi banyak baris. Keduanya sama-sama tak menimbulkan error.
  //
  // Catatan pelaksanaan: List.sort di Dart TIDAK dijamin stabil, jadi setiap
  // tes urutan di bawah memakai qty (dan omzet, untuk kasir) yang semuanya
  // BERBEDA. Data yang seri akan membuat tesnya berubah warna tanpa ada
  // perubahan kode sama sekali.
  group('computeTopProducts — penggabungan lintas struk', () {
    test('produk sama di dua struk jadi SATU baris', () {
      final hasil = computeTopProducts([
        _sale(
          total: 100000,
          items: [_item(qty: 2, refundedQty: 0, productRemoteId: 'P1')],
        ),
        _sale(
          total: 150000,
          items: [_item(qty: 3, refundedQty: 0, productRemoteId: 'P1')],
        ),
      ]);

      expect(hasil, hasLength(1));
      expect(hasil.first.qty, 5);
      expect(hasil.first.revenue, 250000); // 50.000 × 5
    });

    test('nama sama tapi ID berbeda TIDAK dilebur', () {
      // Dua gerai bisa punya "Kopi" masing-masing dengan ID sendiri. Meleburnya
      // membuat laporan produk terlaris salah, dan salahnya tak kelihatan
      // karena namanya memang sama.
      final hasil = computeTopProducts([
        _sale(
          total: 1,
          items: [
            _item(qty: 5, refundedQty: 0, productRemoteId: 'P1', productName: 'Kopi'),
            _item(qty: 2, refundedQty: 0, productRemoteId: 'P2', productName: 'Kopi'),
          ],
        ),
      ]);

      expect(hasil, hasLength(2));
      expect(hasil.map((e) => e.qty), [5, 2]); // terurut qty menurun
    });

    test('produk tanpa ID dilebur berdasar nama', () {
      // Produk kustom (ketik manual di kasir) tak punya remote ID. Tanpa
      // cadangan nama, tiap barisnya jadi baris laporan sendiri.
      final hasil = computeTopProducts([
        _sale(total: 1, items: [_item(qty: 2, refundedQty: 0, productName: 'Titipan')]),
        _sale(total: 1, items: [_item(qty: 4, refundedQty: 0, productName: 'Titipan')]),
      ]);

      expect(hasil, hasLength(1));
      expect(hasil.first.qty, 6);
    });

    test('produk tanpa ID dengan nama BERBEDA tetap terpisah', () {
      final hasil = computeTopProducts([
        _sale(
          total: 1,
          items: [
            _item(qty: 3, refundedQty: 0, productName: 'Titipan A'),
            _item(qty: 1, refundedQty: 0, productName: 'Titipan B'),
          ],
        ),
      ]);

      expect(hasil, hasLength(2));
    });

    test('SKU yang semula kosong terisi dari kemunculan berikutnya', () {
      // Struk lama bisa tak menyimpan SKU. Kalau baris pertama yang menang
      // mutlak, SKU-nya hilang selamanya dari laporan walau struk berikutnya
      // membawanya.
      final hasil = computeTopProducts([
        _sale(total: 1, items: [_item(qty: 1, refundedQty: 0, productRemoteId: 'P1')]),
        _sale(
          total: 1,
          items: [
            _item(qty: 1, refundedQty: 0, productRemoteId: 'P1', productSku: 'SKU-9'),
          ],
        ),
      ]);

      expect(hasil.first.sku, 'SKU-9');
    });

    test('terurut qty menurun dan dipotong di limit', () {
      // Sebelas produk dengan qty 1..11 — semuanya BERBEDA, supaya urutannya
      // tak bergantung pada kestabilan sort.
      final items = [
        for (var i = 1; i <= 11; i++)
          _item(qty: i, refundedQty: 0, productRemoteId: 'P$i'),
      ];
      final hasil = computeTopProducts([_sale(total: 1, items: items)]);

      expect(hasil, hasLength(10)); // limit default
      expect(hasil.first.qty, 11);
      expect(hasil.last.qty, 2);
      // Yang terkecil (qty 1) memang terpotong — bukan hilang karena bug.
      expect(hasil.map((e) => e.qty), isNot(contains(1)));
    });

    test('limit bisa dinaikkan dan semuanya ikut', () {
      final items = [
        for (var i = 1; i <= 11; i++)
          _item(qty: i, refundedQty: 0, productRemoteId: 'P$i'),
      ];
      expect(computeTopProducts([_sale(total: 1, items: items)], limit: 20), hasLength(11));
    });

    test('omzet memakai qty BERSIH, bukan qty asli', () {
      // Bertetangga dengan tes netting di atas, tapi mengunci sisi UANG-nya:
      // 5 terjual, 2 diretur → 3 × 50.000.
      final hasil = computeTopProducts([
        _sale(
          total: 250000,
          isPartiallyRefunded: true,
          refundedAmount: 100000,
          items: [_item(qty: 5, refundedQty: 2, productRemoteId: 'P1')],
        ),
      ]);

      expect(hasil.first.qty, 3);
      expect(hasil.first.revenue, 150000);
    });
  });

  group('computeCashierSummaries — penggabungan lintas struk', () {
    test('kasir sama di dua struk: transaksi dihitung, omzet dijumlah', () {
      final hasil = computeCashierSummaries([
        _sale(
          total: 100000,
          cashierRemoteId: 'K1',
          cashierName: 'putra',
          items: [_item(qty: 2, refundedQty: 0)],
        ),
        _sale(
          total: 50000,
          cashierRemoteId: 'K1',
          cashierName: 'putra',
          items: [_item(qty: 1, refundedQty: 0)],
        ),
      ]);

      expect(hasil, hasLength(1));
      expect(hasil.first.transactions, 2);
      expect(hasil.first.itemsSold, 3);
      expect(hasil.first.revenue, 150000);
    });

    test('nama berubah tapi ID sama tetap SATU kasir', () {
      // Nama bisa diperbaiki ejaannya di tengah jalan. Yang mengikat adalah
      // ID-nya; nama pertama yang dipakai untuk pelabelan.
      final hasil = computeCashierSummaries([
        _sale(total: 10000, cashierRemoteId: 'K1', cashierName: 'putra'),
        _sale(total: 20000, cashierRemoteId: 'K1', cashierName: 'Putra Nagari'),
      ]);

      expect(hasil, hasLength(1));
      expect(hasil.first.cashierName, 'putra');
      expect(hasil.first.revenue, 30000);
    });

    test('kasir tanpa ID dilebur berdasar nama', () {
      final hasil = computeCashierSummaries([
        _sale(total: 10000, cashierName: 'putra'),
        _sale(total: 20000, cashierName: 'putra'),
        _sale(total: 5000, cashierName: 'uudin'),
      ]);

      expect(hasil, hasLength(2));
      expect(hasil.first.cashierName, 'putra'); // omzet tertinggi di depan
      expect(hasil.first.revenue, 30000);
    });

    test('struk tanpa kasir sama sekali dikumpulkan jadi "Tanpa Kasir"', () {
      // Struk lama sebelum sesi kasir dicatat. Membiarkannya bernama kosong
      // membuat barisnya tak bisa dibaca di laporan.
      final hasil = computeCashierSummaries([
        _sale(total: 10000),
        _sale(total: 20000),
      ]);

      expect(hasil, hasLength(1));
      expect(hasil.first.cashierName, 'Tanpa Kasir');
      expect(hasil.first.transactions, 2);
    });

    test('terurut omzet menurun', () {
      final hasil = computeCashierSummaries([
        _sale(total: 10000, cashierRemoteId: 'K1', cashierName: 'kecil'),
        _sale(total: 90000, cashierRemoteId: 'K2', cashierName: 'besar'),
        _sale(total: 50000, cashierRemoteId: 'K3', cashierName: 'sedang'),
      ]);

      expect(hasil.map((e) => e.cashierName), ['besar', 'sedang', 'kecil']);
    });

    test('struk yang diretur penuh tidak menambah hitungan transaksi', () {
      final hasil = computeCashierSummaries([
        _sale(total: 100000, cashierRemoteId: 'K1', cashierName: 'putra'),
        _sale(
          total: 50000,
          cashierRemoteId: 'K1',
          cashierName: 'putra',
          isRefunded: true,
          isPaid: false,
        ),
      ]);

      expect(hasil.first.transactions, 1);
      expect(hasil.first.revenue, 100000);
    });
  });
}
