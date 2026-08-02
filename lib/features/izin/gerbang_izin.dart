import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/permission_service.dart';

/// Keadaan gerbang izin, dalam bentuk yang bisa dibaca router secara SINKRON.
///
/// # KENAPA null PUNYA ARTI SENDIRI
///
/// redirect milik GoRouter harus menjawab seketika — ia tak bisa menunggu
/// Future. Sementara memeriksa izin selalu asinkron.
///
/// Kalau keadaan awal dibuat `false`, aplikasi berkedip ke halaman izin tiap
/// kali dibuka, lalu melompat pergi begitu pemeriksaan selesai — padahal
/// izinnya sudah lengkap sejak awal. Kalau dibuat `true`, gerbangnya bocor:
/// satu frame pertama meloloskan pengguna ke halaman utama.
///
/// Karena itu ada tiga keadaan, bukan dua:
///
///   null   belum diperiksa → tahan di halaman izin, tampilkan keadaan memuat
///   false  ada yang belum diberikan → tahan di halaman izin
///   true   lengkap → lanjut ke login / halaman utama
class GerbangIzin extends Notifier<bool?> {
  @override
  bool? build() {
    periksa();
    return null;
  }

  /// Periksa ulang seluruh izin. Dipanggil saat aplikasi mulai, setiap kali
  /// pengguna kembali dari halaman Pengaturan, dan sesudah tiap permintaan.
  Future<void> periksa() async {
    try {
      state = await ref.read(systemPermissionServiceProvider).semuaDiberikan;
    } catch (_) {
      // Kegagalan membaca izin BUKAN alasan mengunci kasir dari alat kerjanya.
      //
      // Yang dijaga gerbang ini adalah pengguna yang menolak izin, bukan
      // perangkat yang plugin-nya bermasalah. Menahan di halaman izin saat
      // pemeriksaannya sendiri yang rusak menghasilkan layar yang tak bisa
      // dilewati dengan cara apa pun — termasuk dengan memberikan izinnya.
      state = true;
    }
  }
}

final gerbangIzinProvider = NotifierProvider<GerbangIzin, bool?>(
  GerbangIzin.new,
);
