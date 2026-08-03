import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nara_pos_mobile/core/shared_prefs.dart';
import 'package:nara_pos_mobile/core/staff_device_storage.dart';
import 'package:nara_pos_mobile/features/user/data/auth_api_service.dart';
import 'package:nara_pos_mobile/features/user/data/auth_service.dart';
import 'package:nara_pos_mobile/features/user/ui/staff_session_page.dart';
import 'package:nara_pos_mobile/features/user/ui/widgets/keypad_kode.dart';

// Layar "Siapa yang bertugas?" — pilih nama, lalu masukkan PIN.
//
// # PERILAKU YANG DIJAGA BERKAS INI
//
// Memilih nama TIDAK memanggil jaringan sama sekali: ia hanya berpindah ke
// layar PIN. Kode email tidak dikirim otomatis, karena PIN-nya sudah ada di
// tangan kasir — mengirimnya berarti membanjiri kotak masuk Pemilik dengan kode
// yang tak seorang pun akan pakai, setiap pergantian giliran.
//
// Sempat ada jalur "pilih nama langsung masuk", lalu dicabut bersamaan dengan
// PIN kini dibuat otomatis oleh server saat karyawan ditambahkan. Alasannya
// bukan berbalik pikiran: masuk-langsung dipilih ketika PIN pada praktiknya TAK
// BISA DIBAGIKAN. Begitu PIN lahir bersama karyawannya dan bisa disalin dari
// dashboard, hambatan itu hilang — dan yang tersisa hanya keuntungannya, yaitu
// jejak transaksi kembali menunjuk orang yang mengetikkan sesuatu yang hanya ia
// tahu.
//
// Tombol "Kirim ulang kode" tetap ada untuk yang lupa PIN-nya.

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

/// Mengetik kode lewat KEYPAD, bukan papan ketik OS.
///
/// Kode 6 digit TERKIRIM OTOMATIS di digit terakhir — jadi jangan menambahkan
/// ketukan "Mulai sesi" sesudahnya, karena itu mengirim permintaan kedua dan
/// membuat tes menghitung dua kali sesuatu yang di aplikasi hanya sekali.
Future<void> _ketikKode(WidgetTester tester, String kode) async {
  for (final d in kode.split('')) {
    final tombol = find.byKey(ValueKey('keypad-$d'));
    await tester.ensureVisible(tombol);
    await tester.tap(tombol);
    await tester.pump();
  }
}

class _AuthPalsu extends AuthNotifier {
  int permintaanKode = 0;

  /// Ditolaknya PIN/kode oleh server, terpisah dari galat KIRIM kode — dua
  /// kegagalan yang berbeda dan tak boleh saling menyamar.
  String? galatPin;
  String? galatKirimKode;

