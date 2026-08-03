import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Tab dengan lencana jumlah di sebelah labelnya.
///
/// # KENAPA LENCANA INI ADA
///
/// Kasir hanya melihat SATU tab pada satu waktu. Pesanan meja yang masuk saat
/// ia sedang menyusun keranjang tidak terlihat sama sekali sampai ia menyentuh
/// tab sebelah — dan pelanggan di meja itu menunggu tanpa ada yang tahu.
/// Sebaliknya juga: kasir yang sedang menangani pesanan meja lupa bahwa masih
/// ada keranjang setengah jadi di tab satunya.
class TabBerlencana extends StatelessWidget {
  const TabBerlencana({super.key, required this.label, required this.jumlah});

  final String label;

  /// Jumlah yang ditampilkan. null = belum diketahui (mis. masih memuat dari
  /// jaringan); lencananya disembunyikan.
  ///
  /// null DIBEDAKAN dari 0 dengan sengaja: menampilkan "0" saat datanya belum
  /// tiba adalah kebohongan kecil yang membuat kasir menyimpulkan tak ada
  /// pesanan masuk, lalu berhenti memeriksa.
  final int? jumlah;

  @override
  Widget build(BuildContext context) {
    final n = jumlah ?? 0;
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Flexible + ellipsis: label tab ini panjang ("Pesanan dari Scan
          // Meja") dan ruangnya sempit. Tanpa ini, lencananya mendorong teks
          // sampai meluber jadi garis kuning-hitam di layar yang lebih kecil.
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (jumlah != null && n > 0) ...[
            const SizedBox(width: 6),
            _Lencana(jumlah: n),
          ],
        ],
      ),
    );
  }
}

class _Lencana extends StatelessWidget {
  const _Lencana({required this.jumlah});

  final int jumlah;

  @override
  Widget build(BuildContext context) {
    // 99+ supaya lencananya tak pernah melebar tak terkendali dan mendorong
    // label tabnya keluar. Di atas itu angka pastinya sudah tak berarti —
    // yang perlu diketahui kasir adalah "banyak sekali".
    final teks = jumlah > 99 ? '99+' : '$jumlah';
    return Container(
      key: ValueKey('tab-badge-$teks'),
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: kPrimary,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        teks,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1.4,
        ),
      ),
    );
  }
}
