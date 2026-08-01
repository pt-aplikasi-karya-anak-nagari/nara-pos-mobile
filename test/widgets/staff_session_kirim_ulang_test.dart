import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nara_pos_mobile/core/shared_prefs.dart';
import 'package:nara_pos_mobile/core/staff_device_storage.dart';
import 'package:nara_pos_mobile/features/user/data/auth_api_service.dart';
import 'package:nara_pos_mobile/features/user/data/auth_service.dart';
import 'package:nara_pos_mobile/features/user/ui/staff_session_page.dart';

// Tombol "Kirim ulang kode" di layar persetujuan sesi kasir.
//
// # KENAPA LAYAR INI PERNAH BUNTU
//
// Kode 6 digit dikirim ke email Pemilik, dan satu-satunya jalan meminta kode
// baru adalah menekan "Kembali", memilih ulang stafnya, lalu mengetik ulang —
// pada perangkat yang belum disahkan itu berarti mengetik ulang password
// Pemilik. Kode yang telat sampai, terhapus, atau salah ketik sampai
// kedaluwarsa menjadi jalan buntu di depan mesin kasir yang sedang dipakai
// melayani orang.
//
// # BATAS YANG DISENGAJA
//
// Server MEMPERTAHANKAN sisa waktu tantangan saat kode diminta ulang, tidak
// memperpanjangnya (anti-penyalahgunaan, disengaja & berkomentar di
// staff_session_service.go). Jadi tombol ini menolong kasus "kodenya tak
// sampai", BUKAN "waktunya sudah habis" — untuk yang kedua server menjawab
// "ulangi dari awal", dan pesan itu harus sampai apa adanya ke layar.

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

/// Menghitung berapa kali kode diminta, dan boleh disuruh gagal.
class _AuthPalsu extends AuthNotifier {
  int permintaanKode = 0;
  String? galat;
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
  }) async =>
      resumeStaffSession(deviceToken: 'x');

  @override
  Future<String?> verifyStaffSession({
    required String challengeId,
    required String staffUserId,
    required String code,
  }) async {
    kodeDiverifikasi.add(code);
    return galat;
  }

  @override
  Future<String> requestStaffSessionOtp({
    required String challengeId,
    required String staffUserId,
  }) async {
    permintaanKode++;
    if (galat != null) throw galat!;
    return 'pem***@uji.invalid';
  }
}

Future<_AuthPalsu> _buka(
  WidgetTester tester, {
  String? galat,
  bool stafPunyaPin = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final auth = _AuthPalsu()
    ..galat = galat
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
        home: Scaffold(body: StaffSessionFlow(onSelesai: () {})),
      ),
    ),
  );
  await tester.pump(); // useEffect pemulihan perangkat
  await tester.pump();
  return auth;
}

