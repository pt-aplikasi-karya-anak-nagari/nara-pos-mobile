import 'package:flutter/material.dart';

/// Wadah untuk keempat branch navigasi utama, dengan perpindahan yang
/// beranimasi.
///
/// # KENAPA BUKAN indexedStack BAWAAN
///
/// `StatefulShellRoute.indexedStack` menukar branch dalam SATU frame: layar
/// Kasir hilang, layar Riwayat muncul, tanpa apa pun di antaranya. Perpindahan
/// yang mendadak begitu membuat mata kehilangan jejak — di layar POS yang
/// isinya padat angka, kasir harus memindai ulang dari nol untuk memastikan ia
/// ada di halaman yang benar.
///
/// # KENAPA BUKAN AnimatedSwitcher
///
/// AnimatedSwitcher membuang widget lama dan membangun yang baru. Untuk shell
/// ini itu berarti keranjang yang sedang diisi, posisi gulir daftar produk, dan
/// isian form di tab lain semuanya hilang tiap kali kasir berpindah tab —
/// justru kebalikan dari yang dijanjikan StatefulShellRoute.
///
/// Di sini SELURUH branch tetap hidup dan tetap terpasang; yang beranimasi
/// hanya opasitas dan pergeseran kecilnya. Yang tak aktif dibungkus
/// IgnorePointer supaya tak menangkap sentuhan, dan TickerMode(false) supaya
/// animasi di dalamnya berhenti — tanpa itu, tiga halaman tersembunyi tetap
/// membakar frame di belakang layar.
class WadahBranchBeranimasi extends StatelessWidget {
  final int aktif;
  final List<Widget> anak;

  /// Cukup untuk terbaca mata, cukup pendek untuk tak terasa menghambat. Kasir
  /// berpindah tab puluhan kali sehari; setengah detik akan terasa lamban pada
  /// pemakaian kelima.
  static const Duration durasi = Duration(milliseconds: 220);

  const WadahBranchBeranimasi({
    super.key,
    required this.aktif,
    required this.anak,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [for (var i = 0; i < anak.length; i++) _bungkus(i, anak[i])],
    );
  }

  Widget _bungkus(int i, Widget child) {
    final ini = i == aktif;
    return AnimatedOpacity(
      opacity: ini ? 1 : 0,
      duration: durasi,
      // easeOut untuk yang datang, dan sama untuk yang pergi: kurva yang
      // berbeda antara masuk dan keluar membuat keduanya bersilangan di titik
      // yang salah, dan sekilas kedua halaman terlihat menumpuk.
      curve: Curves.easeOut,
      child: IgnorePointer(
        ignoring: !ini,
        child: TickerMode(
          enabled: ini,
          child: AnimatedSlide(
            // Geseran kecil ke atas untuk yang aktif; yang tak aktif menunggu
            // 8 dp di bawah. Cukup untuk memberi arah tanpa jadi pertunjukan.
            offset: ini ? Offset.zero : const Offset(0, 0.012),
            duration: durasi,
            curve: Curves.easeOut,
            child: child,
          ),
        ),
      ),
    );
  }
}
