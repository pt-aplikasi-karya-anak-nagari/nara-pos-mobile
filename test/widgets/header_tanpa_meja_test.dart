import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/core/outlet_scope.dart';
import 'package:nara_pos_mobile/features/drafts/providers.dart';
import 'package:nara_pos_mobile/features/kasir/ui/widgets/header_aksi_kasir.dart';

// Fitur Meja bisa dimatikan untuk tipe outlet (mis. Retail) oleh SuperAdmin.
// Layar Kasir lalu mengirim onMeja: null, dan tombolnya harus HILANG — bukan
// tampil lalu membuka daftar meja yang ditolak server.
Future<void> _pasang(WidgetTester tester, {VoidCallback? onMeja}) async {
  tester.view.physicalSize = const Size(1024, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeOutletLabelProvider.overrideWithValue('Toko Uji'),
        draftsCountProvider.overrideWithValue(0),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              HeaderAksiKasir(
                onScan: () {},
                onCustomOrder: () {},
                onMeja: onMeja,
                onDraft: () {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('tanpa onMeja → tombol Meja tak ditampilkan', (tester) async {
    await _pasang(tester);
    expect(find.text('Meja'), findsNothing);
    // Aksi lain tetap ada.
    for (final label in ['Scan', 'Custom Order', 'Draft']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('dengan onMeja → tombol Meja tampil', (tester) async {
    await _pasang(tester, onMeja: () {});
    expect(find.text('Meja'), findsOneWidget);
  });
}
