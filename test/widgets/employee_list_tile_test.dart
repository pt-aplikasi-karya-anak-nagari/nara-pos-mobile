import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/user/domain/user.dart';
import 'package:nara_pos_mobile/features/user/domain/user_role.dart';
import 'package:nara_pos_mobile/features/user/ui/widgets/employee_list_tile.dart';

// REGRESI commit 3fbeb7e — "@" yang menggantung di daftar karyawan.
//
// Sejak staf dipisah ke tabel `employees` (Fase 5) karyawan tak punya username
// lagi, dan server mengirimnya sebagai string KOSONG. Baris kedua tiap kartu
// jadi terbaca:
//
//     putra
//     @ • Cabang Utama
//
// Sebuah "at" tanpa apa pun sesudahnya. Tak ada yang error: "" adalah String
// yang sah, interpolasi '@${...}' adalah kode yang sah, dan dart analyze diam
// sepenuhnya. Hanya layar yang menunjukkannya.
//
// Ini tes widget PERTAMA di repo ini — tes lain seluruhnya unit. Sengaja
// dimulai dari widget yang tak butuh provider maupun plugin, supaya polanya
// bisa diikuti tanpa memasang perancah apa pun.

User _karyawan({required String username, String nama = 'putra'}) => User(
  name: nama,
  username: username,
  passwordHash: '',
  roleIndex: UserRole.cashier.index,
);

Widget _bungkus(Widget anak) =>
    MaterialApp(home: Scaffold(body: ListView(children: [anak])));

void main() {
  testWidgets('username kosong → hanya nama outlet, tanpa "@"', (tester) async {
    await tester.pumpWidget(
      _bungkus(
        EmployeeListTile(
          employee: _karyawan(username: ''),
          outletName: 'Cabang Utama',
        ),
      ),
    );

    expect(find.text('Cabang Utama'), findsOneWidget);

    // Inti regresinya. Bukan sekadar "tak ada teks @ sendirian" — pemisah "•"
    // juga tak boleh ikut muncul, karena tak ada dua hal untuk dipisahkan.
    expect(find.textContaining('@'), findsNothing);
    expect(find.textContaining('•'), findsNothing);
  });

  testWidgets('username ada → "@nama • outlet" tetap utuh', (tester) async {
    // Sisi sebaliknya. Perbaikan yang menyembunyikan SEMUA username sama
    // merusaknya dengan bug aslinya — owner masih punya username, dan bagi
    // mereka baris itu memang informasi.
    await tester.pumpWidget(
      _bungkus(
        EmployeeListTile(
          employee: _karyawan(username: 'budi', nama: 'Budi'),
          outletName: 'Cabang Utama',
        ),
      ),
    );

    expect(find.text('@budi • Cabang Utama'), findsOneWidget);
  });

  testWidgets('nama tetap tampil apa pun keadaan username-nya', (tester) async {
    await tester.pumpWidget(
      _bungkus(
        EmployeeListTile(
          employee: _karyawan(username: ''),
          outletName: 'Cabang Utama',
        ),
      ),
    );

    // Penjaga terhadap tes di atas yang lulus karena alasan salah: kalau
    // kartunya ternyata gagal dirender sama sekali, "tak ada @" juga benar.
    expect(find.text('putra'), findsOneWidget);
  });

  testWidgets('nama kosong tidak membuat inisial melempar', (tester) async {
    // employee.name[0] pada string kosong adalah RangeError. Kodenya sudah
    // berjaga (name.isEmpty ? '?' : ...), dan penjaga itu dikunci di sini —
    // daftar karyawan yang menabrak satu baris cacat tak boleh memadamkan
    // seluruh layar kasir.
    await tester.pumpWidget(
      _bungkus(
        EmployeeListTile(
          employee: _karyawan(username: '', nama: ''),
          outletName: 'Cabang Utama',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('?'), findsOneWidget);
  });
}
