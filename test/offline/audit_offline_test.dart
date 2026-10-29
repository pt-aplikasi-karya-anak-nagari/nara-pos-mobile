import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nara_pos_mobile/core/offline/audit_offline.dart';
import 'package:nara_pos_mobile/core/offline/nomor_struk_offline.dart';
import 'package:nara_pos_mobile/core/offline/sale_outbox.dart';
import 'package:nara_pos_mobile/shared/widgets/dialog_buang_offline.dart';

PendingSale jual(String id, String outlet, String? ref, DateTime t) =>
    PendingSale(
      localId: id,
      outletId: outlet,
      createdAt: t,
      payload: {'final_amount': 10000, 'offline_ref': ?ref},
    );

void main() {
  test('laporan perangkat: nomor urut, antrian & nomor yang tertahan', () {
    final data = susunLaporanPerangkat(
      outletId: 'o1',
      deviceId: 'dev-1',
      deviceLabel: 'Xiaomi Pad',
      kodeStruk: '3FA9C2',
      urutTerakhir: 42,
      penjualanMenunggu: [
        jual('a', 'o1', 'OFF-3FA9C2-00041', DateTime(2026, 10, 29, 9)),
        jual('b', 'o1', 'OFF-3FA9C2-00042', DateTime(2026, 10, 29, 10)),
        jual('c', 'o2', 'OFF-3FA9C2-00040', DateTime(2026, 10, 28)),
        jual('lama', 'o1', null, DateTime(2026, 10, 29, 11)),
      ],
      penjualanGagal: [
        jual('d', 'o1', 'OFF-3FA9C2-00039', DateTime(2026, 10, 29, 8)),
      ],
      shiftMenunggu: 1,
    );
    expect(data['urut_terakhir'], 42);
    expect(data['antrian_penjualan'], 3, reason: 'hanya outlet o1');
    expect(data['antrian_gagal'], 1);
    expect(data['antrian_shift'], 1);
    expect(
      data['ref_tertahan'],
      unorderedEquals([
        'OFF-3FA9C2-00041',
        'OFF-3FA9C2-00042',
        'OFF-3FA9C2-00039',
      ]),
    );
    expect(
      DateTime.parse(data['antrian_tertua'] as String).toLocal(),
      DateTime(2026, 10, 29, 8),
    );
  });

  test('nomor urut terakhir yang dipakai ikut dilaporkan', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final n = NomorStrukOffline(prefs, idPerangkat: () => 'abcdef12');
    expect(n.urutTerakhir, 0);
    await n.berikutnya();
    await n.berikutnya();
    expect(n.urutTerakhir, 2);
  });

  testWidgets('Buang hanya bisa setelah alasan & PIN manajer diisi', (
    tester,
  ) async {
    IsianBuang? hasil;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              hasil = await mintaAlasanDanPinBuang(
                context,
                judul: 'Buang transaksi?',
                keterangan: 'Tetap tercatat di server.',
              );
            },
            child: const Text('buka'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    FilledButton tombol() => tester.widget(find.byType(FilledButton));
    expect(tombol().onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'Produk dihapus');
    await tester.pump();
    expect(tombol().onPressed, isNull, reason: 'PIN belum diisi');

    await tester.enterText(find.byKey(const ValueKey('pin-buang')), '4321');
    await tester.pump();
    expect(tombol().onPressed, isNotNull);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(hasil?.alasan, 'Produk dihapus');
    expect(hasil?.pin, '4321');
  });
}
