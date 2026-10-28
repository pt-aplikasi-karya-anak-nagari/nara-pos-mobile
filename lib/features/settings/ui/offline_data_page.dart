import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/connectivity_service.dart';
import '../../../core/format.dart';
import '../../../core/offline/cadangan_transaksi.dart';
import '../../../core/offline/sale_outbox.dart';
import '../../../core/offline/shift_outbox.dart';
import '../../../core/offline/transaksi_folder.dart';
import '../../../core/offline/product_cache.dart';
import '../../../core/offline/product_folder_store.dart';
import '../../../core/offline/product_offline_sync.dart';
import '../../../core/outlet_scope.dart';
import '../../../core/permission_service.dart';
import '../../../shared/widgets/tablet_components.dart';

/// Status data offline: cadangan produk, add-on, dan transaksi.
///
/// Cadangan disimpan OTOMATIS di penyimpanan tersembunyi & terenkripsi yang
/// tetap ada walau aplikasi di-uninstall (lihat FolderOfflineChannel.kt).
/// Lokasinya sengaja tidak ditampilkan di mana pun — pengguna tak memilih
/// folder, dan kasir tak tahu di mana datanya untuk diubah atau dihapus.
class OfflineDataPage extends HookConsumerWidget {
  const OfflineDataPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(productFolderStoreProvider);
    final outletId = ref.watch(activeOutletIdProvider);
    final outlet = ref.watch(activeOutletProvider);
    final offline = ref.watch(isOfflineProvider);
    final syncedAt = ref.watch(offlineDataSyncedAtProvider).value;
    final isTablet = MediaQuery.of(context).size.width >= 600;

    final memuat = useState(true);
    final aktif = useState(false);
    final jumlah = useState(0);
    final cadanganTransaksi = useState<({int penjualan, int shift})>(
      (penjualan: 0, shift: 0),
    );
    final menunggu = ref.watch(pendingSyncCountProvider);
    final menungguShift = ref.watch(pendingShiftSyncCountProvider);
    final sibuk = useState<String?>(null); // teks proses yang sedang berjalan
    final galat = useState<String?>(null);

    Future<void> muatStatus() async {
      final ok = await store.aktif();
      final n = ok && outletId != null ? await store.jumlah(outletId) : 0;
      final cermin = ref.read(cerminTransaksiProvider);
      final t = ok && outletId != null
          ? await cermin.jumlah(outletId)
          : (penjualan: 0, shift: 0);
      if (!context.mounted) return;
      aktif.value = ok;
      jumlah.value = n;
      cadanganTransaksi.value = t;
      galat.value = store.galatTerakhir ?? cermin.galatTerakhir;
      memuat.value = false;
    }

    useEffect(() {
      muatStatus();
      return null;
    }, [outletId, menunggu, menungguShift]);

