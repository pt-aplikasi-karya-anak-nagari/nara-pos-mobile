import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nara_pos_mobile/core/shared_prefs.dart';
import 'package:nara_pos_mobile/core/staff_device_storage.dart';
import 'package:nara_pos_mobile/features/user/data/auth_api_service.dart';
import 'package:nara_pos_mobile/features/user/data/auth_service.dart';
import 'package:nara_pos_mobile/features/user/ui/staff_session_page.dart';

// Layar "Siapa yang bertugas?" — pilih nama, langsung bertugas.
//
// # PERUBAHAN PERILAKU YANG DIJAGA BERKAS INI
//
// Dulu perangkat yang hanya MENGINGAT pengesahan lama (punya device_token,
// Pemilik tak hadir) menuntut bukti ketiga: kode 6 digit ke email Pemilik, atau
// PIN. Sekarang tidak lagi — memilih nama langsung membuka sesi.
//
// Alasannya: bukti pengelola sudah lewat sebelum layar ini. device_token adalah
// 32 byte acak yang hanya terbit setelah Pemilik lolos password DI MESIN ITU,
// dan bisa dicabut kapan saja dari dashboard. Menahan kasir untuk bukti ketiga
// berarti menunggu email di depan mesin yang sedang dipakai melayani orang.
//
// Yang DILEPAS dan itu disengaja: bukti "siapa yang benar-benar berdiri di
// kasir". Batas keamanannya berpindah ke penguasaan fisik perangkat yang sudah
// disahkan.
//
// # KENAPA OTP & PIN TETAP DIUJI DI SINI
//
// Keduanya tidak dibuang, hanya tak lagi diminta di muka. Server masih
// menerimanya, dan aplikasi masih mengantar ke layar verifikasi bila jalur
// langsung DITOLAK — mis. staf sudah dinonaktifkan, atau outletnya berubah.
// Tanpa jalur cadangan itu, penolakan berarti layar buntu.

class _StoragePalsu extends StaffDeviceStorage {
  _StoragePalsu({this.token, this.outlet});
  final String? token;
  final String? outlet;

  @override
  Future<String?> bacaToken() async => token;
  @override
  Future<String?> bacaOutletName() async => outlet;
  @override
  Future<String?> bacaOutletId() async => null;
  @override
  Future<void> hapus() async {}
}

class _AuthPalsu extends AuthNotifier {
  int permintaanKode = 0;

  /// Ditolaknya jalur LANGSUNG (verifyStaffSession), terpisah dari galat kirim
  /// kode — dua kegagalan yang berbeda dan tak boleh saling menyamar.
  String? galatVerifikasi;
  String? galatKirimKode;
  bool stafPunyaPin = false;

  /// Kode yang diterima verifyStaffSession. String kosong = tanpa bukti kedua.
  final List<String> kodeDiverifikasi = [];

  @override
  AuthState build() => const AuthState();

  @override
  Future<StaffSessionStart> resumeStaffSession({
    required String deviceToken,
  }) async {
    return StaffSessionStart(
      challengeId: 'tantangan-1',
      authorizerName: 'Pemilik Uji',
      authorizerEmail: 'pem***@uji.invalid',
      outletId: 'OUT1',
      outlets: const [StaffOutletOption(id: 'OUT1', name: 'Outlet Uji')],
      staff: [
        StaffCandidate(
          id: 'E1',
          fullName: 'putra',
          role: 'Cashier',
          username: '',
          hasPin: stafPunyaPin,
        ),
      ],
    );
  }

  @override
  Future<StaffSessionStart> startStaffSession({
    required String email,
    required String password,
    required String outletId,
    String deviceLabel = '',
  }) async => resumeStaffSession(deviceToken: 'x');

  @override
  Future<String?> verifyStaffSession({
    required String challengeId,
    required String staffUserId,
    required String code,
  }) async {
    kodeDiverifikasi.add(code);
    // Kode kosong = jalur langsung. Kode terisi = jalur cadangan, yang di tes
    // ini selalu diterima supaya kegagalan langkah pertama tak menyamar
    // sebagai kegagalan langkah kedua.
    return code.isEmpty ? galatVerifikasi : null;
  }

  @override
  Future<String> requestStaffSessionOtp({
    required String challengeId,
    required String staffUserId,
  }) async {
    permintaanKode++;
    if (galatKirimKode != null) throw galatKirimKode!;
    return 'pem***@uji.invalid';
  }
}

