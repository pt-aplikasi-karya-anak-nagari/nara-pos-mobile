import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../antrian/data/antrian_service.dart';

/// Nomor antrian besar setelah pembayaran — yang dipanggil kasir/dapur saat
/// pesanan siap. Dipakai dialog sukses & detail transaksi.
class KartuNomorAntrian extends StatelessWidget {
  const KartuNomorAntrian({
    super.key,
    required this.nomor,
    this.ringkas = false,
  });

  final String nomor;

  /// Versi kecil (satu baris) untuk daftar/detail.
  final bool ringkas;

  @override
  Widget build(BuildContext context) {
    if (ringkas) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: kPrimary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Antrian $nomor',
          style: const TextStyle(
            color: kPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      );
    }
    return Semantics(
      label: 'Nomor antrian $nomor',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: kPrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kPrimary.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            const Text(
              'Nomor Antrian',
              style: TextStyle(
                color: kPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              child: Text(
                nomor,
                style: const TextStyle(
                  color: kPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 44,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Total antrian hari ini · menunggu" di bawah nomor antrian (dialog sukses).
class InfoAntrianHariIni extends ConsumerWidget {
  const InfoAntrianHariIni({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(ringkasanAntrianProvider).value;
    if (r == null || !r.aktif || r.total == 0) return const SizedBox.shrink();
    return Text(
      'Total antrian hari ini ${r.total} · ${r.menunggu} menunggu',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: kTextMid),
    );
  }
}
