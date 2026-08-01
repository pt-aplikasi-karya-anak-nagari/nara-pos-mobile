import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nara_pos_mobile/core/outlet_scope.dart';
import 'package:nara_pos_mobile/core/shared_prefs.dart';
import 'package:nara_pos_mobile/features/outlet/data/outlet_service.dart';
import 'package:nara_pos_mobile/features/user/data/auth_service.dart';
import 'package:nara_pos_mobile/features/user/domain/assignable_role.dart';
import 'package:nara_pos_mobile/features/user/domain/user.dart';
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
// # DAFTAR PERAN DARI SERVER
//
// Versi pertama berkas ini sengaja tidak memaku isi payload, karena jalur
// simpannya memang sedang rusak: form menembak POST /outlets/{id}/employees
// (handler AddEmployee, yang menuntut `user_id`) alih-alih /employees/create,
// dan mengirim 'role' berisi "cashier" huruf kecil sementara tabel roles di
// server hanya berisi "Cashier". Memaku nilai yang salah berarti membekukan
// cacatnya jadi kontrak.
//
// Keduanya sudah diperbaiki, jadi sekarang justru sebaliknya: yang dikunci
// adalah daftar perannya datang dari server, dan chip-nya menampilkan sebutan
// dari deskripsi server — bukan dari enum UserRole lokal yang cuma punya empat
// nilai untuk sepuluh peran.

class _FakeAuth extends AuthNotifier {
  final AuthState awal;
  _FakeAuth(this.awal);
  @override
  AuthState build() => awal;
}

/// Peran seperti yang benar-benar dijawab server: nama BERKAPITAL, dengan
/// deskripsi yang memuat sebutan Indonesia di depan em-dash.
const _peranServer = [
  AssignableRole(
    name: 'Cashier',
    description: 'Kasir — proses transaksi, buka/tutup shift.',
  ),
  AssignableRole(
    name: 'Barista',
    description: 'Barista — operator dapur minuman & display order minuman.',
  ),
  AssignableRole(name: 'Waiter', description: 'Pramusaji — ambil pesanan.'),
];

Future<void> _buka(
  WidgetTester tester, {
  AuthState? sesi,
  List<AssignableRole>? peran,
}) async {
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
        assignableRolesProvider.overrideWith(
          (ref, id) async => peran ?? _peranServer,
        ),
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

  testWidgets('pilihan peran dibangun dari daftar server', (tester) async {
    await _buka(tester);

    // Ketiganya berasal dari _peranServer, bukan dari UserRole. Barista dan
    // Pramusaji khususnya: keduanya TIDAK ADA di enum lokal, jadi keduanya tak
    // akan pernah muncul kalau daftarnya masih dibangun dari sana.
    expect(find.text('Kasir'), findsOneWidget);
    expect(find.text('Barista'), findsOneWidget);
    expect(find.text('Pramusaji'), findsOneWidget);
  });

  testWidgets('"Admin Outlet" tak lagi ditawarkan — server tak punya peran itu',
      (tester) async {
    await _buka(tester);

    // Chip lama yang tak punya padanan apa pun di sepuluh peran server.
    // Menawarkannya berarti mengundang simpan yang pasti ditolak.
    expect(find.text('Admin Outlet'), findsNothing);
  });

  testWidgets('daftar peran gagal dimuat → dikatakan, bukan ditebak',
      (tester) async {
    await _buka(tester, peran: const []);

    // Tanpa daftar cadangan lokal. Menawarkan tebakan berarti mengundang
    // penyimpanan yang ditolak server dengan pesan yang tak berarti apa pun
    // bagi penggunanya — persis kegagalan senyap yang sedang diperbaiki.
    expect(find.textContaining('Daftar peran belum bisa dimuat'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('outlet dinyatakan, bukan dipilih', (tester) async {
    await _buka(tester);

    // Server mengambil outlet dari path URL; dto.CreateEmployeeRequest tak
    // punya field outlet sama sekali. Pemilih outlet di sini dulu tak
    // berpengaruh apa pun — dan itu lebih buruk daripada tidak ada, karena
    // membuat orang mengira karyawannya ditempatkan di cabang lain.
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('halaman terbuka tanpa sesi login tanpa melempar', (tester) async {
    // Halaman ini bisa tercapai saat token baru saja kedaluwarsa. Melempar di
    // sini akan memadamkan layar, bukan sekadar menampilkan form kosong.
    await _buka(tester);
    expect(tester.takeException(), isNull);
  });
}
