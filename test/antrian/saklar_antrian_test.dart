import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nara_pos_mobile/features/antrian/data/antrian_service.dart';
import 'package:nara_pos_mobile/features/antrian/domain/antrian.dart';
import 'package:nara_pos_mobile/features/antrian/ui/tombol_antrian.dart';
import 'package:nara_pos_mobile/features/settings/data/app_settings.dart';

// Pemilik bisa mematikan fitur antrian per outlet.
void main() {
  test('saklar antrian dibaca dari pengaturan outlet (bawaan nyala)', () {
    expect(OutletAppSettings.fromJson(const {}).antrianAktif, isTrue);
    final mati = OutletAppSettings.fromJson({'antrian_aktif': false});
    expect(mati.antrianAktif, isFalse);
    expect(OutletAppSettings.fromJson(mati.toJson()).antrianAktif, isFalse);
    expect(RingkasanAntrian.fromJson({'aktif': false}).aktif, isFalse);
  });

  Future<void> pasang(WidgetTester t, {required bool aktif}) => t.pumpWidget(
    ProviderScope(
      overrides: [
        outletAppSettingsProvider.overrideWith(
          (ref) async => OutletAppSettings(antrianAktif: aktif),
        ),
        ringkasanAntrianProvider.overrideWith(
          (ref) async => RingkasanAntrian.fromJson({
            'aktif': aktif,
            'total': 7,
            'menunggu': 2,
            'sedang_dipanggil': {'id': 'T5', 'nomor': '005'},
          }),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: Center(child: TombolAntrian())),
      ),
    ),
  );

  testWidgets('tombol antrian tampil saat fitur nyala', (t) async {
    await pasang(t, aktif: true);
    await t.pumpAndSettle();
    expect(find.text('Antrian 005'), findsOneWidget);
    expect(find.text('2 menunggu · 7 hari ini'), findsOneWidget);
  });

  testWidgets('tombol antrian disembunyikan saat Pemilik mematikannya', (
    t,
  ) async {
    await pasang(t, aktif: false);
    await t.pumpAndSettle();
    expect(find.textContaining('Antrian'), findsNothing);
  });
}
