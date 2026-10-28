import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/theme.dart';
import '../../core/offline/sale_outbox.dart';
import '../../core/offline/shift_outbox.dart';
import 'dead_letter_recovery_sheet.dart';

/// Banner MERAH untuk data offline yang GAGAL permanen (dead-letter): transaksi
/// dan catatan buka/tutup shift yang ditolak server — perlu aksi owner
/// (pulihkan/buang) supaya tidak hilang diam-diam.
///
/// Antrian yang masih MENUNGGU dikirim (dan progres pengirimannya) tampil di
/// [AntrianOfflineFloating]. Kegagalan permanen sengaja tetap di sini: banner
/// tak bisa digeser menjauh atau ditutup, jadi tak bisa terlewat.
class PendingSyncBanner extends ConsumerWidget {
  const PendingSyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dead = ref.watch(deadLetterCountProvider);
    // Dead-letter SHIFT dihitung sejak lama tapi tak pernah ditampilkan di
    // permukaan mana pun — satu-satunya yang membacanya adalah penyinkron, untuk
    // menyegarkan angkanya sendiri. Akibatnya catatan tutup shift yang ditolak
    // permanen (uang laci, catatan penutup) hilang diam-diam: tak sampai ke
    // server, dan tak bisa dipulihkan dari aplikasi. Z-Report untuk shift itu
    // tak pernah terbit, dan rekonsiliasi kas hari itu tak bisa diselesaikan.
    final shiftDead = ref.watch(shiftDeadLetterCountProvider);
    if (dead <= 0 && shiftDead <= 0) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dead > 0)
            _BannerRow(
              color: kDanger,
              icon: Icons.error_outline_rounded,
              text: '$dead transaksi gagal terkirim',
              actionLabel: 'Pulihkan',
              onAction: () => showDeadLetterRecoverySheet(context, ref),
            ),
          if (shiftDead > 0)
            _BannerRow(
              color: kDanger,
              icon: Icons.point_of_sale_outlined,
              // Disebut "buka/tutup shift", bukan "operasi shift": yang hilang
              // adalah catatan uang laci, dan kasir perlu langsung mengenali
              // bahwa itu yang sedang dibicarakan.
              text: '$shiftDead catatan buka/tutup shift gagal terkirim',
              actionLabel: 'Pulihkan',
              onAction: () => showDeadLetterRecoverySheet(context, ref),
            ),
        ],
      ),
    );
  }
}

class _BannerRow extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  const _BannerRow({
    required this.color,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const Gap(12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null)
              TextButton(
                onPressed: () => onAction!(),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
