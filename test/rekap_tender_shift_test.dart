import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/transactions/domain/sale.dart';

/// Rekap tender shift mengelompokkan transaksi lewat TIPE metode bayar.
///
/// # KENAPA INI ADA
///
/// Sampai perbaikan ini, halaman Riwayat Shift dan struk laporan tutup kasir
/// mengelompokkan tender dengan mencocokkan NAMA persis:
///
///     if (sale.paymentMethod == 'Kartu')    totalCard     += ...
///     if (sale.paymentMethod == 'Transfer') totalTransfer += ...
///
/// Nama sebenarnya di basis data adalah "Kartu Debit/Kredit" dan "Transfer
/// Bank". Tak satu pun pernah cocok, jadi kedua baris itu SELALU nol — dan
/// Pemilik masih bebas mengganti nama metode bayarnya kapan saja, yang membuat
/// cocok-persis mustahil dibuat benar.
///
/// Yang membuat ini mahal: kertas laporan tutup kasir dipakai menyerahkan uang
/// ke supervisor. "Total Kartu Rp0" untuk shift yang menerima jutaan lewat
/// kartu bukan sekadar tak berguna — ia bukti tertulis yang salah, dan yang
/// menandatanganinya tak punya cara tahu.

Sale saleUji({
  required String metode,
  String tipe = '',
  double total = 100000,
  String status = 'paid',
  double refunded = 0,
  List<SaleTender> tenders = const [],
}) {
  return Sale(
    createdAt: DateTime(2026, 1, 1),
    subtotal: total,
    tax: 0,
    total: total,
    paymentMethod: metode,
    paymentMethodType: tipe,
    tenders: tenders,
    isPaid: status == 'paid' || status == 'partially_refunded',
    paymentStatus: status,
    isRefunded: status == 'refunded',
    isPartiallyRefunded: status == 'partially_refunded',
    refundedAmount: refunded,
  );
}

