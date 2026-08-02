import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nara_pos_mobile/features/kasir/ui/widgets/dialog_bukti_qris.dart';

// Dialog verifikasi bukti pembayaran QRIS di kasir.
//
// # DUA HAL YANG DIJAGA
//
// BUKTINYA TAMPIL DI DALAM DIALOG. Sebelumnya kasir mengonfirmasi lewat dialog
// yang hanya menulis metode dan total; buktinya di tombol "Lihat" terpisah
// yang tak wajib ditekan. Konfirmasi buta meniadakan gunanya bukti — pelanggan
// mana pun bisa meng-upload gambar apa pun, dan kasir yang sibuk menekan
// "Terima" tanpa pernah melihatnya.
//
// TIDAK ADA PEMILIH METODE. Pembayarannya sudah TERJADI di ponsel pelanggan
// sebelum dialog ini terbuka. Pemilih metode di sini mengundang kasir menimpa
// metode yang benar dan membuang tautan buktinya.

Future<AksiBukti?> buka(
  WidgetTester tester, {
  String url = 'https://server.invalid/uploads/bukti.jpg',
}) async {
  AksiBukti? hasil;
  var selesai = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                hasil = await showDialog<AksiBukti>(
                  context: ctx,
                  builder: (_) => DialogBuktiQris(
                    urlBukti: url,
                    metode: 'QRIS',
                    total: 11000,
                  ),
                );
                selesai = true;
              },
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('buka'));
  await tester.pumpAndSettle();
  return selesai ? hasil : null;
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('bukti pembayaran TAMPIL di dalam dialog', (tester) async {
    await buka(tester);
    // Image.network di lingkungan tes selalu gagal memuat (HTTP diblokir) —
    // yang dijaga adalah widget gambarnya ADA di pohon, bukan pikselnya.
    expect(
      find.byType(Image),
      findsOneWidget,
      reason:
          'tak ada widget gambar — kasir kembali mengonfirmasi buta seperti '
          'dialog lama yang hanya menulis metode dan total',
    );
    expect(
      find.byType(InteractiveViewer),
      findsOneWidget,
      reason: 'nominal di tangkapan layar harus bisa di-zoom',
    );
    // Bersihkan pending timer image sebelum tes berakhir.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('TIDAK ada pemilih metode pembayaran', (tester) async {
    await buka(tester);
    for (final teks in ['Tunai', 'Kartu', 'Transfer', 'Pilih Pembayaran']) {
      expect(
        find.textContaining(teks),
        findsNothing,
        reason:
            'ada "$teks" — dialog ini berubah jadi pemilih metode, padahal '
            'pembayarannya sudah terjadi',
      );
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('Konfirmasi Pembayaran mengembalikan terima', (tester) async {
    AksiBukti? hasil;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                hasil = await showDialog<AksiBukti>(
                  context: ctx,
                  builder: (_) => const DialogBuktiQris(
                    urlBukti: '',
                    metode: 'QRIS',
                    total: 11000,
                  ),
                );
              },
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bukti-terima')));
    await tester.pumpAndSettle();
    expect(hasil, AksiBukti.terima);
  });

  testWidgets('Tolak Bukti mengembalikan tolak', (tester) async {
    AksiBukti? hasil;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                hasil = await showDialog<AksiBukti>(
                  context: ctx,
                  builder: (_) => const DialogBuktiQris(
                    urlBukti: '',
                    metode: 'QRIS',
                    total: 11000,
                  ),
                );
              },
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bukti-tolak')));
    await tester.pumpAndSettle();
    expect(
      hasil,
      AksiBukti.tolak,
      reason:
          'tanpa jalur tolak, satu-satunya pilihan kasir atas bukti buram '
          'adalah menerimanya — dan alur upload-ulang di halaman pelanggan '
          'tak pernah bisa terpicu dari perangkat kasir',
    );
  });

  testWidgets('menutup tanpa memilih mengembalikan null (batal)', (
    tester,
  ) async {
    var dipanggil = false;
    AksiBukti? hasil;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                hasil = await showDialog<AksiBukti>(
                  context: ctx,
                  builder: (_) => const DialogBuktiQris(
                    urlBukti: '',
                    metode: 'QRIS',
                    total: 11000,
                  ),
                );
                dipanggil = true;
              },
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    // Ketuk barrier di luar dialog.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(dipanggil, isTrue);
    expect(hasil, isNull, reason: 'batal tak boleh dibaca sebagai keputusan');
  });
}
