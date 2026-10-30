import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/core/network/galat_api.dart';
import 'package:nara_pos_mobile/shared/widgets/pin_stok.dart';

void main() {
  Future<BuildContext> pasang(WidgetTester t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    return ctx;
  }

  testWidgets('ditolak perlu_pin_stok → minta PIN lalu ulangi dengan PIN',
      (t) async {
    final ctx = await pasang(t);
    final pinDikirim = <String?>[];
    final hasil = denganPinStok<int>(ctx, (pin) async {
      pinDikirim.add(pin);
      if (pin == null) {
        throw const GalatApi(kodePerluPinStok, 'Pengurangan stok melebihi batas');
      }
      return 7;
    });
    await t.pumpAndSettle();
    expect(find.text('Pengurangan stok melebihi batas'), findsOneWidget);
    await t.enterText(find.byType(TextField), '1234');
    await t.pump();
    await t.tap(find.text('Setujui'));
    await t.pumpAndSettle();
    expect(await hasil, 7);
    expect(pinDikirim, [null, '1234']);
  });

  testWidgets('dialog dibatalkan → null, tanpa mengulang', (t) async {
    final ctx = await pasang(t);
    var dipanggil = 0;
    final hasil = denganPinStok<int>(ctx, (pin) async {
      dipanggil++;
      throw const GalatApi(kodePerluPinStok, 'perlu PIN');
    });
    await t.pumpAndSettle();
    await t.tap(find.text('Batal'));
    await t.pumpAndSettle();
    expect(await hasil, isNull);
    expect(dipanggil, 1);
  });

  testWidgets('galat lain diteruskan apa adanya', (t) async {
    final ctx = await pasang(t);
    await expectLater(
      denganPinStok<int>(ctx, (_) async => throw 'Tidak ada koneksi internet'),
      throwsA('Tidak ada koneksi internet'),
    );
  });
}
