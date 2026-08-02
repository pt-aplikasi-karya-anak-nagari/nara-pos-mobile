import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/theme.dart';
import '../../core/connectivity_service.dart';
import '../../core/offline/offline_sync_service.dart';
import '../../core/offline/sale_outbox.dart';
import '../../core/offline/shift_outbox.dart';
import 'dead_letter_recovery_sheet.dart';

/// Banner status sinkron offline. Dua baris terpisah:
///  - KUNING: transaksi menunggu sinkron (akan terkirim otomatis saat online).
///  - MERAH: transaksi GAGAL permanen (dead-letter) — perlu aksi owner
///    (pulihkan/buang) supaya tidak hilang diam-diam.
/// Sinkron otomatis tetap berjalan via [offlineAutoSyncProvider].
class PendingSyncBanner extends ConsumerWidget {
  const PendingSyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingSyncCountProvider);
    final dead = ref.watch(deadLetterCountProvider);
    final shiftPending = ref.watch(pendingShiftSyncCountProvider);
    // Dead-letter SHIFT dihitung sejak lama tapi tak pernah ditampilkan di
    // permukaan mana pun — satu-satunya yang membacanya adalah penyinkron, untuk
    // menyegarkan angkanya sendiri. Akibatnya catatan tutup shift yang ditolak
    // permanen (uang laci, catatan penutup) hilang diam-diam: tak sampai ke
    // server, dan tak bisa dipulihkan dari aplikasi. Z-Report untuk shift itu
    // tak pernah terbit, dan rekonsiliasi kas hari itu tak bisa diselesaikan.
    final shiftDead = ref.watch(shiftDeadLetterCountProvider);
    if (pending <= 0 && dead <= 0 && shiftPending <= 0 && shiftDead <= 0) {
      return const SizedBox.shrink();
    }

    final online =
        (ref.watch(connectivityProvider).value ?? ConnectionStatus.online) ==
            ConnectionStatus.online;

    return SafeArea(
      bottom: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (shiftPending > 0)
            _BannerRow(
              color: kPrimary,
              icon: Icons.point_of_sale_outlined,
              text: '$shiftPending operasi shift menunggu sync'
                  '${online ? '' : ' • menunggu koneksi'}',
            ),
          if (pending > 0)
            _BannerRow(
              color: kWarning,
              icon: Icons.cloud_upload_outlined,
              text: '$pending transaksi menunggu sinkron'
                  '${online ? '' : ' • menunggu koneksi'}',
              actionLabel: online ? 'Sinkronkan' : null,
              onAction: online
                  ? () async {
                      final r =
                          await ref.read(offlineSyncServiceProvider).sync();
                      if (!context.mounted) return;
                      final msg = r.synced > 0
                          ? '${r.synced} transaksi tersinkron'
                              '${r.failed > 0 ? ', ${r.failed} gagal' : ''}'
                          : r.failed > 0
                              ? '${r.failed} transaksi gagal — cek "Pulihkan"'
                              : 'Belum ada yang bisa disinkronkan';
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(msg)));
                    }
                  : null,
            ),
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
