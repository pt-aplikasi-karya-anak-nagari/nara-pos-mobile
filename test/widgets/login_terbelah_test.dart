import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sizer/sizer.dart';

import 'package:nara_pos_mobile/core/shared_prefs.dart';
import 'package:nara_pos_mobile/core/staff_device_storage.dart';
import 'package:nara_pos_mobile/features/user/data/auth_api_service.dart';
import 'package:nara_pos_mobile/features/user/data/auth_service.dart';
import 'package:nara_pos_mobile/features/user/ui/login_page.dart';
import 'package:nara_pos_mobile/features/user/ui/staff_session_page.dart';

// Tata letak halaman login: satu kolom di ponsel, terbelah dua di tablet
// mendatar.
//
// # YANG DIJAGA BERKAS INI
//
// Perangkat kasir dipakai dalam dua bentuk yang sangat berbeda — ponsel di
// tangan pemilik, dan tablet mendatar yang berdiri di konter sepanjang hari.
// Tata letak yang hanya diuji di satu ukuran akan pecah di ukuran lain, dan
// yang menemukannya kasir di tengah antrean.
//
// Dua kegagalan yang paling mungkin terjadi diam-diam:
//
//   1. Alur login TERGANDA — kalau kedua cabang tata letak masing-masing
//      membuat StaffSessionFlow sendiri, ketukan bisa mengenai salinan yang
//      tak terlihat, dan tak ada galat yang muncul.
//   2. OVERFLOW — keypad PIN membuat kolom login jauh lebih tinggi daripada
//      sebelumnya. Di layar pendek, kolom yang tak bisa digulir memunculkan
//      garis kuning-hitam alih-alih tombol.

class _StoragePalsu extends StaffDeviceStorage {
  @override
  Future<String?> bacaToken() async => 'token-perangkat';
  @override
  Future<String?> bacaOutletName() async => 'Outlet Uji';
  @override
  Future<String?> bacaOutletId() async => null;
  @override
  Future<void> hapus() async {}
}

class _AuthPalsu extends AuthNotifier {
  @override
  AuthState build() => const AuthState();

  @override
  Future<StaffSessionStart> resumeStaffSession({
    required String deviceToken,
  }) async => const StaffSessionStart(
    challengeId: 'ch-1',
    authorizerName: 'Pemilik Uji',
    authorizerEmail: 'pem***@uji.invalid',
    outletId: 'outlet-1',
    outlets: [StaffOutletOption(id: 'outlet-1', name: 'Outlet Uji')],
    staff: [
      StaffCandidate(
        id: 'staf-1',
        fullName: 'putra',
        username: 'putra',
        role: 'Kasir',
        hasPin: true,
      ),
    ],
  );
}

Future<void> _buka(WidgetTester tester, Size ukuran) async {
  tester.view.physicalSize = ukuran;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        staffDeviceStorageProvider.overrideWithValue(_StoragePalsu()),
        authProvider.overrideWith(_AuthPalsu.new),
      ],
      child: Sizer(builder: (_, _, _) => const MaterialApp(home: LoginPage())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ambang tata letak', () {
    test('ponsel & tablet tegak TIDAK dibelah', () {
      expect(tataLetakTerbelah(390), isFalse, reason: 'ponsel');
      expect(tataLetakTerbelah(768), isFalse, reason: 'tablet tegak');
      expect(
        tataLetakTerbelah(899),
        isFalse,
        reason:
            'tepat di bawah ambang — kartu login 460 + panel 340 tak muat, '
            'dan yang mengalah selalu lebar keypad PIN',
      );
    });

    test('tablet mendatar dibelah', () {
      expect(tataLetakTerbelah(900), isTrue, reason: 'tepat di ambang');
      expect(tataLetakTerbelah(1280), isTrue);
    });
  });

  testWidgets('layar lebar: panel merek tampil di samping login', (t) async {
    await _buka(t, const Size(1280, 800));
    expect(find.byKey(const ValueKey('login-logo-merek')), findsOneWidget);
    expect(find.text('NARA POS'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('layar sempit: panel merek TIDAK ikut tampil', (t) async {
    // Panel merek di layar ponsel akan memakan separuh lebar yang dibutuhkan
    // keypad PIN.
    await _buka(t, const Size(430, 900));
    expect(find.byKey(const ValueKey('login-logo-merek')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('alur login hanya ADA SATU di tiap tata letak', (t) async {
    // Dua salinan berarti ketukan bisa mengenai yang tak terlihat, dan tak ada
    // galat apa pun yang menjelaskan kenapa PIN-nya tak pernah terkirim.
    await _buka(t, const Size(1280, 800));
    expect(find.byType(StaffSessionFlow), findsOneWidget);

    await _buka(t, const Size(430, 900));
    expect(find.byType(StaffSessionFlow), findsOneWidget);
  });

  testWidgets('tidak overflow di layar tablet yang PENDEK', (t) async {
    // 1280x600: tablet mendatar berlayar pendek. Keypad PIN membuat kolom
    // login tinggi, jadi di sinilah overflow paling mungkin muncul.
    await _buka(t, const Size(1280, 600));
    expect(
      t.takeException(),
      isNull,
      reason: 'kolom login harus bisa digulir, bukan meluber',
    );
  });

  testWidgets('tidak overflow di ponsel kecil', (t) async {
    await _buka(t, const Size(360, 640));
    expect(t.takeException(), isNull);
  });
}