void main() {
  testWidgets('sampai di layar persetujuan lewat perangkat tersimpan',
      (tester) async {
    final auth = await _buka(tester);
    await tester.tap(find.text('putra'));
    await tester.pump();

    // Positifnya lebih dulu: kalau layarnya tak pernah tercapai, semua
    // pernyataan soal tombolnya kehilangan arti.
    expect(find.textContaining('Setujui sesi putra'), findsOneWidget);
    expect(auth.permintaanKode, 1); // kode pertama dikirim otomatis
  });

  testWidgets('tombol kirim ulang ADA dan meminta kode baru', (tester) async {
    final auth = await _buka(tester);
    await tester.tap(find.text('putra'));
    await tester.pump();

    await tester.tap(find.text('Kirim ulang kode'));
    await tester.pump();

    expect(auth.permintaanKode, 2);
    expect(find.textContaining('Kode baru dikirim'), findsOneWidget);
  });

  testWidgets('sesudah dipakai, tombolnya berjeda dengan hitungan terbaca',
      (tester) async {
    final auth = await _buka(tester);
    await tester.tap(find.text('putra'));
    await tester.pump();
    await tester.tap(find.text('Kirim ulang kode'));
    await tester.pump();

    // Hitungannya ditulis di label. Tombol yang mati tanpa alasan terbaca
    // sebagai aplikasi yang macet, dan orang akan menekannya berkali-kali.
    expect(find.textContaining('Kirim ulang kode dalam'), findsOneWidget);

    // Ketukan kedua selama jeda tidak mengirim apa pun.
    await tester.tap(find.textContaining('Kirim ulang kode dalam'));
    await tester.pump();
    expect(auth.permintaanKode, 2);

    // Setelah jedanya habis, tombolnya hidup lagi.
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Kirim ulang kode'), findsOneWidget);

    await tester.tap(find.text('Kirim ulang kode'));
    await tester.pump();
    expect(auth.permintaanKode, 3);
  });

  testWidgets('penolakan server sampai apa adanya, tanpa disamarkan',
      (tester) async {
    // Tantangan yang sudah kedaluwarsa TIDAK bisa diselamatkan tombol ini —
    // server mempertahankan sisa waktu, tidak memperpanjangnya. Yang penting
    // alasannya terbaca, bukan berubah jadi "Terjadi kesalahan sistem".
    await _buka(tester, galat: 'sesi otorisasi sudah kedaluwarsa, ulangi dari awal');
    await tester.pump();

    // Kode pertama pun gagal, dan alur tetap mengantar ke layar verifikasi
    // supaya PIN masih bisa dipakai.
    await tester.tap(find.text('putra'));
    await tester.pump();

    expect(
      find.textContaining('sesi otorisasi sudah kedaluwarsa'),
      findsOneWidget,
    );
  });

  testWidgets('kode lama dibersihkan saat yang baru dikirim', (tester) async {
    await _buka(tester);
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

  testWidgets('staf BER-PIN diarahkan memakai PIN-nya sendiri', (tester) async {
    // Sebelum ini layar selalu menyuruh memakai "PIN otorisasi Anda" — yang
    // dimaksud PIN PEMILIK, bukan PIN staf. Staf yang sudah diberi PIN dari
    // dashboard tak punya cara tahu bahwa PIN itulah yang diminta.
    await _buka(tester, stafPunyaPin: true);
    await tester.tap(find.text('putra'));
    await tester.pump();

    expect(find.textContaining('Masukkan PIN putra'), findsOneWidget);
    // Kode email tetap disebut sebagai jalan cadangan — bukan dihilangkan.
    expect(find.textContaining('Belum punya PIN atau lupa'), findsOneWidget);
  });

  testWidgets('staf TANPA PIN tetap diarahkan ke kode email', (tester) async {
    // Sisi sebaliknya. Perbaikan yang menyuruh semua orang mengetik "PIN Anda"
    // akan menyesatkan staf yang memang belum diberi PIN — mereka akan mencoba
    // menebak PIN yang tak pernah ada.
    await _buka(tester, stafPunyaPin: false);
    await tester.tap(find.text('putra'));
    await tester.pump();

    expect(find.textContaining('Kode 6 digit dikirim ke'), findsOneWidget);
    expect(find.textContaining('Masukkan PIN putra'), findsNothing);
  });

  // ── Pemilik hadir: pilih staf, langsung masuk ────────────────────────────
  //
  // Perangkat TANPA device_token berarti Pemilik baru saja mengetik email +
  // passwordnya di sini. Ia ada di depan mesin dan sudah membuktikan dirinya;
  // meminta kode ke emailnya sendiri sesudah itu berarti menyuruh orang yang
  // sama membuktikan hal yang sama dua kali.

  Future<_AuthPalsu> bukaTanpaPerangkat(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final auth = _AuthPalsu();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // Tanpa token: perangkat ini belum pernah disahkan.
          staffDeviceStorageProvider.overrideWithValue(_StoragePalsu()),
          authProvider.overrideWith(() => auth),
        ],
        child: MaterialApp(
          home: Scaffold(body: StaffSessionFlow(onSelesai: () {})),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return auth;
  }

  testWidgets('Pemilik hadir → pilih staf langsung masuk, TANPA kode',
      (tester) async {
    final auth = await bukaTanpaPerangkat(tester);

    // Pemilik mengetik kredensialnya.
    final isian = find.byType(TextField);
    await tester.enterText(isian.at(0), 'owner@uji.invalid');
    await tester.enterText(isian.at(1), 'rahasia');
    await tester.tap(find.text('Lanjut'));
    await tester.pump();

    await tester.tap(find.text('putra'));
    await tester.pump();

    // Kode TIDAK diminta — tak ada email yang dikirim.
    expect(auth.permintaanKode, 0);
    // Dan verifikasinya dipanggil dengan kode KOSONG: itulah penanda
    // "tanpa bukti kedua" yang dibaca server.
    expect(auth.kodeDiverifikasi, ['']);
  });

  testWidgets('perangkat yang diingat TETAP meminta bukti', (tester) async {
    // Sisi sebaliknya, dan ini yang menjaga PIN tetap berarti. Di perangkat
    // yang cuma mengingat pengesahan lama, Pemilik TIDAK hadir — membiarkan
    // siapa pun memilih nama lalu masuk akan membuat PIN jadi hiasan.
    final auth = await _buka(tester);
    await tester.tap(find.text('putra'));
    await tester.pump();

    expect(auth.permintaanKode, 1);
    expect(auth.kodeDiverifikasi, isEmpty);
    expect(find.textContaining('Setujui sesi putra'), findsOneWidget);
  });
}
