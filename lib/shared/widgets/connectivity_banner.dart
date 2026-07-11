import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';
import '../../app/theme.dart';
import '../../core/app_icons.dart';
import '../../core/connectivity_service.dart';
import '../../core/i18n.dart';
import '../../core/offline/product_cache.dart';

class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status =
        ref.watch(connectivityProvider).value ?? ConnectionStatus.online;

    if (status == ConnectionStatus.online) return const SizedBox.shrink();

    final isOffline = status == ConnectionStatus.offline;
    final color = isOffline ? kDanger : kWarning;
    final baseMessage = isOffline
        ? ref.t('common.offline')
        : ref.t('common.unstable');
    // Indikator kesegaran: saat offline, beri tahu kapan data tersimpan
    // terakhir disinkron supaya owner sadar bisa jadi sudah basi.
    final syncedAt = ref.watch(offlineDataSyncedAtProvider).value;
    final message = isOffline && syncedAt != null
        ? '$baseMessage • data ${_relativeAge(syncedAt)}'
        : baseMessage;
    final icon = isOffline ? AppIcons.accessRights : AppIcons.inventory;

    return Material(
      color: color,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              HugeIcon(
                icon: icon,
                color: Colors.white,
                size: 18,
              ),
              const Gap(12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  ref.invalidate(connectivityProvider);
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  ref.t('common.retry'),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Umur data relatif untuk indikator kesegaran cache: "baru saja",
/// "X menit lalu", "X jam lalu", "X hari lalu".
String _relativeAge(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'baru saja';
  if (d.inMinutes < 60) return '${d.inMinutes} menit lalu';
  if (d.inHours < 24) return '${d.inHours} jam lalu';
  return '${d.inDays} hari lalu';
}