    void kabar(String pesan, {bool sukses = true}) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(pesan),
          backgroundColor: sukses ? kSuccess : kDanger,
        ),
      );
    }

    Future<void> simpanSemua() async {
      if (outletId == null || sibuk.value != null) return;
      sibuk.value = 'Menyimpan produk…';
      // 1. Samakan katalog di perangkat dengan server (hanya produk yang
      //    berubah yang diambil).
      final hasil = await ref.read(sinkronProdukProvider).jalankan(paksa: true);
      // 2. Tulis SEMUA produk lokal ke cadangan — termasuk yang tidak berubah.
      //    File yang isinya sama dilewati.
      await ref.read(productCacheProvider).salinKeFolder(outletId);
      sibuk.value = null;
      await muatStatus();
      if (hasil?.galat != null) {
        kabar(
          'Sebagian produk gagal diambil dari server. '
          '${jumlah.value} produk tercadangkan.',
          sukses: false,
        );
      } else if (store.galatTerakhir != null) {
        kabar('Gagal menyimpan cadangan: ${store.galatTerakhir}', sukses: false);
      } else {
        kabar('${jumlah.value} produk tercadangkan.');
      }
    }

    // Menyalakan izin penyimpanan cadangan (biasanya sudah diberikan di
    // gerbang izin saat aplikasi pertama dibuka).
    Future<void> aktifkanCadangan() async {
      if (sibuk.value != null) return;
      sibuk.value = 'Meminta izin…';
      final status = await ref
          .read(systemPermissionServiceProvider)
          .minta(IzinAplikasi.penyimpanan);
      if (status == StatusIzin.ditolakPermanen) {
        await ref.read(systemPermissionServiceProvider).bukaPengaturan();
      }
      final ok = await ref.read(izinCadanganProvider.notifier).periksa();
      if (!ok) {
        sibuk.value = null;
        await muatStatus();
        kabar('Izin penyimpanan cadangan belum diberikan.', sukses: false);
        return;
      }
      store.aksesBerubah();
      ref.read(cerminTransaksiProvider).lupakan();
      sibuk.value = 'Menyiapkan cadangan…';
      final pulih = await siapkanCadanganOffline(ref.read);
      await ref.read(cerminTransaksiProvider).jadwalkan();
      sibuk.value = null;
      await muatStatus();
      kabar(
        pulih.total > 0
            ? '${pulih.penjualan} transaksi offline dipulihkan — akan dikirim '
                  'saat online.'
            : 'Penyimpanan cadangan aktif.',
      );
    }

    final waktu = syncedAt == null ? 'Belum pernah' : formatDateTime(syncedAt);

    final body = SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 40.0 : 16.0,
        vertical: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabletFormIllustration(
                icon: AppIcons.folder,
                color: kPrimary,
                title: 'Data Offline',
                subtitle:
                    'Produk & transaksi ${outlet?.name ?? 'outlet ini'} '
                    'tersimpan di tablet, supaya kasir tetap bisa berjualan '
                    'tanpa internet walau aplikasi di-install ulang.',
              ),
              const _Judul('Penyimpanan cadangan'),
              _Kartu(
                children: [
                  _Baris(
                    label: 'Status',
                    nilai: memuat.value
                        ? 'Memeriksa…'
                        : aktif.value
                        ? 'Aktif'
                        : 'Belum aktif',
                    tebal: true,
                  ),
                  const Gap(10),
                  Text(
                    aktif.value
                        ? 'Produk, add-on, dan transaksi offline dicadangkan '
                              'otomatis & terenkripsi di perangkat ini. Bila '
                              'aplikasi terhapus lalu di-install ulang, datanya '
                              'dipulihkan sendiri.'
                        : 'Tanpa izin ini, transaksi offline yang belum '
                              'terkirim HILANG bila aplikasi terhapus.',
                    style: TextStyle(
                      fontSize: 12,
                      color: aktif.value ? kTextMid : kWarning,
                      height: 1.4,
                    ),
                  ),
                  if (!memuat.value && !aktif.value) ...[
                    const Gap(14),
                    FilledButton(
                      onPressed: sibuk.value == null ? aktifkanCadangan : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: kPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(sibuk.value ?? 'Aktifkan penyimpanan cadangan'),
                    ),
                  ],
                ],
              ),
              const Gap(20),
              const _Judul('Produk outlet ini'),
              _Kartu(
                children: [
                  _Baris(
                    label: 'Tercadangkan',
                    nilai: aktif.value ? '${jumlah.value} produk' : '—',
                    tebal: true,
                  ),
                  const Gap(8),
                  _Baris(label: 'Terakhir diperbarui', nilai: waktu),
                  const Gap(14),
                  OutlinedButton.icon(
                    onPressed:
                        aktif.value &&
                            !offline &&
                            outletId != null &&
                            sibuk.value == null
                        ? simpanSemua
                        : null,
                    icon: sibuk.value != null
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : HugeIcon(icon: AppIcons.refresh, size: 18),
                    label: Text(sibuk.value ?? 'Simpan semua produk sekarang'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  if (offline && aktif.value) ...[
                    const Gap(8),
                    Text(
                      'Sedang offline — produk disimpan otomatis saat online lagi.',
                      style: TextStyle(fontSize: 12, color: kTextMid),
                    ),
                  ],
                  if (galat.value != null) ...[
                    const Gap(8),
                    Text(
                      'Gagal mengakses cadangan: ${galat.value}',
                      style: TextStyle(fontSize: 12, color: kDanger),
                    ),
                  ],
                ],
              ),
              const Gap(20),
              const _Judul('Transaksi offline'),
              _Kartu(
                children: [
                  _Baris(
                    label: 'Belum terkirim',
                    nilai: '$menunggu transaksi'
                        '${menungguShift > 0 ? ' · $menungguShift catatan shift' : ''}',
                    tebal: true,
                  ),
                  const Gap(8),
                  _Baris(
                    label: 'Tercadangkan',
                    nilai: aktif.value
                        ? '${cadanganTransaksi.value.penjualan} transaksi'
                              '${cadanganTransaksi.value.shift > 0 ? ' · ${cadanganTransaksi.value.shift} catatan shift' : ''}'
                        : 'Tidak aktif',
                  ),
                  const Gap(10),
                  Text(
                    aktif.value
                        ? 'Setiap transaksi offline langsung dicadangkan, dan '
                              'cadangannya dihapus setelah diterima server. Bila '
                              'aplikasi terhapus sebelum terkirim, install ulang '
                              'lalu login — transaksinya dipulihkan dan dikirim '
                              'otomatis.'
                        : 'Aktifkan penyimpanan cadangan supaya transaksi '
                              'offline tidak hilang bila aplikasi terhapus '
                              'sebelum sempat terkirim.',
                    style: TextStyle(
                      fontSize: 12,
                      color: aktif.value ? kTextMid : kWarning,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
              const Gap(20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HugeIcon(
                      icon: AppIcons.alertCircle,
                      color: kPrimary,
                      size: 18,
                    ),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        'Semua berjalan otomatis: produk diperbarui setiap kali '
                        'dimuat dari server, dan transaksi offline dikirim '
                        'begitu internet kembali. Cadangan hanya bisa dibaca '
                        'oleh aplikasi ini di perangkat ini.',
                        style: TextStyle(
                          fontSize: 12,
                          color: kTextMid,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Data Offline'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: body,
    );
  }
}

class _Judul extends StatelessWidget {
  final String teks;
  const _Judul(this.teks);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        teks.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: kTextMid,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _Kartu extends StatelessWidget {
  final List<Widget> children;
  const _Kartu({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _Baris extends StatelessWidget {
  final String label;
  final String nilai;
  final bool tebal;
  const _Baris({required this.label, required this.nilai, this.tebal = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: kTextMid)),
        const Gap(12),
        Expanded(
          child: Text(
            nilai,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: tebal ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
