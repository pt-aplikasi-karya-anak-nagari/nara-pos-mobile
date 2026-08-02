import 'dart:convert';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nara_pos_mobile/features/kasir/ui/widgets/payment_sheet.dart';
import 'package:nara_pos_mobile/features/payments/data/payment_method_repository.dart';
import 'package:nara_pos_mobile/features/payments/domain/payment_method.dart';

// Kartu QRIS di layar bayar kasir.
//
// # YANG DIJAGA
//
// Bukan "kartunya tampil". Yang dijaga adalah QR MANA yang benar-benar
// tergambar, dan ANGKA MANA yang tertulis di sebelahnya — dua hal yang
// menentukan berapa uang yang berpindah, dan yang tak akan pernah menimbulkan
// galat kalau salah.
//
// Tiga keadaan yang harus dibedakan:
//
//   berhasil   QR memuat payload DINAMIS dari server, dan angka yang tampil
//              adalah `amount` dari server — bukan total kasir. QRIS hanya
//              membawa rupiah bulat, jadi keduanya bisa berbeda, dan layar yang
//              menyebut angka berbeda dari isi QR-nya membuat yang membayar tak
//              punya cara tahu mana yang benar.
//
//   gagal      QR kembali ke payload STATIS milik outlet, DAN kasir diberi tahu
//              bahwa nominalnya harus diketik pelanggan. Diam saja di sini
//              adalah yang paling mahal: kasir mengira nominalnya sudah
//              terkunci padahal pelanggan bebas mengetik angka lain.
//
//   memuat     QR statisnya tetap tergambar, tak boleh menghilang. Kalau ia
//              hilang lalu muncul lagi, kasir yang sudah mengarahkan ponsel
//              pelanggan ke layar harus mengulang.

const statis = "00020101021126660020ID.CO.BANKNAGARI.WWW"
    "011893600118100721002402090072100240303UMI"
    "51440014ID.CO.QRIS.WWW0215ID10200425042480303UMI5204866153033605802ID"
    "5917SURAU BANK NAGARI6006PADANG61052511762070703A016304E858";

// Payload dinamis Rp11.000 — dihasilkan paket Go internal/qris dan sudah
// dicocokkan byte-per-byte dengan proyek acuan qris-dinamis.
const dinamis = "00020101021226660020ID.CO.BANKNAGARI.WWW"
    "011893600118100721002402090072100240303UMI"
    "51440014ID.CO.QRIS.WWW0215ID10200425042480303UMI520486615303360"
    "5405110005802ID5917SURAU BANK NAGARI6006PADANG61052511762070703A016304A797";

PaymentMethod metodeQris({String id = 'PM-1'}) => PaymentMethod(
      id: id,
      name: 'QRIS',
      type: 'qris',
      qrData: statis,
    );

/// Memasang kartunya dengan satu tiruan untuk qrisDinamisProvider.
///
/// Tipe `Override` tidak dinamai di sini — ia tidak diekspor lewat API publik
/// flutter_riverpod 3.x. Menerima fungsi pembuatnya langsung juga lebih jujur:
/// setiap tes di berkas ini memang hanya menirukan satu provider.
Future<void> pasang(
  WidgetTester tester, {
  required Future<Map<String, dynamic>> Function(Ref, KunciQrisDinamis) buat,
  PaymentMethod? metode,
  double nominal = 11000,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [qrisDinamisProvider.overrideWith(buat)],
      child: MaterialApp(
        home: Scaffold(
          body: KartuQris(metode: metode ?? metodeQris(), nominal: nominal),
        ),
      ),
    ),
  );
}

/// Isi QR yang BENAR-BENAR akan tergambar.
///
/// BarcodeWidget menyimpan `data` sebagai byte, bukan String — membacanya
/// sebagai String langsung akan melempar. Memeriksanya dari byte justru lebih
/// dekat ke kenyataan: inilah yang akan dipindai ponsel pelanggan.
String qrTergambar(WidgetTester tester) => utf8.decode(
      tester.widget<BarcodeWidget>(find.byType(BarcodeWidget)).data
          as List<int>,
    );

