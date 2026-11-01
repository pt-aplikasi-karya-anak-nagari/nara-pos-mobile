import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';
import '../../app/theme.dart';
import '../../core/app_icons.dart';
import '../../core/connectivity_service.dart';
import '../../core/sesi_login.dart';
import '../../core/i18n.dart';
import '../../core/offline/jam_offline.dart';
import '../../core/offline/jam_terpercaya.dart';
import '../../core/offline/product_cache.dart';
import '../../core/outlet_scope.dart';
import '../../features/settings/data/app_settings.dart';

class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status =
        ref.watch(connectivityProvider).value ?? ConnectionStatus.online;
    // Jam perangkat diubah — ditampilkan online maupun offline: offline
    // penjualan ditahan, online struk mencetak jam yang salah.
    final jam = ref.watch(peringatanJamProvider).value;

    if (status == ConnectionStatus.online) {
      if (jam == null) return const SizedBox.shrink();
      return _BannerJam(pesan: jam);
    }

    final isOffline = status == ConnectionStatus.offline;
    final color = isOffline ? kDanger : kWarning;
    final baseMessage = isOffline
        ? ref.t('common.offline')
        : ref.t('common.unstable');
    // Indikator kesegaran: saat offline, beri tahu kapan data tersimpan
    // terakhir disinkron supaya owner sadar bisa jadi sudah basi.
    final syncedAt = ref.watch(offlineDataSyncedAtProvider).value;
    // Sesi login hampir / sudah berakhir — hanya relevan saat offline:
    // online, sesi diperbarui otomatis.
    final sesi = isOffline ? ref.watch(peringatanSesiProvider) : null;
    // Batas lama offline (Pengaturan App) hampir tercapai.
    final batas = isOffline
        ? ref.watch(peringatanBatasOfflineProvider).value
        : null;
    final message = [
      baseMessage,
      ?jam,
      if (isOffline && syncedAt != null) 'data ${_relativeAge(syncedAt)}',
      ?batas,
      ?sesi,
    ].join(' • ');
    final icon = isOffline ? AppIcons.accessRights : AppIcons.inventory;

    return Material(
      color: color,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              HugeIcon(icon: icon, color: Colors.white, size: 18),
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
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
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

/// Peringatan batas lama offline untuk banner — bergerak tiap menit.
final peringatanBatasOfflineProvider = FutureProvider<String?>((ref) async {
  ref.watch(detakMenitProvider);
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return null;
  final batas = batasOfflineEfektif(
    (await bacaAppSettingsTersimpan(outletId)).maxOfflineHours,
  );
  return peringatanBatasOffline(
    ref.read(jamOfflineProvider).lamaOffline(),
    batas,
  );
});

/// Peringatan jam perangkat untuk banner, atau null bila jamnya wajar.
/// Diperiksa tiap menit — mengubah jam di Pengaturan lalu kembali ke
/// aplikasi langsung terlihat.
final peringatanJamProvider = FutureProvider<String?>((ref) async {
  ref.watch(detakMenitProvider);
  final jam = ref.read(jamOfflineProvider);
  final offline = ref.watch(isOfflineProvider);
  if (offline) {
    final p = await jam.periksa();
    if (p.wajar) return null;
    final arah = p.status == StatusJam.dimajukan ? 'dimajukan' : 'dimundurkan';
    return 'jam perangkat $arah ${teksDurasi(p.selisih)} — transaksi '
        'offline ditahan, betulkan jamnya';
  }
  // Online: server memakai jamnya sendiri, tapi struk mencetak jam perangkat.
  final selisih = jam.selisihSaatOnline;
  if (selisih == null || selisih.abs() <= toleransiJam) return null;
  final arah = selisih.isNegative ? 'terlambat' : 'terlalu cepat';
  return 'Jam perangkat $arah ${teksDurasi(selisih)} dari jam server — '
      'nyalakan "Tanggal & waktu otomatis" supaya jam di struk benar';
});

class _BannerJam extends StatelessWidget {
  final String pesan;
  const _BannerJam({required this.pesan});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kWarning,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.schedule_rounded, color: Colors.white, size: 18),
              const Gap(12),
              Expanded(
                child: Text(
                  pesan,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