  /// Default TRUE: sesudah PIN dibuat otomatis saat karyawan ditambahkan,
  /// karyawan tanpa PIN hanya tersisa dari sebelum perubahan itu.
  bool stafPunyaPin = true;

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
    return galatPin;
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
  String? galatPin,
  String? galatKirimKode,
  bool stafPunyaPin = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final auth = _AuthPalsu()
    ..galatPin = galatPin
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
      child: MaterialApp(
        home: Scaffold(
          // SingleChildScrollView meniru KEDUA pemanggil sungguhan
          // (LoginPage & StaffSessionPage). Tanpa itu harness ini lebih
          // sempit daripada aplikasinya, dan konten yang wajar-wajar saja
          // tampak sebagai overflow yang tak pernah dialami siapa pun.
          body: SingleChildScrollView(
            child: StaffSessionFlow(onSelesai: () {}),
          ),
        ),
      ),
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
      child: MaterialApp(
        home: Scaffold(
          // SingleChildScrollView meniru KEDUA pemanggil sungguhan
          // (LoginPage & StaffSessionPage). Tanpa itu harness ini lebih
          // sempit daripada aplikasinya, dan konten yang wajar-wajar saja
          // tampak sebagai overflow yang tak pernah dialami siapa pun.
          body: SingleChildScrollView(
            child: StaffSessionFlow(onSelesai: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return auth;
}

void main() {
  // ── Pilih nama, langsung bertugas ────────────────────────────────────────

  testWidgets('perangkat tersimpan → pilih staf antar ke layar PIN', (
    tester,
  ) async {
    final auth = await _bukaTersimpan(tester);

    // Positifnya lebih dulu: kalau layarnya tak pernah tercapai, semua
    // pernyataan setelahnya kehilangan arti.
    expect(find.text('putra'), findsOneWidget);

    await tester.tap(find.text('putra'));
    await tester.pump();

    // TIDAK ada panggilan jaringan: tak ada kode dikirim, tak ada verifikasi
    // dicoba. Memilih nama hanyalah berpindah layar.
    expect(auth.permintaanKode, 0);
    expect(auth.kodeDiverifikasi, isEmpty);
    expect(find.textContaining('Masukkan PIN putra'), findsOneWidget);
  });

  testWidgets('Pemilik hadir → tetap diminta PIN, bukan langsung masuk', (
    tester,
  ) async {
    // Password Pemilik membuktikan siapa yang MENYETUJUI, bukan siapa yang
    // akan bertugas. PIN-lah yang menjawab pertanyaan kedua, dan itu yang
    // membuat jejak transaksinya berarti.
    final auth = await _bukaTanpaPerangkat(tester);

    final isian = find.byType(TextField);
    await tester.enterText(isian.at(0), 'owner@uji.invalid');
    await tester.enterText(isian.at(1), 'rahasia');
    await tester.tap(find.text('Lanjut'));
    await tester.pump();

    await tester.tap(find.text('putra'));
    await tester.pump();

    expect(auth.kodeDiverifikasi, isEmpty);
    expect(find.textContaining('Masukkan PIN putra'), findsOneWidget);
  });

  testWidgets('layarnya menyebut PIN, bukan menjanjikan email', (tester) async {
    // Teks lama berbunyi "Kode verifikasi akan dikirim ke pem***@uji.invalid".
    // Membiarkannya berarti aplikasi menjanjikan email yang tak pernah datang —
    // orang akan menunggu, membuka kotak masuk, lalu mengira ada yang rusak.
    await _bukaTersimpan(tester);

    expect(find.textContaining('Kode verifikasi akan dikirim'), findsNothing);
    expect(
      find.textContaining('Pilih nama, lalu masukkan PIN'),
      findsOneWidget,
    );
    // Nama pengotorisasinya tetap disebut — itu yang menjelaskan atas restu
    // siapa sesi ini terbit.
    expect(find.textContaining('Pemilik Uji'), findsOneWidget);
  });

  testWidgets('PIN yang diketik benar-benar dikirim ke server', (tester) async {
    final auth = await _bukaTersimpan(tester, stafPunyaPin: true);
    await tester.tap(find.text('putra'));
    await tester.pump();

    // 6 digit -> terkirim otomatis di digit terakhir; tak perlu menekan
    // "Mulai sesi" (menekannya justru mengirim permintaan kedua).
    await _ketikKode(tester, '246810');

    expect(auth.kodeDiverifikasi, ['246810']);
  });

  testWidgets('PIN 4 digit dikirim lewat TOMBOL, bukan otomatis', (
    tester,
  ) async {
    // Server menerima 4-6 digit. Keypad yang hanya mengirim saat 6 titik penuh
    // akan mengunci setiap staf ber-PIN 4 digit di luar aplikasi — tanpa satu
    // pun pesan yang menjelaskan sebabnya. Karena itu tombol "Mulai sesi"
    // tidak boleh dihapus dari layar ini.
    final auth = await _bukaTersimpan(tester, stafPunyaPin: true);
    await tester.tap(find.text('putra'));
    await tester.pump();

    await _ketikKode(tester, '5029');
    expect(
      auth.kodeDiverifikasi,
      isEmpty,
      reason:
          '4 digit belum boleh terkirim otomatis — staf ber-PIN 6 digit '
          'akan mengirim separuh PIN-nya',
    );

    final tombol = find.text('Mulai sesi');
    await tester.ensureVisible(tombol);
    await tester.tap(tombol);
    await tester.pump();

    expect(auth.kodeDiverifikasi, ['5029']);
  });

  // ── Jalur cadangan saat yang langsung DITOLAK ────────────────────────────

  testWidgets('penolakan server sampai apa adanya, tanpa disamarkan', (
    tester,
  ) async {
    // PIN bisa ditolak karena bukan salah ketik: staf dinonaktifkan,
    // keanggotaan outlet dicabut, perangkat di-revoke. Mengubah semuanya jadi
    // "PIN salah" akan membuat kasir mencoba lagi berkali-kali dengan PIN yang
    // sebenarnya benar.
    final auth = await _bukaTersimpan(
      tester,
      galatPin: 'staf itu tidak bisa bertugas di outlet ini',
      stafPunyaPin: true,
    );

    await tester.tap(find.text('putra'));
    await tester.pump();
    await _ketikKode(tester, '246810');

    expect(find.textContaining('staf itu tidak bisa bertugas'), findsOneWidget);
    expect(auth.kodeDiverifikasi, ['246810']);
  });

  testWidgets('di layar cadangan, kirim ulang kode BEKERJA', (tester) async {
    final auth = await _bukaTersimpan(tester, galatPin: 'PIN salah');
    await tester.tap(find.text('putra'));
    await tester.pump();

    // Kode belum pernah dikirim — jalur langsung tak mengirim apa pun.
    expect(auth.permintaanKode, 0);

    await tester.tap(find.text('Kirim ulang kode'));
    await tester.pump();

    expect(auth.permintaanKode, 1);
    expect(find.textContaining('Kode baru dikirim'), findsOneWidget);
  });

  testWidgets('sesudah dipakai, tombolnya berjeda dengan hitungan terbaca', (
    tester,
  ) async {
    final auth = await _bukaTersimpan(tester, galatPin: 'PIN salah');
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
    await _bukaTersimpan(tester, galatPin: 'PIN salah');
    await tester.tap(find.text('putra'));
    await tester.pump();

    await _ketikKode(tester, '123456');

    await tester.tap(find.text('Kirim ulang kode'));
    await tester.pump();

    // Kode lama tak berlaku lagi begitu yang baru terbit. Membiarkannya
    // terketik membuat percobaan pertama sesudah kirim ulang pasti gagal —
    // dan orangnya menyangka kode barunya yang salah.
    final keypad = tester.widget<KeypadKode>(find.byType(KeypadKode));
    expect(keypad.nilai, isEmpty);
  });

  testWidgets('kegagalan kirim kode sampai apa adanya, tanpa disamarkan', (
    tester,
  ) async {
    await _bukaTersimpan(
      tester,
      galatPin: 'PIN salah',
      galatKirimKode: 'sesi otorisasi sudah kedaluwarsa, ulangi dari awal',
    );
    await tester.tap(find.text('putra'));
    await tester.pump();
    await tester.tap(find.text('Kirim ulang kode'));
    await tester.pump();

    expect(
      find.textContaining('sesi otorisasi sudah kedaluwarsa'),
      findsOneWidget,
    );
  });

  // ── Kata-kata di layar cadangan menyesuaikan keadaan staf ────────────────

  testWidgets('staf BER-PIN diarahkan memakai PIN-nya sendiri', (tester) async {
    // Layar ini pernah selalu menyuruh memakai "PIN otorisasi Anda" — yang
    // dimaksud PIN PEMILIK, bukan PIN staf. Staf yang sudah diberi PIN dari
    // dashboard tak punya cara tahu bahwa PIN itulah yang diminta.
    await _bukaTersimpan(tester, galatPin: 'PIN salah', stafPunyaPin: true);
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
    await _bukaTersimpan(tester, galatPin: 'PIN salah', stafPunyaPin: false);
    await tester.tap(find.text('putra'));
    await tester.pump();

    expect(find.textContaining('Masukkan PIN putra'), findsNothing);
  });
}
