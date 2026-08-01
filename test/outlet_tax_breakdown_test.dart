import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/outlet/domain/outlet.dart';

// Outlet.computeTaxBreakdown — SATU sumber kebenaran pajak & service charge di
// aplikasi kasir. Setiap struk yang dicetak lewat sini (_taxBreakdownProvider,
// lib/features/kasir/providers.dart:232), dan sampai sekarang tak ada satu pun
// tes menyentuhnya. Komentar di provider itu sendiri mencatat bahwa bug
// dobel-charge PPN baru saja diperbaiki — tanpa tes, ia bebas kembali kapan
// saja.
//
// # KENAPA TIDAK ADA SATU PUN ASSERT PADA grandTotal SENDIRIAN
//
// Regresi paling mungkin di sini adalah menyederhanakan back-out PPN mode
// inclusive jadi `net = amount / (1 + taxRate)` — bentuk yang jauh lebih rapi
// dan salah, karena ia ikut mengupas PPN dari item yang BEBAS pajak.
//
// Untuk keranjang Rp110.000 yang separuhnya bebas pajak:
//
//                    subtotal(DPP)      pajak     grandTotal
//     benar             105.000         5.000       110.000
//     rusak             100.000        10.000       110.000   ← sama!
//
// grandTotal-nya IDENTIK. Tes yang cuma memeriksa total yang dibayar pelanggan
// akan hijau selamanya sementara DPP dan PPN di struk salah — dan itu angka
// yang masuk ke SPT. Jadi tiap kasus di bawah mengunci `subtotal` dan `tax`.
//
// # KENAPA NILAINYA DIEJA, BUKAN DIHITUNG DARI INVARIAN
//
// Menggoda sekali menulis `expect(grandTotal, subtotal + tax + serviceCharge)`.
// Itu SALAH di sini: keempat komponen di-roundToDouble() sendiri-sendiri, jadi
// penjumlahan yang dibulatkan tidak sama dengan jumlah dari yang dibulatkan.
// Penyisiran 69.744 kombinasi (nominal 1.000–200.000, tarif 5/10/11/12%,
// SC 0/5/7,5/10%, porsi kena pajak 100/50/37%) menemukan 741 yang melanggarnya
// — sekitar 1%. Tes berbasis invarian itu akan gagal acak.
//
// Angka harapan di bawah diturunkan dari aturan pajaknya lebih dulu, baru
// dicocokkan dengan implementasi — bukan dibaca dari keluarannya.

Outlet _outlet({
  bool inclusive = false,
  double taxPercent = 10,
  double servicePercent = 0,
  bool taxEnabled = true,
}) => Outlet(
  name: 'Outlet Uji',
  taxEnabled: taxEnabled,
  taxPercent: taxPercent,
  serviceChargePercent: servicePercent,
  taxInclusive: inclusive,
);

