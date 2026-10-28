import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nara_pos_mobile/core/auth_storage.dart';
import 'package:nara_pos_mobile/core/connectivity_service.dart';
import 'package:nara_pos_mobile/core/outlet_scope.dart';
import 'package:nara_pos_mobile/core/shared_prefs.dart';
import 'package:nara_pos_mobile/features/kasir/providers.dart';
import 'package:nara_pos_mobile/features/kasir/ui/widgets/product_card.dart';
import 'package:nara_pos_mobile/features/outlet/data/outlet_service.dart';
import 'package:nara_pos_mobile/features/products/domain/product.dart';

// Laporan: saat offline, mengetuk produk tidak melakukan apa-apa — transaksi
// tak bisa dibuat sama sekali.
//
// # SEBABNYA
//
// Sebelum item masuk keranjang, kartu mengambil grup add-on produk dari
// server. Saat offline permintaan itu tetap dikirim dan baru menyerah setelah
// jaringan gagal (di Wi-Fi tanpa internet: sampai batas waktu 10 detik,
// ditambah percobaan ulang otomatis). Selama itu tombol "+" tampak mati.
//
// # YANG DIJAGA
//
// Server yang TAK PERNAH menjawab tidak boleh menahan kasir: offline → item
// masuk seketika; online tapi server diam → item tetap masuk setelah batas
// tunggu yang pendek.

class _ServerDiam extends OutletService {
  _ServerDiam() : super(Dio());
  int dipanggil = 0;

  @override
  Future<List<Map<String, dynamic>>> getProductModifierGroups(
    String outletId,
    String productId,
  ) {
    dipanggil++;
    return Completer<List<Map<String, dynamic>>>().future; // tak pernah selesai
  }
}

late SharedPreferences _prefs;

Future<ProviderContainer> _pasang(
  WidgetTester tester,
  _ServerDiam server, {
  required ConnectionStatus koneksi,
}) async {
  SharedPreferences.setMockInitialValues({});
  _prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStorageProvider.overrideWithValue(AuthStorage(_prefs)),
        sharedPreferencesProvider.overrideWithValue(_prefs),
        connectivityProvider.overrideWith((ref) => Stream.value(koneksi)),
        activeOutletIdProvider.overrideWithValue('o1'),
        outletServiceProvider.overrideWithValue(server),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 180,
              child: IntrinsicHeight(
                child: ProductCard(
                  product: Product(
                    remoteId: 'p1',
                    name: 'Susu',
                    price: 10000,
                    trackStock: false,
                  ),
                  lebarKartu: 180,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final c = ProviderScope.containerOf(tester.element(find.byType(ProductCard)));
  // Di aplikasi, status koneksi selalu dipantau (banner koneksi). Tanpa
  // pemantau, StreamProvider-nya belum punya nilai dan dianggap online.
  c.listen(connectivityProvider, (_, _) {});
  await tester.pump();
  await tester.pump();
  return c;
}

void main() {
  testWidgets(
    'offline: ketuk produk → langsung masuk keranjang, tanpa server',
    (tester) async {
      final server = _ServerDiam();
      final c = await _pasang(
        tester,
        server,
        koneksi: ConnectionStatus.offline,
      );

      // runAsync: salinan lokal dibaca lewat kanal platform (SQLite), yang di
      // tes widget hanya selesai di waktu nyata. Batas 1 detik — jauh di bawah
      // batas tunggu jaringan — membuktikan tak ada yang menunggu server.
      await tester.tap(find.text('Susu'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      expect(
        c.read(cartProvider).length,
        1,
        reason: 'item harus masuk seketika',
      );
      expect(
        server.dipanggil,
        0,
        reason: 'offline tak boleh menyentuh jaringan',
      );

      // Habiskan pewaktu yang masih berjalan (batas tunggu, dsb.).
      await tester.pump(const Duration(seconds: 10));
    },
  );

  testWidgets('online tapi server diam: tetap masuk setelah batas tunggu', (
    tester,
  ) async {
    final server = _ServerDiam();
    final c = await _pasang(tester, server, koneksi: ConnectionStatus.online);

    await tester.tap(find.text('Susu'));
    await tester.pump(const Duration(seconds: 1));
    expect(c.read(cartProvider), isEmpty, reason: 'masih menunggu server');

    await tester.pump(const Duration(seconds: 5));
    expect(c.read(cartProvider).length, 1);
    expect(server.dipanggil, 1);
  });
}