void main() {
  group('pengelompokan lewat tipe', () {
    test('nama panjang bawaan sistem tetap masuk kelompoknya', () {
      // Persis nama yang ada di tabel payment_methods. Inilah kasus yang
      // membuat kolom Kartu dan Transfer selalu nol.
      final kartu = saleUji(metode: 'Kartu Debit/Kredit', tipe: 'card');
      final transfer = saleUji(metode: 'Transfer Bank', tipe: 'transfer');

      expect(kartu.porsiTender('card'), 100000,
          reason: 'penjualan kartu tak terhitung — struk tutup kasir akan '
              'mencetak Rp0 untuk laci yang menerima jutaan');
      expect(transfer.porsiTender('transfer'), 100000);
    });

    test('nama yang diubah Pemilik tetap terhitung lewat tipe', () {
      // Alasan pencocokan nama tak akan pernah bisa dibuat benar: nama metode
      // bayar adalah teks bebas milik Pemilik.
      final s = saleUji(metode: 'QRIS BCA Kantin', tipe: 'qris');
      expect(s.porsiTender('qris'), 100000);
    });

    test('tidak bocor ke kelompok lain', () {
      // Sisi yang membuat rekap ini berarti. Perbaikan yang menjawab "ya" untuk
      // semua tipe akan membuat total tender jauh melebihi omzetnya.
      final s = saleUji(metode: 'QRIS', tipe: 'qris');
      expect(s.porsiTender('card'), 0);
      expect(s.porsiTender('cash'), 0);
      expect(s.porsiTender('transfer'), 0);
    });
  });

  group('transaksi lama tanpa payment_method_id', () {
    test('tipe ditebak dari nama bila server tak mengirim tipenya', () {
      // payment_method_type kosong karena JOIN-nya tak dapat baris. Server
      // memperlakukan kasus yang sama dengan menebak dari nama juga
      // (cashSalesSubquery), jadi mobile harus mengikuti supaya angkanya tak
      // berbeda dari Ekspektasi Kas di layar yang sama.
      expect(saleUji(metode: 'Tunai').porsiTender('cash'), 100000);
      expect(saleUji(metode: 'QRIS').porsiTender('qris'), 100000);
      expect(
          saleUji(metode: 'Kartu Debit/Kredit').porsiTender('card'), 100000);
      expect(saleUji(metode: 'Transfer Bank').porsiTender('transfer'), 100000);
    });

    test('tipe dari server MENGALAHKAN tebakan nama', () {
      // Nama dan tipe bisa berbeda — Pemilik boleh menamai metode bertipe
      // transfer dengan "Kartu Kredit Cicilan". Yang menentukan adalah tipenya.
      final s = saleUji(metode: 'Kartu Kredit Cicilan', tipe: 'transfer');
      expect(s.porsiTender('transfer'), 100000);
      expect(s.porsiTender('card'), 0);
    });

    test('nama tak dikenal tidak masuk kelompok mana pun', () {
      final s = saleUji(metode: 'Voucher Karyawan');
      expect(s.porsiTender('cash'), 0);
      expect(s.porsiTender('qris'), 0);
      expect(s.porsiTender('card'), 0);
      expect(s.porsiTender('transfer'), 0);
    });
  });

  group('split payment', () {
    test('tiap tender masuk kelompoknya sendiri', () {
      // Transaksi split disimpan dengan payment_method = "split" — bukan metode
      // mana pun. Sebelum rincian tender dimuat, seluruh nilainya lenyap dari
      // rekap, sementara porsi tunainya TETAP dihitung server di Ekspektasi
      // Kas. Dua angka dari laci yang sama yang tak bisa dicocokkan.
      final s = saleUji(
        metode: 'split',
        total: 100000,
        tenders: const [
          SaleTender(method: 'Tunai', type: 'cash', amount: 40000),
          SaleTender(method: 'QRIS', type: 'qris', amount: 60000),
        ],
      );

      expect(s.porsiTender('cash'), 40000);
      expect(s.porsiTender('qris'), 60000);
      expect(s.porsiTender('card'), 0);
    });

    test('retur sebagian dibagi proporsional ke semua tender', () {
      // Server tak mencatat tender mana yang dikembalikan, jadi memilih salah
      // satu berarti menebak — dan tebakan yang salah memindahkan uang antar
      // kolom di kertas serah-terima.
      final s = saleUji(
        metode: 'split',
        total: 100000,
        status: 'partially_refunded',
        refunded: 20000,
        tenders: const [
          SaleTender(method: 'Tunai', type: 'cash', amount: 40000),
          SaleTender(method: 'QRIS', type: 'qris', amount: 60000),
        ],
      );

      expect(s.porsiTender('cash'), closeTo(32000, 0.01));
      expect(s.porsiTender('qris'), closeTo(48000, 0.01));
      expect(s.porsiTender('cash') + s.porsiTender('qris'),
          closeTo(s.netTotal, 0.01));
    });

    test('tender tanpa payment_type ditebak dari namanya', () {
      // Baris yang ditulis klien lama: server hanya menebak "cash" di sana,
      // sisanya disimpan kosong.
      final s = saleUji(
        metode: 'split',
        total: 100000,
        tenders: const [
          SaleTender(method: 'Tunai', type: 'cash', amount: 30000),
          SaleTender(method: 'Kartu Debit/Kredit', type: '', amount: 70000),
        ],
      );

      expect(s.porsiTender('card'), 70000);
    });
  });

  group('retur', () {
    test('retur penuh tidak menyumbang tender apa pun', () {
      final s = saleUji(metode: 'QRIS', tipe: 'qris', status: 'refunded');
      expect(s.porsiTender('qris'), 0,
          reason: 'struk yang diretur penuh tetap dihitung sebagai penjualan '
              'QRIS — rekap tender tak akan cocok dengan uang di laci');
    });

    test('retur sebagian hanya menyumbang porsi yang diterima', () {
      final s = saleUji(
        metode: 'Kartu Debit/Kredit',
        tipe: 'card',
        total: 100000,
        status: 'partially_refunded',
        refunded: 25000,
      );
      expect(s.porsiTender('card'), closeTo(75000, 0.01));
    });
  });

  test('fromJson membaca payment_method_type dan payments', () {
    // Bentuk JSON persis dari GET /shifts/:id/transactions.
    final s = Sale.fromJson({
      'id': 'TRX-1',
      'created_at': '2026-01-01T10:00:00Z',
      'subtotal_amount': 100000,
      'tax_amount': 0,
      'final_amount': 100000,
      'payment_method': 'split',
      'payment_method_type': '',
      'payment_status': 'paid',
      'payments': [
        {'payment_method': 'Tunai', 'payment_type': 'cash', 'amount': 40000},
        {'payment_method': 'QRIS', 'payment_type': 'qris', 'amount': 60000},
      ],
    });

    expect(s.tenders.length, 2);
    expect(s.porsiTender('cash'), 40000);
    expect(s.porsiTender('qris'), 60000);
  });

  test('fromJson tanpa payments tetap aman', () {
    // Endpoint lain tak memuat rincian tender. Transaksi single-method harus
    // tetap terkelompokkan lewat payment_method_type / tebakan nama.
    final s = Sale.fromJson({
      'id': 'TRX-2',
      'created_at': '2026-01-01T10:00:00Z',
      'subtotal_amount': 50000,
      'tax_amount': 0,
      'final_amount': 50000,
      'payment_method': 'Kartu Debit/Kredit',
      'payment_status': 'paid',
    });

    expect(s.tenders, isEmpty);
    expect(s.porsiTender('card'), 50000);
  });
}