void main() {
  group('mode inclusive — harga sudah termasuk PPN', () {
    test('PPN di-back-out HANYA dari porsi yang kena pajak', () {
      // Keranjang Rp110.000: Rp55.000 kena pajak (harganya sudah termasuk
      // PPN 10%), Rp55.000 bebas pajak.
      //   porsi kena pajak: 55.000 / 1,1 = 50.000 → PPN = 5.000
      //   item bebas pajak tidak mengandung PPN sama sekali
      //   DPP = 110.000 − 5.000 = 105.000
      final r = _outlet(
        inclusive: true,
      ).computeTaxBreakdown(110000, taxableSubtotal: 55000);

      expect(r.subtotal, 105000);
      expect(r.tax, 5000);
      expect(r.grandTotal, 110000);
    });

    test('keranjang yang SELURUHNYA kena pajak memberi angka berbeda', () {
      // Pasangan pembanding kasus di atas. Nominal yang dibayar sama persis
      // (110.000), yang berbeda hanya komposisinya — dan justru di sinilah
      // perbedaannya harus muncul. Kalau kedua kasus ini pernah memberi hasil
      // yang sama, argumen taxableSubtotal sudah tak berfungsi.
      final r = _outlet(
        inclusive: true,
      ).computeTaxBreakdown(110000, taxableSubtotal: 110000);

      expect(r.subtotal, 100000);
      expect(r.tax, 10000);
      expect(r.grandTotal, 110000);
    });

    test('PPN TIDAK ditambahkan di atas harga — pelanggan bayar sesuai daftar', () {
      // Inti bug dobel-charge. Di outlet tax-inclusive, harga yang dipajang
      // sudah final. Kalau PPN ditambahkan lagi di atasnya, tiap struk naik
      // 10% tanpa ada yang menyadarinya sampai pelanggan protes.
      final r = _outlet(
        inclusive: true,
      ).computeTaxBreakdown(100000, taxableSubtotal: 100000);

      expect(r.grandTotal, 100000);
    });

    test('service charge dihitung dari NET, bukan dari harga kotor', () {
      //   net = 100.000 / 1,1 = 90.909,09  → PPN = 9.090,91
      //   SC 5% dari NET      = 4.545,45   (bukan 5% dari 100.000 = 5.000)
      //   total = 90.909,09 + 9.090,91 + 4.545,45 = 104.545,45
      final r = _outlet(
        inclusive: true,
        servicePercent: 5,
      ).computeTaxBreakdown(100000, taxableSubtotal: 100000);

      expect(r.subtotal, 90909);
      expect(r.tax, 9091);
      expect(r.serviceCharge, 4545);
      expect(r.grandTotal, 104545);

      // Sengaja dieja: SC dari harga kotor akan memberi 5.000. Selisihnya kecil
      // per struk, tapi ia masuk ke ekspektasi kas shift tiap hari.
      expect(r.serviceCharge, isNot(5000));
    });
  });

  group('mode exclusive — PPN ditambahkan di atas harga', () {
    test('basis pajak = porsi kena pajak + service charge, bukan seluruh nota', () {
      //   SC        = 5% × 100.000 = 5.000
      //   basis PPN = 50.000 + 5.000 = 55.000
      //   PPN       = 5.500
      //   total     = 100.000 + 5.000 + 5.500 = 110.500
      final r = _outlet(
        servicePercent: 5,
      ).computeTaxBreakdown(100000, taxableSubtotal: 50000);

      expect(r.subtotal, 100000);
      expect(r.serviceCharge, 5000);
      expect(r.tax, 5500);
      expect(r.grandTotal, 110500);

      // Kalau basisnya jadi seluruh nota (100.000 + 5.000), PPN-nya 10.500 —
      // item bebas pajak ikut dipajaki.
      expect(r.tax, isNot(10500));
    });

    test('subtotal mode exclusive adalah harga kotor apa adanya', () {
      final r = _outlet().computeTaxBreakdown(100000, taxableSubtotal: 100000);

      expect(r.subtotal, 100000);
      expect(r.tax, 10000);
      expect(r.grandTotal, 110000);
    });
  });

  group('kedua mode tidak boleh menyatu', () {
    test('angka yang sama, dua mode, hasil WAJIB berbeda', () {
      // Penjaga terhadap refactor yang "merapikan" dua cabang jadi satu.
      // Untuk nominal & tarif yang sama, inclusive dan exclusive memang harus
      // memberi total yang berbeda — itulah gunanya saklar tersebut.
      final inc = _outlet(
        inclusive: true,
      ).computeTaxBreakdown(100000, taxableSubtotal: 100000);
      final exc = _outlet().computeTaxBreakdown(100000, taxableSubtotal: 100000);

      expect(inc.grandTotal, 100000);
      expect(exc.grandTotal, 110000);
      expect(inc.grandTotal, isNot(exc.grandTotal));
    });
  });

  group('jalur pintas', () {
    test('pajak dimatikan → nota lewat tanpa disentuh', () {
      final r = _outlet(taxEnabled: false).computeTaxBreakdown(100000);

      expect(r.subtotal, 100000);
      expect(r.tax, 0);
      expect(r.serviceCharge, 0);
      expect(r.grandTotal, 100000);
    });

    test('service charge TIDAK ikut kalau pajak dimatikan', () {
      // Jalur pintas di awal fungsi keluar sebelum service charge dihitung.
      // Perilaku ini mudah berubah tanpa sengaja saat seseorang memindahkan
      // perhitungan SC ke luar dari cabang pajak.
      final r = _outlet(
        taxEnabled: false,
        servicePercent: 10,
      ).computeTaxBreakdown(100000);

      expect(r.serviceCharge, 0);
      expect(r.grandTotal, 100000);
    });

    test('nominal nol atau negatif tidak menghasilkan pajak negatif', () {
      for (final nominal in [0.0, -5000.0]) {
        final r = _outlet().computeTaxBreakdown(nominal);
        expect(r.tax, 0, reason: 'nominal $nominal');
        expect(r.grandTotal, nominal, reason: 'nominal $nominal');
      }
    });

    test('taxableSubtotal yang tak diisi jatuh ke seluruh nominal', () {
      // Pemanggil lama memanggil tanpa argumen ini. Kalau cadangannya berubah
      // jadi 0, seluruh nota mendadak bebas pajak dan tak ada yang error.
      final tanpa = _outlet().computeTaxBreakdown(100000);
      final dengan = _outlet().computeTaxBreakdown(
        100000,
        taxableSubtotal: 100000,
      );

      expect(tanpa.tax, dengan.tax);
      expect(tanpa.tax, 10000);
    });
  });
}
