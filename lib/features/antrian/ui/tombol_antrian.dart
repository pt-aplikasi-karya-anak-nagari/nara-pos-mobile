import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/theme.dart';
import '../../settings/data/app_settings.dart';
import '../data/antrian_service.dart';
import 'antrian_sheet.dart';

/// Tombol ringkas di kepala panel "Pesanan": nomor yang sedang dipanggil +
/// jumlah menunggu + total hari ini. Ketuk untuk membuka panel antrian.
class TombolAntrian extends ConsumerWidget {
  const TombolAntrian({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pemilik mematikan fitur antrian → tombolnya tak ditampilkan.
    final aktif =
        ref.watch(outletAppSettingsProvider).value?.antrianAktif ?? true;
    final r = ref.watch(ringkasanAntrianProvider).value;
    if (!aktif || r?.aktif == false) return const SizedBox.shrink();
    final nomor = r?.sedangDipanggil?.nomor ?? '—';
    final menunggu = r?.menunggu ?? 0;
    return Semantics(
      button: true,
      label: 'Antrian, sedang dipanggil $nomor, $menunggu menunggu',
      excludeSemantics: true,
      child: Material(
        color: kPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => bukaPanelAntrian(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.campaign_rounded, color: kPrimary, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Antrian $nomor',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '$menunggu menunggu · ${r?.total ?? 0} hari ini',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: kTextMid, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: kPrimary,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
