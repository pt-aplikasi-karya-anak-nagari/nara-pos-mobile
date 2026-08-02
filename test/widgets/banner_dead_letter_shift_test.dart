import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:nara_pos_mobile/core/offline/sale_outbox.dart';
import 'package:nara_pos_mobile/core/offline/shift_outbox.dart';
import 'package:nara_pos_mobile/shared/widgets/pending_sync_banner.dart';

// Catatan buka/tutup shift yang gagal permanen tak pernah tampil di UI mana pun.
//
// # KEJADIANNYA
//
// shiftDeadLetterCountProvider sudah ada dan sudah dihitung — tapi satu-satunya
// yang membacanya adalah penyinkron, untuk menyegarkan angkanya sendiri. Tak ada
// satu pun widget yang menampilkannya.
//
// Jadi ketika kasir menutup shift saat luring dan server menolaknya permanen,
// actual_balance dan catatan penutupnya hilang diam-diam: tak sampai ke server,
// dan tak bisa dipulihkan dari aplikasi. Z-Report untuk shift itu tak pernah
// terbit, dan rekonsiliasi kas hari itu tak bisa diselesaikan.
//
// # YANG DIJAGA
//
// Bukan "ada widget baru", melainkan angkanya benar-benar sampai ke mata orang.
// Sebuah provider yang dihitung rajin tapi tak pernah dirender sama saja dengan
// tidak ada.

// Tiap provider hitungan punya tipe notifier sendiri, jadi override-nya harus
// mewarisi tipe yang tepat — bukan satu kelas serbaguna.
class _PenjualanMenunggu extends PendingSyncCountNotifier {
  _PenjualanMenunggu(this._n);
  final int _n;
  @override
  int build() => _n;
}

class _PenjualanGagal extends DeadLetterCountNotifier {
  _PenjualanGagal(this._n);
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

Widget _banner({
  int penjualanMenunggu = 0,
  int penjualanGagal = 0,
  int shiftMenunggu = 0,
  int shiftGagal = 0,
}) {
  return ProviderScope(
    overrides: [
      pendingSyncCountProvider.overrideWith(() => _PenjualanMenunggu(penjualanMenunggu)),
      deadLetterCountProvider.overrideWith(() => _PenjualanGagal(penjualanGagal)),
      pendingShiftSyncCountProvider.overrideWith(() => _ShiftMenunggu(shiftMenunggu)),
      shiftDeadLetterCountProvider.overrideWith(() => _ShiftGagal(shiftGagal)),
    ],
    child: const MaterialApp(
      home: Scaffold(body: PendingSyncBanner()),
    ),
  );
}

void main() {
  testWidgets('shift yang gagal permanen MUNCUL di banner', (tester) async {
    await tester.pumpWidget(_banner(shiftGagal: 2));
    await tester.pump();

    expect(
      find.textContaining('catatan buka/tutup shift gagal'),
      findsOneWidget,
      reason: 'angkanya dihitung tapi tak pernah sampai ke mata kasir — '
          'catatan uang laci hilang tanpa ada yang tahu',
    );
    // Harus ada jalan keluarnya, bukan sekadar pemberitahuan.
    expect(find.text('Pulihkan'), findsWidgets);
  });

  testWidgets('muncul WALAU tak ada penjualan yang gagal', (tester) async {
    // Kasus paling mungkin di lapangan: penjualannya terkirim semua, yang
    // tersangkut hanya catatan tutup shift. Kalau banner shift menempel pada
    // ada-tidaknya penjualan gagal, justru kasus ini yang tak pernah terlihat.
    await tester.pumpWidget(_banner(penjualanGagal: 0, shiftGagal: 1));
    await tester.pump();

    expect(find.textContaining('catatan buka/tutup shift gagal'), findsOneWidget);
    expect(find.textContaining('transaksi gagal terkirim'), findsNothing);
  });

  testWidgets('tidak muncul kalau memang tak ada yang gagal', (tester) async {
    // Sisi sebaliknya. Banner permanen yang selalu ada akan diabaikan orang,
    // dan saat benar-benar ada masalah tak ada yang membacanya lagi.
    await tester.pumpWidget(_banner());
    await tester.pump();

    expect(find.byType(PendingSyncBanner), findsOneWidget);
    expect(find.textContaining('gagal'), findsNothing);
    expect(find.textContaining('menunggu'), findsNothing);
  });

  testWidgets('penjualan gagal dan shift gagal tampil BERSAMAAN', (tester) async {
    // Keduanya punya sumber sendiri; satu tak boleh menutupi yang lain.
    await tester.pumpWidget(_banner(penjualanGagal: 3, shiftGagal: 2));
    await tester.pump();

    expect(find.textContaining('3 transaksi gagal terkirim'), findsOneWidget);
    expect(find.textContaining('2 catatan buka/tutup shift gagal'), findsOneWidget);
  });
}
