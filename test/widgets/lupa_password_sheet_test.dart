import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:nara_pos_mobile/features/user/data/auth_api_service.dart';
import 'package:nara_pos_mobile/features/user/ui/widgets/forgot_password_sheet.dart';

// "Lupa password" Pemilik di aplikasi kasir HANYA mengirim tautan ke email.
// Password baru dibuat di website dari tautan itu — token reset tak pernah
// ditempel ke aplikasi, dan tak ada isian password baru di perangkat bersama.

class _ApiPalsu extends AuthApiService {
  _ApiPalsu() : super(Dio());
  final List<String> diminta = [];

  @override
  Future<void> requestPasswordReset(String email) async => diminta.add(email);
}

Future<_ApiPalsu> _buka(WidgetTester tester) async {
  final api = _ApiPalsu();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authApiServiceProvider.overrideWithValue(api)],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ForgotPasswordSheet()),
        ),
      ),
    ),
  );
  return api;
}

void main() {
  testWidgets('kirim tautan → layar konfirmasi berisi langkah', (tester) async {
    final api = await _buka(tester);

    await tester.enterText(
      find.byKey(const ValueKey('lupa-email')).last,
      'owner@uji.invalid',
    );
    await tester.tap(find.byKey(const ValueKey('lupa-kirim')));
    await tester.pumpAndSettle();

    expect(api.diminta, ['owner@uji.invalid']);
    expect(find.text('Cek email Anda'), findsOneWidget);
    expect(find.textContaining('berlaku 30 menit'), findsOneWidget);
    // Tak ada isian token / password baru di aplikasi.
    // (Teks boleh menyebut tombol "Buat Password Baru" di email — yang
    // dilarang adalah ISIAN di aplikasi.)
    expect(find.textContaining('Token'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('email tak valid tak dikirim', (tester) async {
    final api = await _buka(tester);

    await tester.enterText(
      find.byKey(const ValueKey('lupa-email')).last,
      'owner',
    );
    await tester.tap(find.byKey(const ValueKey('lupa-kirim')));
    await tester.pump();

    expect(api.diminta, isEmpty);
    expect(find.textContaining('email yang valid'), findsOneWidget);
  });
}