void main() {
  testWidgets('berhasil: QR memuat payload dinamis dari server', (tester) async {
    await pasang(
      tester,
      buat: (ref, kunci) async => {'qr_data': dinamis, 'amount': 11000},
    );
    await tester.pumpAndSettle();

    expect(qrTergambar(tester), dinamis,
        reason: 'yang tergambar masih QR statis — pelanggan tetap harus '
            'mengetik nominalnya sendiri, jadi fiturnya tak berbuat apa-apa');
    expect(find.textContaining('nominal sudah terisi'), findsOneWidget);
  });

  testWidgets('angka yang tampil datang dari server, bukan dari total kasir',
      (tester) async {
    // QRIS hanya membawa rupiah bulat, jadi nominal di dalam QR bisa berbeda
    // dari total kasir. Kartu ini harus menampilkan yang ADA DI DALAM QR —
    // kalau ia menampilkan totalnya sendiri, layar dan kode menyebut dua angka
    // berbeda di hadapan orang yang sedang membayar, dan ia tak punya cara tahu
    // mana yang benar.
    //
    // # KENAPA SELISIHNYA DIBUAT BESAR
    //
    // Versi pertama tes ini memakai 11.000,40 lawan 11.000 — dan suntikan yang
    // mengganti angka server dengan total kasir LOLOS, karena formatRupiah
    // membulatkan keduanya jadi teks yang sama persis. Selisih yang tak terlihat
    // di layar tak menguji apa pun. Yang diuji di sini adalah FIELD MANA yang
    // dibaca, jadi selisihnya harus terbaca mata.
    await pasang(
      tester,
      nominal: 12345,
      buat: (ref, kunci) async => {'qr_data': dinamis, 'amount': 12000},
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('12.000'), findsWidgets,
        reason: 'nominal dari server tidak ditampilkan');
    expect(find.textContaining('12.345'), findsNothing,
        reason: 'yang tampil adalah total kasir, bukan angka yang benar-benar '
            'ada di dalam QR');
  });

  testWidgets('gagal: kembali ke QR statis DAN mengatakannya', (tester) async {
    await pasang(
      tester,
      buat: (ref, kunci) async => throw Exception('server tak terjangkau'),
    );
    await tester.pumpAndSettle();

    expect(qrTergambar(tester), statis,
        reason: 'QR-nya hilang saat server gagal — antrean berhenti padahal '
            'QRIS statis masih bisa menerima uang');
    expect(find.textContaining('Nominal belum masuk ke QR'), findsOneWidget,
        reason: 'kasir tidak diberi tahu — ia akan mengira nominalnya sudah '
            'terkunci padahal pelanggan bebas mengetik angka lain');
    expect(find.textContaining('11.000'), findsWidgets,
        reason: 'angka yang harus diketik pelanggan tidak disebutkan');
  });

  testWidgets('memuat: QR statis tetap tergambar, tidak menghilang',
      (tester) async {
    await pasang(tester, buat: (ref, kunci) async {
      await Future<void>.delayed(const Duration(seconds: 5));
      return {'qr_data': dinamis, 'amount': 11000};
    });
    await tester.pump();

    expect(find.byType(BarcodeWidget), findsOneWidget);
    expect(qrTergambar(tester), statis);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 6));
  });

  testWidgets('metode tanpa id tidak menembak server sama sekali',
      (tester) async {
    // Metode yang dibuat offline belum punya id dari server. Memanggil endpoint
    // dengan id kosong hanya menghasilkan 404 dan menunda layar bayar.
    var dipanggil = 0;
    await pasang(
      tester,
      metode: metodeQris(id: ''),
      buat: (ref, kunci) async {
        dipanggil++;
        return {'qr_data': dinamis, 'amount': 11000};
      },
    );
    await tester.pumpAndSettle();

    expect(dipanggil, 0);
    expect(qrTergambar(tester), statis);
    expect(find.textContaining('Nominal belum masuk ke QR'), findsOneWidget);
  });

  group('KunciQrisDinamis', () {
    test('kunci yang sama dianggap sama', () {
      // Menentukan apakah provider men-cache. Tanpa == yang benar, setiap
      // rebuild layar bayar — dan layar itu dibangun ulang tiap kali kasir
      // mengetik — menembak server lagi.
      expect(
        const KunciQrisDinamis('PM-1', 11000),
        const KunciQrisDinamis('PM-1', 11000),
      );
      expect(
        const KunciQrisDinamis('PM-1', 11000).hashCode,
        const KunciQrisDinamis('PM-1', 11000).hashCode,
      );
    });

    test('nominal berbeda = kunci berbeda', () {
      // Sisi yang membuat cache-nya aman. Kalau nominal tak ikut jadi kunci,
      // kasir yang menambah satu item akan tetap melihat QR nominal LAMA.
      expect(
        const KunciQrisDinamis('PM-1', 11000) ==
            const KunciQrisDinamis('PM-1', 25000),
        isFalse,
      );
    });

    test('metode berbeda = kunci berbeda', () {
      expect(
        const KunciQrisDinamis('PM-1', 11000) ==
            const KunciQrisDinamis('PM-2', 11000),
        isFalse,
      );
    });
  });
}
