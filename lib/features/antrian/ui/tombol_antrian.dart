import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../data/antrian_service.dart';
import 'antrian_sheet.dart';

/// Tombol ringkas di header kasir: nomor yang sedang dipanggil + jumlah yang
/// menunggu. Ketuk untuk membuka panel antrian.
class TombolAntrian extends ConsumerWidget {
  const TombolAntrian({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(ringkasanAntrianProvider).value;
    final nomor = r?.sedangDipanggil?.nomor ?? '—';
    final menunggu = r?.menunggu ?? 0;
    return Semantics(
      button: true,
      label: 'Antrian, sedang dipanggil $nomor, $menunggu menunggu',
      excludeSemantics: true,
      child: Material(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => bukaPanelAntrian(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.campaign_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Antrian $nomor',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '$menunggu menunggu · ${r?.total ?? 0} hari ini',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
