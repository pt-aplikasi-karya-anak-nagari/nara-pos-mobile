import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/tables/ui/widgets/kartu_meja.dart';

// Regresi: grid meja memakai 4 kolom tetap & kotak persegi, sehingga di panel
// sempit (tablet tampilan terbelah) kotak lebih pendek dari isinya dan
// muncul "BOTTOM OVERFLOWED BY 11 PIXELS".

Widget _grid(double lebar, double skala, {bool baris = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(lebar, 900),
        textScaler: TextScaler.linear(skala),
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: lebar,
            height: 900,
            child: Builder(
              builder: (context) => GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: baris
                    ? gridBarisMeja(context)
                    : gridKartuMeja(context),
                itemCount: 6,
                itemBuilder: (_, i) => KartuMeja(
                  nama: i == 0
                      ? 'Meja Teras Belakang Dekat Taman'
                      : 'Meja${i + 1}',
                  kapasitas: 2,
                  terisi: i.isOdd,
                  labelStatus: i.isOdd ? 'TERISI' : 'TERSEDIA',
                  durasi: i.isOdd
                      ? Container(
                          color: Colors.red,
                          padding: const EdgeInsets.all(2),
                          child: const Text(
                            '12j 45m',
                            style: TextStyle(fontSize: 9),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final lebar in [320.0, 420.0, 680.0, 1000.0]) {
    for (final skala in [1.0, 1.3, 2.0]) {
      testWidgets('kartu meja tak meluap — lebar $lebar, huruf ${skala}x', (
        tester,
      ) async {
        tester.view.physicalSize = Size(lebar, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_grid(lebar, skala));
        expect(tester.takeException(), isNull);
        expect(find.byType(KartuMeja), findsWidgets);
      });
    }
  }

  testWidgets('jumlah kolom mengikuti lebar panel', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<int> kolom(double lebar) async {
      tester.view.physicalSize = Size(lebar, 900);
      await tester.pumpWidget(_grid(lebar, 1));
      final ys = tester
          .widgetList<KartuMeja>(find.byType(KartuMeja))
          .map((w) => tester.getTopLeft(find.byWidget(w)).dy)
          .toList();
      return ys.where((y) => y == ys.first).length;
    }

    expect(await kolom(360), 2);
    expect(await kolom(680), 4);
    expect(await kolom(1000), 6);
  });

  test('tinggi kartu ikut ukuran huruf', () {
    expect(tinggiKartuMeja(1), 128);
    expect(tinggiKartuMeja(2), greaterThan(tinggiKartuMeja(1.3)));
  });
}
