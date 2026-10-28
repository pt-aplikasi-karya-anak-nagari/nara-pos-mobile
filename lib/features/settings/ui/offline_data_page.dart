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
import '../../../shared/widgets/tablet_components.dart';

/// Pengaturan folder tempat produk disimpan untuk dipakai offline.
///
/// Produk outlet yang sedang login disimpan satu file per produk di folder
/// pilihan pengguna, sehingga tetap ada walau aplikasi di-uninstall. Setelah
/// install ulang, pengguna cukup memilih folder yang sama di halaman ini.
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
    final namaFolder = useState<String?>(null);
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
      final nama = ok ? await store.namaFolder() : null;
      final n = ok && outletId != null ? await store.jumlah(outletId) : 0;
      final cermin = ref.read(cerminTransaksiProvider);
      final t = ok && outletId != null
          ? await cermin.jumlah(outletId)
          : (penjualan: 0, shift: 0);
      if (!context.mounted) return;
      aktif.value = ok;
      namaFolder.value = nama;
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
      // 2. Tulis SEMUA produk lokal ke folder — termasuk yang tidak berubah,
      //    yang belum pernah ditulis ke folder ini. File yang isinya sama
      //    dilewati.
      await ref.read(productCacheProvider).salinKeFolder(outletId);
      sibuk.value = null;
      await muatStatus();
      if (hasil?.galat != null) {
        kabar(
          'Sebagian produk gagal diambil dari server. '
          '${jumlah.value} produk tersimpan di folder.',
          sukses: false,
        );
      } else if (store.galatTerakhir != null) {
        kabar('Gagal menulis ke folder: ${store.galatTerakhir}', sukses: false);
      } else {
        kabar('${jumlah.value} produk tersimpan di folder.');
      }
    }

    Future<void> pilihFolder() async {
      if (sibuk.value != null) return;
      sibuk.value = 'Membuka pemilih folder…';
      bool dipilih;
      try {
        dipilih = await store.pilihFolder();
      } catch (e) {
        sibuk.value = null;
        kabar('Folder tidak bisa dipakai: $e', sukses: false);
        return;
      }
      sibuk.value = null;
      if (!dipilih) {
        await muatStatus();
        return;
      }

      // Transaksi offline lebih dulu dari produk: setelah install ulang,
      // folder ini mungkin berisi penjualan yang belum sampai ke server.
      final cermin = ref.read(cerminTransaksiProvider)..lupakan();
      ref.invalidate(folderCadanganAktifProvider);
      sibuk.value = 'Memulihkan transaksi offline…';
      final pulih = await pulihkanTransaksiOffline(ref.read);
      // Antrian yang sudah ada di perangkat ikut ditulis ke folder baru.
      await cermin.jadwalkan();
      sibuk.value = null;
      await muatStatus();
      if (pulih.total > 0) {
        kabar(
          '${pulih.penjualan} transaksi offline dipulihkan dari folder'
          '${pulih.shift > 0 ? ' (+${pulih.shift} catatan shift)' : ''}'
          ' — akan dikirim saat online.',
        );
      }

      if (offline || outletId == null) {
        // Tanpa internet: salin katalog yang sudah ada di perangkat ke folder.
        // Pada tablet yang baru di-install ulang, arahnya terbalik — produk
        // dibaca DARI folder ini saat halaman kasir dibuka.
        if (outletId != null) {
          await ref.read(productCacheProvider).salinKeFolder(outletId);
          await muatStatus();
        }
        kabar(
          jumlah.value > 0
              ? 'Folder dipilih. ${jumlah.value} produk siap dipakai offline.'
              : 'Folder dipilih. Produk akan disimpan saat online.',
        );
        return;
      }
      await simpanSemua();
    }

    Future<void> lepasFolder() async {
      final ya = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Berhenti menyimpan ke folder?'),
          content: const Text(
            'File yang sudah ada di folder tidak dihapus. Produk dan '
            'transaksi offline tetap tersimpan di aplikasi, tapi akan hilang '
            'bila aplikasi di-uninstall sebelum transaksinya terkirim.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Berhenti', style: TextStyle(color: kDanger)),
            ),
          ],
        ),
      );
      if (ya != true) return;
      await store.lepasFolder();
      ref.read(cerminTransaksiProvider).lupakan();
      ref.invalidate(folderCadanganAktifProvider);
      await muatStatus();
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
                    'Simpan produk ${outlet?.name ?? 'outlet ini'} ke folder di '
                    'tablet, supaya kasir tetap bisa berjualan tanpa internet '
                    'walau aplikasi di-install ulang.',
              ),
              const _Judul('Folder penyimpanan'),
              _Kartu(
                children: [
                  _Baris(
                    label: 'Folder',
                    nilai: memuat.value
                        ? 'Memeriksa…'
                        : aktif.value
                        ? (namaFolder.value ?? 'Terpilih')
                        : 'Belum dipilih',
                    tebal: aktif.value,
                  ),
                  const Gap(14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: sibuk.value == null ? pilihFolder : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: kPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            aktif.value ? 'Ganti folder' : 'Pilih folder',
                          ),
                        ),
                      ),
                      if (aktif.value) ...[
                        const Gap(10),
                        OutlinedButton(
                          onPressed: sibuk.value == null ? lepasFolder : null,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 18,
                            ),
                          ),
                          child: const Text('Berhenti'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const Gap(20),
              const _Judul('Produk outlet ini'),
              _Kartu(
                children: [
                  _Baris(
                    label: 'Tersimpan di folder',
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
                      'Gagal mengakses folder: ${galat.value}',
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
                    label: 'Cadangan di folder',
                    nilai: aktif.value
                        ? '${cadanganTransaksi.value.penjualan} transaksi'
                              '${cadanganTransaksi.value.shift > 0 ? ' · ${cadanganTransaksi.value.shift} catatan shift' : ''}'
                        : 'Tidak aktif',
                  ),
                  const Gap(10),
                  Text(
                    aktif.value
                        ? 'Setiap transaksi offline langsung disalin ke folder ini '
                              'dan dihapus dari folder setelah diterima server. '
                              'Bila aplikasi terhapus sebelum terkirim, install '
                              'ulang lalu pilih folder yang sama — transaksinya '
                              'dipulihkan dan dikirim otomatis.'
                        : 'Pilih folder supaya transaksi offline tidak hilang '
                              'bila aplikasi terhapus atau di-uninstall sebelum '
                              'sempat terkirim.',
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
                        'Buat atau pilih folder khusus, misalnya Documents/NaraPOS. '
                        'Setiap produk disimpan sebagai satu file, dikelompokkan '
                        'per outlet, dan diperbarui otomatis setiap kali produk '
                        'berhasil dimuat dari server.\n\n'
                        'Setelah aplikasi di-install ulang, buka halaman ini dan '
                        'pilih folder yang SAMA — produk langsung bisa dipakai '
                        'walau belum ada internet.',
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
