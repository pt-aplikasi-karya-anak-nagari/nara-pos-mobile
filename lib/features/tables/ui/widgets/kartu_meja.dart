import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

// Grid & kartu meja yang menyesuaikan lebar panel dan ukuran huruf.
//
// Grid lama memakai 4 kolom tetap dengan kotak persegi (childAspectRatio 1).
// Di panel sempit — tablet dalam tampilan terbelah — tiap kotak jadi lebih
// pendek dari isinya (ikon, nama, kursi, badge status) dan Flutter menggambar
// garis "BOTTOM OVERFLOWED". Kini jumlah kolom mengikuti lebar, dan tinggi
// kotak dihitung dari isinya serta ikut membesar dengan ukuran huruf sistem.

/// Skala huruf sistem (1.0 = normal), dibatasi supaya kotak tak membengkak.
double skalaHurufMeja(BuildContext context) =>
    (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.0);

/// Tinggi kartu meja: bagian tetap (padding, ikon, jarak, badge) + teks yang
/// ikut skala huruf.
double tinggiKartuMeja(double skala) => 128 + 56 * (skala - 1);

/// Grid kartu meja (halaman manajemen meja per area).
SliverGridDelegate gridKartuMeja(BuildContext context) =>
    SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 168,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      mainAxisExtent: tinggiKartuMeja(skalaHurufMeja(context)),
    );

/// Grid baris meja (tab area): kotak lebar berisi nama, kursi, & aksi.
SliverGridDelegate gridBarisMeja(BuildContext context) =>
    SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 260,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      mainAxisExtent: 62 + 26 * (skalaHurufMeja(context) - 1),
    );

class KartuMeja extends StatelessWidget {
  const KartuMeja({
    super.key,
    required this.nama,
    required this.kapasitas,
    required this.terisi,
    required this.labelStatus,
    this.durasi,
    this.onTap,
  });

  final String nama;
  final int kapasitas;
  final bool terisi;
  final String labelStatus;

  /// Label lama terisi (mis. "1j 20m"), hanya untuk meja terisi.
  final Widget? durasi;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final warna = terisi ? kDanger : kSuccess;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: warna.withValues(alpha: 0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: warna.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.table_restaurant, color: warna, size: 26),
                const SizedBox(height: 4),
                Text(
                  nama,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  '$kapasitas Kursi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: kTextMid),
                ),
                const SizedBox(height: 6),
                // Badge mengecil sendiri bila kotak sempit (mis. "TERISI"
                // + durasi), alih-alih meluap ke samping.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: warna.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          labelStatus,
                          style: TextStyle(
                            color: warna,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (terisi && durasi != null) ...[
                          const SizedBox(width: 6),
                          durasi!,
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