/// Perangkat yang SUDAH disahkan (punya device_token). Pemilik tak hadir.
Future<_AuthPalsu> _bukaTersimpan(
  WidgetTester tester, {
  String? galatVerifikasi,
  String? galatKirimKode,
  bool stafPunyaPin = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final auth = _AuthPalsu()
    ..galatVerifikasi = galatVerifikasi
    ..galatKirimKode = galatKirimKode
    ..stafPunyaPin = stafPunyaPin;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        staffDeviceStorageProvider.overrideWithValue(
          _StoragePalsu(token: 'token-perangkat', outlet: 'Outlet Uji'),
        ),
        authProvider.overrideWith(() => auth),
      ],
      child: MaterialApp(home: Scaffold(body: StaffSessionFlow(onSelesai: () {}))),
    ),
  );
  await tester.pump(); // useEffect pemulihan perangkat
  await tester.pump();
  return auth;
}

/// Perangkat BARU tanpa device_token. Pemilik mengetik kredensialnya di sini.
Future<_AuthPalsu> _bukaTanpaPerangkat(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final auth = _AuthPalsu();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        staffDeviceStorageProvider.overrideWithValue(_StoragePalsu()),
        authProvider.overrideWith(() => auth),
      ],
      child: MaterialApp(home: Scaffold(body: StaffSessionFlow(onSelesai: () {}))),
    ),
  );
  await tester.pump();
  await tester.pump();
  return auth;
}

