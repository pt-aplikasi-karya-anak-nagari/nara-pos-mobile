import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/user/domain/assignable_role.dart';

// Peran yang boleh diberikan ke karyawan, sebagaimana dijawab
// GET /outlets/:outletId/employee-roles.
//
// Dua hal yang dijaga di sini, dan keduanya gagal tanpa suara:
//
//   1. `name` harus terbawa APA ADANYA. Inilah yang dikirim balik saat
//      menyimpan, dan server mencocokkannya persis (GetRoleByName memakai
//      `WHERE name = $1`). Menurunkannya jadi huruf kecil — persis yang
//      dilakukan kode lama lewat UserRole.cashier.name — membuat setiap
//      penyimpanan ditolak "role target tidak ditemukan".
//
//   2. Sebutan yang ditampilkan diambil dari deskripsi SERVER, yang memang
//      sudah memuatnya di depan em-dash. Dengan begitu peran yang ditambahkan
//      server kelak langsung punya sebutan benar tanpa aplikasi dirilis ulang.

void main() {
  group('nilai yang dikirim balik ke server', () {
    test('name terbawa apa adanya, kapital dan semuanya', () {
      final r = AssignableRole.fromJson({
        'name': 'Cashier',
        'description': 'Kasir — proses transaksi.',
      });

      expect(r.name, 'Cashier');
      expect(r.name, isNot('cashier')); // yang dulu dikirim, dan selalu ditolak
    });
  });

  group('sebutan tampilan', () {
    test('diambil dari deskripsi server, di depan em-dash', () {
      expect(
        AssignableRole.fromJson({
          'name': 'Waiter',
          'description': 'Pramusaji — ambil pesanan di meja.',
        }).label,
        'Pramusaji',
      );
      expect(
        AssignableRole.fromJson({
          'name': 'Inventory',
          'description': 'Tim gudang — kelola stok, supplier.',
        }).label,
        'Tim gudang',
      );
    });

    test('peran yang belum dikenal ditampilkan APA ADANYA', () {
      // Bukan disembunyikan, dan bukan diganti "Kasir" — perilaku lama, yang
      // membuat enam peran berbeda tampil dengan sebutan yang sama. Peran baru
      // dari server harus terlihat supaya kekurangannya bisa diperbaiki.
      expect(labelPeran('PeranBaruDariServer'), 'PeranBaruDariServer');
    });

    test('tanpa deskripsi, peta cadangan yang dipakai', () {
      // Kartu daftar karyawan hanya menyimpan nama peran, tak ada deskripsi.
      expect(labelPeran('Cashier'), 'Kasir');
      expect(labelPeran('Kitchen'), 'Dapur');
      expect(labelPeran('Waiter'), 'Pramusaji');
    });

    test('deskripsi MENGALAHKAN peta cadangan', () {
      // Urutannya penting: server yang berwenang atas sebutannya. Kalau suatu
      // saat server mengubah sebutan sebuah peran, aplikasi harus ikut tanpa
      // dirilis ulang.
      expect(
        labelPeran('Cashier', description: 'Kassa — sebutan baru dari server.'),
        'Kassa',
      );
    });

    test('deskripsi tanpa em-dash tidak merusak apa pun', () {
      expect(labelPeran('Cashier', description: 'tanpa pemisah'), 'Kasir');
      expect(labelPeran('Cashier', description: ''), 'Kasir');
    });
  });

  group('penjelasan di bawah nama', () {
    test('bagian sesudah em-dash, tanpa mengulang sebutannya', () {
      expect(
        AssignableRole.fromJson({
          'name': 'Barista',
          'description': 'Barista — operator dapur minuman.',
        }).penjelasan,
        'operator dapur minuman.',
      );
    });

    test('deskripsi tanpa em-dash dipakai utuh', () {
      expect(
        const AssignableRole(name: 'X', description: 'apa adanya').penjelasan,
        'apa adanya',
      );
    });
  });

  group('jawaban server yang cacat', () {
    test('field yang hilang tidak melempar', () {
      final r = AssignableRole.fromJson({});
      expect(r.name, '');
      expect(r.description, '');
      expect(r.label, '');
    });
  });
}
