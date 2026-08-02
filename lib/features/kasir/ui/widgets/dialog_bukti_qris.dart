import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/format.dart';

/// Keputusan kasir atas bukti pembayaran QRIS dari pesanan menu QR.
enum AksiBukti { terima, tolak }

/// Dialog verifikasi bukti pembayaran QRIS — pesanan yang pelanggannya sudah
/// membayar di muka dan melampirkan bukti.
///
/// # KENAPA BUKTINYA ADA DI DALAM DIALOG, BUKAN DI TOMBOL "LIHAT" TERPISAH
///
/// Sebelumnya kasir mengonfirmasi lewat dialog yang hanya menulis metode dan
/// total — buktinya sendiri di tombol "Lihat" yang terpisah, yang tak wajib
/// ditekan. Konfirmasi buta seperti itu meniadakan gunanya bukti: pelanggan
/// mana pun bisa meng-upload gambar apa pun, dan kasir yang sedang sibuk akan
/// menekan "Terima" tanpa pernah melihatnya. Bukti dan keputusannya harus ada
/// dalam satu layar.
///
/// # KENAPA TIDAK ADA PILIHAN METODE DI SINI
///
/// Pembayaran sudah TERJADI — lewat QRIS, di ponsel pelanggan, sebelum dialog
/// ini terbuka. Yang tersisa untuk kasir hanyalah memutuskan: buktinya sah
/// (terima → transaksi lunas dengan metode yang dipilih pelanggan) atau tidak
/// (tolak → backend menghapus bukti, pelanggan diminta upload ulang di
/// halaman menu). Menampilkan pemilih metode di sini mengundang kasir
/// menimpa metode yang benar dan membuang tautan buktinya.
class DialogBuktiQris extends StatelessWidget {
  final String urlBukti;
  final String metode;
  final double total;

  const DialogBuktiQris({
    super.key,
    required this.urlBukti,
    required this.metode,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: kCard,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Verifikasi Pembayaran',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: kTextDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Pelanggan sudah membayar lewat $metode. Periksa buktinya, '
                'lalu konfirmasi.',
                style: TextStyle(fontSize: 12, color: kTextMid, height: 1.4),
              ),
              const SizedBox(height: 14),
              // Bukti — bagian terpenting dialog ini. InteractiveViewer supaya
              // nominal & nama merchant di tangkapan layar bisa di-zoom tanpa
              // membuka layar lain.
              if (urlBukti.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: InteractiveViewer(
                      maxScale: 5,
                      child: Image.network(
                        urlBukti,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Container(
                          height: 120,
                          alignment: Alignment.center,
                          color: kBg,
                          child: Text(
                            'Gagal memuat gambar bukti',
                            style: TextStyle(color: kTextMid, fontSize: 12),
                          ),
                        ),
                        loadingBuilder: (_, anak, progres) => progres == null
                            ? anak
                            : const SizedBox(
                                height: 120,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total tagihan',
                    style: TextStyle(fontSize: 12, color: kTextMid),
                  ),
                  Text(
                    formatRupiah(total),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: kTextDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  key: const ValueKey('bukti-terima'),
                  onPressed: () => Navigator.pop(context, AksiBukti.terima),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text(
                    'Konfirmasi Pembayaran',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kSuccess,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Jalan keluar untuk bukti yang tak sah — tanpa ini, satu-satunya
              // pilihan kasir atas bukti buram adalah menerimanya, dan alur
              // "upload ulang" di halaman pelanggan tak pernah bisa terpicu
              // dari perangkat kasir.
              TextButton(
                key: const ValueKey('bukti-tolak'),
                onPressed: () => Navigator.pop(context, AksiBukti.tolak),
                style: TextButton.styleFrom(foregroundColor: kDanger),
                child: const Text(
                  'Tolak Bukti — minta upload ulang',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
