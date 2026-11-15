import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nara_pos_mobile/features/billing/data/billing_repository.dart';
import 'package:nara_pos_mobile/features/billing/domain/billing_invoice.dart';
import 'package:nara_pos_mobile/features/subscription/ui/pembayaran_qris.dart';

// Layar bayar QRIS adalah satu-satunya tempat Pemilik tahu pembayarannya masuk.
// Yang dijaga: ia memeriksa status sendiri, tidak menampilkan kode yang sudah
// kedaluwarsa, dan berhenti memeriksa setelah lunas.

final _kini = DateTime.utc(2026, 11, 16, 3);

BillingCheckoutResult _hasil({
  String status = 'pending',
  String qr = '00020101-QR',
  int sisaDetik = 600,
}) {
  return BillingCheckoutResult.fromJson({
    'invoice': {
      'id': 'INV1',
      'invoice_no': 'INV/2026/1',
      'amount_idr': 149000,
      'status': status,
    },
    'payment_instruction': {
      'method_code': 'xendit_qris',
      'method_name': 'QRIS',
      'amount_idr': 149000,
      'invoice_no': 'INV/2026/1',
      'provider': 'xendit',
      'qr_string': qr,
      'expires_at': _kini.add(Duration(seconds: sisaDetik)).toIso8601String(),
      'gateway_status': 'pending',
    },
  });
}

Future<void> _pompa(
  WidgetTester tester, {
  required BillingCheckoutResult hasil,
  Future<BillingCheckoutResult> Function()? pemeriksa,
  VoidCallback? onLunas,
  VoidCallback? onBuatUlang,
  bool membuatUlang = false,
  DateTime Function()? jam,
}) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PembayaranQris(
              outletId: 'OUT1',
              hasil: hasil,
              onLunas: onLunas ?? () {},
              onBuatUlang: onBuatUlang ?? () {},
              membuatUlang: membuatUlang,
              pemeriksa: pemeriksa ?? () async => hasil,
              jam: jam ?? () => _kini,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('BillingCheckoutResult QRIS', () {
    test('mengurai instruksi QRIS dari server', () {
      final h = _hasil();
      final pi = h.paymentInstruction!;
      expect(h.qris, isTrue);
      expect(h.lunas, isFalse);
      expect(pi.isQris, isTrue);
      expect(pi.qrString, '00020101-QR');
      expect(pi.provider, 'xendit');
      expect(pi.expiresAt, _kini.add(const Duration(minutes: 10)));
    });

    test('instruksi transfer manual lama tetap terbaca', () {
      final h = BillingCheckoutResult.fromJson({
        'invoice': {
          'id': 'A',
          'invoice_no': 'N',
          'amount_idr': 1,
          'status': 'pending',
        },
        'payment_instruction': {
          'method_code': 'manual_transfer',
          'bank_name': 'BCA',
          'bank_account_no': '123',
        },
      });
      expect(h.qris, isFalse);
      expect(h.paymentInstruction!.qrString, '');
      expect(h.paymentInstruction!.expiresAt, isNull);
      expect(h.paymentInstruction!.bankName, 'BCA');
    });
  });

  group('sisaWaktuQris', () {
    test('format dan batas mendesak', () {
      ({bool habis, bool mendesak, String teks}) s(int detik) =>
          sisaWaktuQris(_kini.add(Duration(seconds: detik)), _kini);
      expect(s(600), (habis: false, mendesak: false, teks: '10:00'));
      expect(s(119), (habis: false, mendesak: true, teks: '01:59'));
      expect(s(9000), (habis: false, mendesak: false, teks: '2 jam 30 menit'));
      expect(s(0).habis, isTrue);
      expect(s(-30).habis, isTrue);
    });

    test('tanpa batas waktu dianggap habis', () {
      expect(sisaWaktuQris(null, _kini).habis, isTrue);
    });
  });

  group('BillingInvoice', () {
    BillingInvoice inv(String status, String metode) => BillingInvoice.fromJson(
      {'id': 'A', 'status': status, 'payment_method_code': metode},
    );

    test('invoice QRIS tidak menawarkan unggah bukti', () {
      expect(inv('pending', 'xendit_qris').canUploadProof, isFalse);
      expect(inv('pending', 'xendit_qris').menungguQris, isTrue);
      expect(inv('paid', 'xendit_qris').menungguQris, isFalse);
      // Transfer manual tidak berubah.
      expect(inv('pending', 'manual_transfer').canUploadProof, isTrue);
      expect(inv('pending', 'manual_transfer').menungguQris, isFalse);
    });
  });

  group('PembayaranQris', () {
    testWidgets('menampilkan kode QR, nominal, dan sisa waktu', (tester) async {
      await _pompa(tester, hasil: _hasil());
      // BarcodeWidget menyimpan datanya sebagai byte, bukan teks.
      final qr = tester.widget<BarcodeWidget>(find.byType(BarcodeWidget));
      expect(String.fromCharCodes(qr.data), '00020101-QR');
      expect(find.textContaining('149.000'), findsOneWidget);
      expect(find.text('Berlaku 10:00 lagi'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('memeriksa status sendiri dan memanggil onLunas sekali', (
      tester,
    ) async {
      var dipanggil = 0;
      var lunas = 0;
      await _pompa(
        tester,
        hasil: _hasil(),
        onLunas: () => lunas++,
        pemeriksa: () async {
          dipanggil++;
          // Belum dibayar pada pengecekan pertama, lunas pada yang kedua.
          return _hasil(status: dipanggil >= 2 ? 'paid' : 'pending');
        },
      );
      expect(dipanggil, 0);

      await tester.pump(PembayaranQris.jedaCek);
      await tester.pump();
      expect(dipanggil, 1);
      expect(lunas, 0);

      await tester.pump(PembayaranQris.jedaCek);
      await tester.pump();
      expect(dipanggil, 2);
      expect(lunas, 1);

      // Setelah lunas tidak ada pengecekan lagi.
      await tester.pump(PembayaranQris.jedaCek * 4);
      expect(dipanggil, 2);
      expect(lunas, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('kode kedaluwarsa tidak ditampilkan; ditawarkan kode baru', (
      tester,
    ) async {
      var buatUlang = 0;
      await _pompa(
        tester,
        hasil: _hasil(sisaDetik: -5),
        onBuatUlang: () => buatUlang++,
      );
      expect(find.byType(BarcodeWidget), findsNothing);
      expect(find.text('Kode QR sudah kedaluwarsa'), findsOneWidget);
      await tester.tap(find.text('Buat kode QR baru'));
      expect(buatUlang, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('server tidak mengirim QR → sama, tawarkan kode baru', (
      tester,
    ) async {
      await _pompa(tester, hasil: _hasil(qr: ''), membuatUlang: true);
      expect(find.byType(BarcodeWidget), findsNothing);
      expect(find.text('Membuat kode…'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('kode yang habis selagi layar terbuka ikut disembunyikan', (
      tester,
    ) async {
      var sekarang = _kini;
      await _pompa(tester, hasil: _hasil(sisaDetik: 2), jam: () => sekarang);
      expect(find.byType(BarcodeWidget), findsOneWidget);

      sekarang = _kini.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BarcodeWidget), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tombol periksa manual menampilkan galat bila gagal', (
      tester,
    ) async {
      await _pompa(
        tester,
        hasil: _hasil(),
        pemeriksa: () async => throw 'Tidak bisa terhubung ke server',
      );
      await tester.tap(find.text('Saya sudah membayar — periksa status'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Tidak bisa terhubung ke server'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
