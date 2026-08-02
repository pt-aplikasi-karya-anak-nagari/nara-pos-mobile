import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Satu perhitungan yang sudah selesai.
class BarisRiwayat {
  const BarisRiwayat({required this.ekspresi, required this.hasil});

  /// Ekspresi lengkapnya, mis. "50000 − 5000".
  final String ekspresi;

  /// Hasil yang sudah diformat, mis. "45000".
  final String hasil;
}

/// Riwayat perhitungan kalkulator kasir.
///
/// # KENAPA DI PROVIDER, BUKAN DI DALAM DIALOG
///
/// Kalau state-nya hidup di widget dialog, riwayatnya lenyap tiap kali dialog
/// ditutup. Padahal justru itu pemakaiannya: kasir menghitung diskon, menutup
/// kalkulator untuk mengetik nominalnya ke keranjang, lalu membuka lagi untuk
/// hitungan berikutnya — dan sering perlu melihat lagi angka yang tadi.
/// Menyimpannya di sini membuat riwayat bertahan sepanjang sesi aplikasi.
///
/// # KENAPA TIDAK DISIMPAN KE DISK
///
/// Ini catatan coret-coretan, bukan dokumen keuangan. Menyimpannya ke disk
/// membuat angka-angka yang sudah tak berarti bertahan berhari-hari, dan
/// membuat kasir mengira daftar ini catatan resmi transaksi — padahal tak ada
/// hubungannya dengan penjualan mana pun.
class RiwayatKalkulator extends Notifier<List<BarisRiwayat>> {
  /// Batas atas. Kasir sibuk bisa menghitung ratusan kali sehari, dan daftar
  /// yang tumbuh tanpa batas hanya menghabiskan memori untuk baris yang tak
  /// akan pernah digulir orang.
  static const batas = 50;

  @override
  List<BarisRiwayat> build() => const [];

  void tambah(String ekspresi, String hasil) {
    // Terbaru di ATAS: yang baru saja dihitung adalah yang paling mungkin
    // dilihat lagi.
    final baru = [BarisRiwayat(ekspresi: ekspresi, hasil: hasil), ...state];
    state = baru.length > batas ? baru.sublist(0, batas) : baru;
  }

  void bersihkan() => state = const [];
}

final riwayatKalkulatorProvider =
    NotifierProvider<RiwayatKalkulator, List<BarisRiwayat>>(
      RiwayatKalkulator.new,
    );
