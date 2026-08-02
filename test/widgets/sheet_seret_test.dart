import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nara_pos_mobile/core/offline/sale_outbox.dart';
import 'package:nara_pos_mobile/core/offline/shift_outbox.dart';
import 'package:nara_pos_mobile/shared/widgets/dead_letter_recovery_sheet.dart';
import 'package:nara_pos_mobile/shared/widgets/sheet_bawah.dart';

// Sheet yang dulu memakai DraggableScrollableSheet.
//
// # KENAPA WIDGET ITU DICABUT
//
// DraggableScrollableSheet membuka pada pecahan layar yang dipatok
// (initialChildSize), TANPA memandang isinya: 0,6 di sheet ini, 0,85 di
// manajemen metode bayar, 0,7 di checkout langganan, 0,6 di detail transfer
// stok. Satu transaksi gagal tetap membuka 60% layar, dan 40% sisanya rongga
// kosong yang harus diseret pengguna untuk menutupnya.
//
// Widget itu masuk akal untuk daftar panjang yang memang ingin diseret naik.
// Untuk keempat sheet ini isinya hampir selalu pendek, jadi yang tersisa
// hanyalah harganya.
//
// # KENAPA DIUJI DENGAN MERENDER, BUKAN MEMBACA SUMBER
//
// Perubahannya menyentuh empat hal yang saling menopang — DraggableScrollableSheet
// dicabut, Expanded jadi Flexible, Column jadi mainAxisSize.min, ListView dapat
// shrinkWrap. Lupa SATU saja mengembalikan tinggi penuh, dan ketiganya yang lain
// tetap terlihat benar. Hanya tinggi yang benar-benar tergambar yang bisa
// membedakannya.

class SaleOutboxKosong extends SaleOutbox {
  final List<PendingSale> isi;
  SaleOutboxKosong([this.isi = const []]);
  @override
  Future<List<PendingSale>> deadLetters() async => isi;
  @override
  Future<int> count() async => 0;
  @override
  Future<int> deadLetterCount() async => isi.length;
}

class ShiftOutboxKosong extends ShiftOutbox {
  @override
  Future<List<PendingOp>> deadLetters() async => const [];
  @override
  Future<int> count() async => 0;
  @override
  Future<int> deadLetterCount() async => 0;
}

PendingSale sale(String id) => PendingSale(
  localId: id,
  outletId: 'OUT',
  payload: const {
    'final_amount': 50000,
    'payment_method': 'Tunai',
    'items': [1, 2],
  },
  createdAt: DateTime(2026),
  attempts: 5,
  lastError: 'produk tidak ditemukan',
);

Future<double> tinggiSheetDeadLetter(
  WidgetTester tester,
  List<PendingSale> isi,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();

  late WidgetRef wref;
  late BuildContext ctx;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        saleOutboxProvider.overrideWithValue(SaleOutboxKosong(isi)),
        shiftOutboxProvider.overrideWithValue(ShiftOutboxKosong()),
      ],
      child: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: MaterialApp(
          home: Consumer(
            builder: (c, r, _) {
              ctx = c;
              wref = r;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      ),
    ),
  );

  showDeadLetterRecoverySheet(ctx, wref);
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(WadahSheetBawah)).height;
}

void main() {
  // _DeadLetterCard memformat tanggal dengan locale id_ID. Tanpa ini setiap
  // kartu melempar LocaleDataException, dan tinggi yang terukur adalah tinggi
  // widget galat — bukan tinggi sheet yang sedang diuji.
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('sheet pemulihan tidak lagi membuka 60% layar apa pun isinya', (
    tester,
  ) async {
    final t = await tinggiSheetDeadLetter(tester, [sale('a')]);
    expect(
      t,
      lessThan(480), // 0,6 x 800 = 480, tinggi lama yang dipatok
      reason:
          'sheet setinggi ${t.toStringAsFixed(0)} untuk satu transaksi gagal '
          '— masih sebesar initialChildSize lama, jadi salah satu dari '
          'Flexible / mainAxisSize.min / shrinkWrap belum berlaku',
    );
  });

  testWidgets('tingginya bergerak mengikuti banyaknya isi', (tester) async {
    final satu = await tinggiSheetDeadLetter(tester, [sale('a')]);
    final tiga = await tinggiSheetDeadLetter(tester, [
      sale('a'),
      sale('b'),
      sale('c'),
    ]);
    expect(
      tiga,
      greaterThan(satu),
      reason:
          'tiga transaksi menghasilkan tinggi yang sama dengan satu ($satu) '
          '— tingginya masih dipatok, bukan mengikuti isi',
    );
  });

  testWidgets('isi yang banyak tetap dibatasi layar, tidak meluber', (
    tester,
  ) async {
    final t = await tinggiSheetDeadLetter(tester, [
      for (var i = 0; i < 30; i++) sale('s$i'),
    ]);
    expect(t, lessThanOrEqualTo(800));
    expect(tester.takeException(), isNull, reason: 'isi sheet meluber');
  });
}
