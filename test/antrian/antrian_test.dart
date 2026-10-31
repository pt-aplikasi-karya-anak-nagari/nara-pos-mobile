import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nara_pos_mobile/core/shared_prefs.dart';
import 'package:nara_pos_mobile/features/antrian/data/antrian_service.dart';
import 'package:nara_pos_mobile/features/antrian/data/pemanggil_suara.dart';
import 'package:nara_pos_mobile/features/antrian/domain/suara_tts.dart';
import 'package:nara_pos_mobile/features/antrian/domain/antrian.dart';
import 'package:nara_pos_mobile/features/antrian/domain/kalimat_panggilan.dart';
import 'package:nara_pos_mobile/features/antrian/ui/antrian_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('kalimat panggilan', () {
    test('nomor dieja per angka, sama dengan web', () {
      expect(ejaNomor('007'), 'nol, nol, tujuh');
      expect(ejaNomor('120'), 'satu, dua, nol');
      expect(ejaNomor('3fa-012'), 'tiga, F, A, nol, satu, dua');
      expect(
        kalimatPanggilan('007'),
        'Nomor antrian, nol, nol, tujuh. Silakan menuju kasir.',
      );
      expect(
        kalimatPanggilan('007', ulang: true),
        startsWith('Panggilan ulang. Nomor antrian, nol, nol, tujuh.'),
      );
    });
  });

  test('ringkasan dibaca dari JSON server', () {
    final r = RingkasanAntrian.fromJson({
      'total': 5,
      'menunggu': 2,
      'dipanggil': 3,
      'sedang_dipanggil': {
        'id': 'T2',
        'nomor': '002',
        'customer_name': 'Budi',
        'table_name': '4',
        'call_count': 2,
        'called_at': '2026-10-31T02:00:00Z',
      },
      'berikutnya': {'id': 'T4', 'nomor': '004'},
      'daftar_menunggu': [
        {'id': 'T4', 'nomor': '004'},
        {'id': 'T5', 'nomor': '3FA-001'},
      ],
      'riwayat_panggil': null,
    });
    expect((r.total, r.menunggu, r.dipanggil), (5, 2, 3));
    expect(r.sedangDipanggil!.keterangan, 'Budi · Meja 4');
    expect(r.sedangDipanggil!.dipanggilKali, 2);
    expect(r.daftarMenunggu.map((e) => e.nomor), ['004', '3FA-001']);
    expect(r.riwayatPanggil, isEmpty);
  });

  test('event realtime yang memuat ulang antrian', () {
    expect(mengubahAntrian('queue.called'), isTrue);
    expect(mengubahAntrian('transaction.created'), isTrue);
    expect(mengubahAntrian('order.confirmed'), isTrue);
    expect(mengubahAntrian('inventory.low_stock'), isFalse);
  });

  testWidgets('panel menampilkan nomor, total, menunggu & tombol panggil', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await t.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          pemanggilSuaraProvider.overrideWithValue(_SuaraPalsu(prefs)),
          ringkasanAntrianProvider.overrideWith(
            (ref) async => RingkasanAntrian.fromJson({
              'total': 9,
              'menunggu': 2,
              'dipanggil': 7,
              'sedang_dipanggil': {'id': 'T7', 'nomor': '007'},
              'berikutnya': {'id': 'T8', 'nomor': '008'},
              'daftar_menunggu': [
                {'id': 'T8', 'nomor': '008', 'customer_name': 'Rina'},
                {'id': 'T9', 'nomor': '009'},
              ],
            }),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: AntrianSheet())),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('007'), findsOneWidget);
    expect(find.text('9'), findsOneWidget); // total
    expect(find.text('Total antrian'), findsOneWidget);
    expect(find.text('Panggil berikutnya · 008'), findsOneWidget);
    expect(find.text('Rina'), findsOneWidget);
    expect(find.text('Panggil ulang'), findsOneWidget);
    // Pilihan suara: otomatis (paling alami) sebagai bawaan.
    await t.scrollUntilVisible(
      find.text('Otomatis (paling alami)'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Otomatis (paling alami)'), findsOneWidget);
  });
}

/// Tanpa mesin TTS sungguhan di lingkungan tes.
class _SuaraPalsu extends PemanggilSuara {
  _SuaraPalsu(super.prefs);

  @override
  Future<List<SuaraTts>> daftarSuara() async => const [
    SuaraTts(
      nama: 'id-id-x-idc-network',
      lokal: 'id-ID',
      kualitas: 'very high',
      butuhInternet: true,
    ),
  ];
}
