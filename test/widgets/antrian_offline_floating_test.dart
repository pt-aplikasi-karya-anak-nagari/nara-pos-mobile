import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:nara_pos_mobile/core/connectivity_service.dart';
import 'package:nara_pos_mobile/core/offline/offline_sync_service.dart';
import 'package:nara_pos_mobile/core/offline/sale_outbox.dart';
import 'package:nara_pos_mobile/core/offline/shift_outbox.dart';
import 'package:nara_pos_mobile/shared/widgets/antrian_offline_floating.dart';

// Floating antrian offline: kasir harus selalu tahu transaksi mana yang masih
// tersimpan di perangkat, dan kapan semuanya sudah sampai di server.

class _Menunggu extends PendingSyncCountNotifier {
  _Menunggu(this._n);
  final int _n;
  @override
  int build() => _n;
}

class _Gagal extends DeadLetterCountNotifier {
  _Gagal(this._n);
  final int _n;
  @override
  int build() => _n;
}

class _ShiftMenunggu extends PendingShiftSyncCountNotifier {
  _ShiftMenunggu(this._n);
  final int _n;
  @override
  int build() => _n;
}

class _ShiftGagal extends ShiftDeadLetterCountNotifier {
  _ShiftGagal(this._n);
  final int _n;
  @override
  int build() => _n;
}

class _Progres extends ProgresSinkronNotifier {
  _Progres(this._awal);
  final ProgresSinkron _awal;
  @override
  ProgresSinkron build() => _awal;
}

PendingSale _sale(String id, num total, {int attempts = 0, String? galat}) =>
    PendingSale(
      localId: id,
      outletId: 'o1',
      payload: {
        'final_amount': total,
        'payment_method': 'Tunai',
        'occurred_at': '2026-10-29T03:15:00Z',
        'items': [
          {'quantity': 2},
          {'quantity': 1},
        ],
      },
      createdAt: DateTime(2026, 10, 29, 10, 15),
      attempts: attempts,
      lastError: galat,
    );

Widget _app({
  int menunggu = 0,
  int gagal = 0,
  int shiftMenunggu = 0,
  int shiftGagal = 0,
  ConnectionStatus koneksi = ConnectionStatus.online,
  ProgresSinkron progres = const ProgresSinkron(),
  AntrianOffline antrian = const AntrianOffline(),
  void Function(WidgetRef ref)? pulihkan,
}) {
  return ProviderScope(
    overrides: [
      pendingSyncCountProvider.overrideWith(() => _Menunggu(menunggu)),
      deadLetterCountProvider.overrideWith(() => _Gagal(gagal)),
      pendingShiftSyncCountProvider.overrideWith(
        () => _ShiftMenunggu(shiftMenunggu),
      ),
      shiftDeadLetterCountProvider.overrideWith(() => _ShiftGagal(shiftGagal)),
      connectivityProvider.overrideWith((ref) => Stream.value(koneksi)),
      progresSinkronProvider.overrideWith(() => _Progres(progres)),
      antrianOfflineProvider.overrideWith((ref) async => antrian),
    ],
    // Dipasang di MaterialApp.builder — DI LUAR Navigator, persis seperti di
    // aplikasi. Widget yang butuh Overlay (mis. Tooltip) akan gagal di sini.
    child: MaterialApp(
      builder: (context, child) => Stack(
        children: [
          child!,
          Positioned.fill(
            child: AntrianOfflineFloating(bukaSheetPulihkan: pulihkan),
          ),
        ],
      ),
      home: const Scaffold(body: SizedBox.expand()),
    ),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  testWidgets('tidak tampil bila tak ada apa pun di antrian', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(find.byType(Material), findsWidgets);
    expect(find.textContaining('offline'), findsNothing);
    expect(find.textContaining('dikirim'), findsNothing);
  });

  testWidgets('offline: jumlah transaksi yang tersimpan di perangkat', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(menunggu: 3, koneksi: ConnectionStatus.offline),
    );
    await tester.pump();
    expect(find.text('3 tersimpan offline'), findsOneWidget);
  });

  testWidgets('online tapi belum terkirim: menunggu dikirim', (tester) async {
    await tester.pumpWidget(_app(menunggu: 2, shiftMenunggu: 1));
    await tester.pump();
    expect(find.text('3 menunggu dikirim'), findsOneWidget);
  });

  testWidgets('sedang mengirim: progres "x dari y"', (tester) async {
    await tester.pumpWidget(
      _app(
        menunggu: 4,
        progres: const ProgresSinkron(berjalan: true, total: 5, terkirim: 1),
      ),
    );
    await tester.pump();
    expect(find.text('Mengirim 2 dari 5'), findsOneWidget);
    final cincin = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(cincin.value, closeTo(0.2, 0.001));
  });

  testWidgets('yang gagal tetap terlihat walau ada antrian lain', (
    tester,
  ) async {
    await tester.pumpWidget(_app(menunggu: 2, gagal: 1, shiftGagal: 1));
    await tester.pump();
    expect(find.text('2 menunggu dikirim'), findsOneWidget);
    expect(find.text('2 gagal'), findsOneWidget);
  });

  testWidgets('selesai mengirim: tampil sebentar lalu hilang sendiri', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        progres: ProgresSinkron(
          selesaiPada: DateTime.now(),
          terkirimTerakhir: 3,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('3 terkirim'), findsOneWidget);

    await tester.pump(AntrianOfflineFloating.durasiSukses);
    await tester.pump();
    expect(find.text('3 terkirim'), findsNothing);
  });

  testWidgets('ketuk: rincian transaksi, tanpa crash di luar Navigator', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        menunggu: 2,
        koneksi: ConnectionStatus.offline,
        antrian: AntrianOffline(
          menunggu: [
            _sale('a', 45000),
            _sale('b', 18000, attempts: 2, galat: 'Server sibuk'),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('2 tersimpan offline'));
    await tester.pumpAndSettle();

    expect(find.text('Mode offline'), findsOneWidget);
    expect(find.textContaining('45.000'), findsOneWidget);
    expect(find.textContaining('18.000'), findsOneWidget);
    expect(find.text('3 item · Tunai'), findsNWidgets(2));
    expect(find.text('Coba 2/5'), findsOneWidget);
    expect(find.text('Server sibuk'), findsOneWidget);

    // Offline: tombol kirim nonaktif, dengan alasan yang jelas.
    final tombol = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Menunggu internet'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(tombol.onPressed, isNull);
  });

  testWidgets('Pulihkan membuka pemulihan untuk yang gagal', (tester) async {
    var dibuka = 0;
    await tester.pumpWidget(
      _app(
        gagal: 1,
        antrian: AntrianOffline(gagal: [_sale('x', 30000, attempts: 5)]),
        pulihkan: (_) => dibuka++,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('1 gagal terkirim'));
    await tester.pumpAndSettle();

    expect(find.text('Gagal'), findsOneWidget);
    await tester.tap(find.text('Pulihkan (1)'));
    expect(dibuka, 1);
  });
}