void main() {
  // ── Pilih nama, langsung bertugas ────────────────────────────────────────

  testWidgets('perangkat tersimpan → pilih staf LANGSUNG masuk, tanpa kode',
      (tester) async {
    final auth = await _bukaTersimpan(tester);

    // Positifnya lebih dulu: kalau layarnya tak pernah tercapai, semua
    // pernyataan setelahnya kehilangan arti.
    expect(find.text('putra'), findsOneWidget);

    await tester.tap(find.text('putra'));
    await tester.pump();

    // Tak ada email yang dikirim, dan verifikasinya dipanggil dengan kode
    // KOSONG — penanda "tanpa bukti kedua" yang dibaca server.
    expect(auth.permintaanKode, 0);
    expect(auth.kodeDiverifikasi, ['']);
  });

  testWidgets('Pemilik hadir → pilih staf langsung masuk, tanpa kode',
      (tester) async {
    final auth = await _bukaTanpaPerangkat(tester);

    final isian = find.byType(TextField);
    await tester.enterText(isian.at(0), 'owner@uji.invalid');
    await tester.enterText(isian.at(1), 'rahasia');
    await tester.tap(find.text('Lanjut'));
    await tester.pump();

    await tester.tap(find.text('putra'));
    await tester.pump();

    expect(auth.permintaanKode, 0);
    expect(auth.kodeDiverifikasi, ['']);
  });

  testWidgets('layarnya tidak lagi menjanjikan kode yang tak akan dikirim',
      (tester) async {
    // Teks lama berbunyi "Kode verifikasi akan dikirim ke pem***@uji.invalid".
    // Membiarkannya berarti aplikasi menjanjikan email yang tak pernah datang —
    // orang akan menunggu, lalu membuka kotak masuk, lalu mengira ada yang rusak.
    await _bukaTersimpan(tester);

    expect(find.textContaining('Kode verifikasi akan dikirim'), findsNothing);
    expect(find.textContaining('Pilih nama untuk mulai bertugas'), findsOneWidget);
    // Nama pengotorisasinya tetap disebut — itu yang menjelaskan atas restu
    // siapa sesi ini terbit.
    expect(find.textContaining('Pemilik Uji'), findsOneWidget);
  });

  // ── Jalur cadangan saat yang langsung DITOLAK ────────────────────────────

  testWidgets('penolakan server mengantar ke verifikasi, bukan jalan buntu',
      (tester) async {
    // Jalur langsung bisa ditolak: staf dinonaktifkan, keanggotaan outlet
    // dicabut, perangkat di-revoke. Tanpa jalur cadangan, penolakan berarti
    // layar mati di depan mesin kasir yang sedang dipakai.
    final auth = await _bukaTersimpan(
      tester,
      galatVerifikasi: 'staf itu tidak bisa bertugas di outlet ini',
    );

    await tester.tap(find.text('putra'));
    await tester.pump();

    expect(find.textContaining('staf itu tidak bisa bertugas'), findsOneWidget);
    expect(find.textContaining('Setujui sesi putra'), findsOneWidget);
    expect(auth.kodeDiverifikasi, ['']);
  });

  testWidgets('di layar cadangan, kirim ulang kode BEKERJA', (tester) async {
    final auth = await _bukaTersimpan(tester, galatVerifikasi: 'ditolak');
    await tester.tap(find.text('putra'));
    await tester.pump();

    // Kode belum pernah dikirim — jalur langsung tak mengirim apa pun.
    expect(auth.permintaanKode, 0);

    await tester.tap(find.text('Kirim ulang kode'));
    await tester.pump();

    expect(auth.permintaanKode, 1);
    expect(find.textContaining('Kode baru dikirim'), findsOneWidget);
  });

  testWidgets('sesudah dipakai, tombolnya berjeda dengan hitungan terbaca',
      (tester) async {
    final auth = await _bukaTersimpan(tester, galatVerifikasi: 'ditolak');
    await tester.tap(find.text('putra'));
    await tester.pump();
    await tester.tap(find.text('Kirim ulang kode'));
    await tester.pump();

    // Hitungannya ditulis di label. Tombol yang mati tanpa alasan terbaca
    // sebagai aplikasi yang macet, dan orang akan menekannya berkali-kali.
    expect(find.textContaining('Kirim ulang kode dalam'), findsOneWidget);

    await tester.tap(find.textContaining('Kirim ulang kode dalam'));
    await tester.pump();
    expect(auth.permintaanKode, 1);

    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Kirim ulang kode'), findsOneWidget);

    await tester.tap(find.text('Kirim ulang kode'));
    await tester.pump();
    expect(auth.permintaanKode, 2);
  });

  testWidgets('kode lama dibersihkan saat yang baru dikirim', (tester) async {
    await _bukaTersimpan(tester, galatVerifikasi: 'ditolak');
    await tester.tap(find.text('putra'));
    await tester.pump();

    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.pump();

    await tester.tap(find.text('Kirim ulang kode'));
    await tester.pump();

    // Kode lama tak berlaku lagi begitu yang baru terbit. Membiarkannya
    // terketik membuat percobaan pertama sesudah kirim ulang pasti gagal —
    // dan orangnya menyangka kode barunya yang salah.
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('kegagalan kirim kode sampai apa adanya, tanpa disamarkan',
      (tester) async {
    await _bukaTersimpan(
      tester,
      galatVerifikasi: 'ditolak',
      galatKirimKode: 'sesi otorisasi sudah kedaluwarsa, ulangi dari awal',
    );
    await tester.tap(find.text('putra'));
    await tester.pump();
    await tester.tap(find.text('Kirim ulang kode'));
    await tester.pump();

    expect(find.textContaining('sesi otorisasi sudah kedaluwarsa'), findsOneWidget);
  });

  // ── Kata-kata di layar cadangan menyesuaikan keadaan staf ────────────────

  testWidgets('staf BER-PIN diarahkan memakai PIN-nya sendiri', (tester) async {
    // Layar ini pernah selalu menyuruh memakai "PIN otorisasi Anda" — yang
    // dimaksud PIN PEMILIK, bukan PIN staf. Staf yang sudah diberi PIN dari
    // dashboard tak punya cara tahu bahwa PIN itulah yang diminta.
    await _bukaTersimpan(tester, galatVerifikasi: 'ditolak', stafPunyaPin: true);
    await tester.tap(find.text('putra'));
    await tester.pump();

    // Tiba di layar cadangan TANPA kode pernah dikirim: yang diminta hanya
    // PIN-nya, dan tak boleh menyebut-nyebut email yang belum dikirim ke mana pun.
    expect(find.textContaining('Masukkan PIN putra'), findsOneWidget);
    expect(find.textContaining('Belum punya PIN atau lupa'), findsNothing);

    // Sesudah kode diminta, jalan cadangan lewat email BARU disebut — bukan
    // dihilangkan, supaya staf yang lupa PIN tetap punya jalan keluar.
    await tester.tap(find.text('Kirim ulang kode'));
    await tester.pump();
    expect(find.textContaining('Belum punya PIN atau lupa'), findsOneWidget);
  });

  testWidgets('staf TANPA PIN tetap diarahkan ke kode email', (tester) async {
    // Sisi sebaliknya. Menyuruh semua orang mengetik "PIN Anda" akan
    // menyesatkan staf yang memang belum diberi PIN — mereka akan mencoba
    // menebak PIN yang tak pernah ada.
    await _bukaTersimpan(tester, galatVerifikasi: 'ditolak', stafPunyaPin: false);
    await tester.tap(find.text('putra'));
    await tester.pump();

    expect(find.textContaining('Masukkan PIN putra'), findsNothing);
  });
}
