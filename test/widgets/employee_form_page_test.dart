import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nara_pos_mobile/core/outlet_scope.dart';
import 'package:nara_pos_mobile/core/shared_prefs.dart';
import 'package:nara_pos_mobile/features/outlet/data/outlet_service.dart';
import 'package:nara_pos_mobile/features/user/data/auth_service.dart';
import 'package:nara_pos_mobile/features/user/domain/user.dart';
import 'package:nara_pos_mobile/features/user/domain/user_role.dart';
import 'package:nara_pos_mobile/features/user/ui/employee_form_page.dart';

// REGRESI commit 8ee0ce7 — form karyawan tak boleh meminta username & password.
//
// Karyawan tak punya keduanya sejak dipisah ke tabel `employees` (Fase 5):
// mereka masuk lewat sesi kasir atas persetujuan Pemilik, bukan dengan
// kredensial sendiri. Server MEMBUANG kedua field itu diam-diam — jadi form
// yang lama memaksa penggunanya mengarang username dan password yang tak
// pernah tersimpan dan tak pernah bisa dipakai. Tak ada error yang muncul,
// jadi tak ada yang menyadarinya.
//
// # YANG SENGAJA TIDAK DIUJI DI SINI
//
// Isi payload yang dikirim ke server — khususnya nilai 'role'-nya — TIDAK
// dipaku di berkas ini, walau secara teknis bisa. Penyelidikan saat menulis
// tes ini menemukan jalur simpannya memang sedang rusak: form menembak
// POST /outlets/{id}/employees (handler AddEmployee, yang menuntut `user_id`)
// alih-alih /employees/create, dan mengirim 'role' berisi 'cashier' huruf
// kecil sementara tabel roles di server hanya berisi 'Cashier'.
//
// Memaku nilai-nilai itu sekarang berarti membekukan cacatnya jadi kontrak.
// Yang dikunci di sini hanya yang memang sudah benar.

class _FakeAuth extends AuthNotifier {
  final AuthState awal;
  _FakeAuth(this.awal);
  @override
  AuthState build() => awal;
}

Future<void> _buka(WidgetTester tester, {AuthState? sesi}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // ref.t (i18n) membaca localeProvider yang membaca prefs.
        sharedPreferencesProvider.overrideWithValue(prefs),
        // AuthNotifier.build() aslinya membaca authStorageProvider
        // (FlutterSecureStorage). Menimpa build() PENUH — tanpa super.build() —
        // membuat storage itu tak pernah tersentuh.
        authProvider.overrideWith(() => _FakeAuth(sesi ?? const AuthState())),
        selectedOutletIdProvider.overrideWith((ref) => 'o1'),
        // Aslinya memanggil outletService.getEmployees lewat dio → butuh token.
        outletEmployeesProvider.overrideWith((ref, id) async => <User>[]),
      ],
      child: const MaterialApp(home: EmployeeFormPage()),
    ),
  );
  // pump() saja, bukan pumpAndSettle: halaman punya provider async yang tak
  // pernah "settle" di lingkungan tes.
  await tester.pump();
}

void main() {
  testWidgets('hanya SATU kolom isian — nama', (tester) async {
    await _buka(tester);

    // Bug aslinya menambahkan dua TextField lagi (username & password).
    // Menghitungnya lebih tahan lama daripada mencari label tertentu, yang
    // bisa berubah kata tanpa mengubah maksudnya.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('tak ada LABEL username maupun password', (tester) async {
    await _buka(tester);

    // Pencocokan persis, bukan textContaining: kalimat penjelas di halaman ini
    // memang menyebut kata "username" dan "password" — itu justru maksudnya.
    // Yang tak boleh ada adalah label kolom isian.
    for (final label in [
      'Username',
      'Password',
      'Kata Sandi',
      'Kata sandi',
      'Nama Pengguna',
    ]) {
      expect(find.text(label), findsNothing, reason: 'masih ada label "$label"');
    }
  });

  testWidgets('menjelaskan KENAPA kredensialnya tak diminta', (tester) async {
    await _buka(tester);

    // Menghapus kolomnya saja tak cukup. Pemilik yang terbiasa mengisi
    // username akan mengira formnya rusak atau belum selesai dimuat.
    expect(
      find.textContaining('tidak punya username maupun password'),
      findsOneWidget,
    );
  });

  testWidgets('peran yang ditawarkan tidak memuat Owner maupun Admin', (tester) async {
    await _buka(tester);

    // Owner lahir dari registrasi mandiri (1 email = 1 owner) dan server
    // menolaknya terang-terangan lewat validateRoleAssignment. Menawarkannya
    // di sini berarti mengundang klik yang pasti gagal.
    expect(find.text(UserRole.owner.label), findsNothing); // "Owner"
    expect(find.text(UserRole.admin.label), findsNothing); // "Admin"

    // Sisi positifnya diperiksa juga — kalau daftar perannya ternyata kosong
    // sama sekali, kedua pernyataan di atas benar tanpa arti.
    expect(find.text(UserRole.cashier.label), findsOneWidget); // "Kasir"
    expect(find.text(UserRole.adminOutlet.label), findsOneWidget);
  });

  testWidgets('halaman terbuka tanpa sesi login tanpa melempar', (tester) async {
    // Halaman ini bisa tercapai saat token baru saja kedaluwarsa. Melempar di
    // sini akan memadamkan layar, bukan sekadar menampilkan form kosong.
    await _buka(tester);
    expect(tester.takeException(), isNull);
  });
}
