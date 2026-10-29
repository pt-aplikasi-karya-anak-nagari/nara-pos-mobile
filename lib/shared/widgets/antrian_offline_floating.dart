import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/theme.dart';
import '../../core/connectivity_service.dart';
import '../../core/format.dart';
import '../../core/offline/cadangan_transaksi.dart';
import '../../core/offline/offline_sync_service.dart';
import '../../core/offline/sale_outbox.dart';
import '../../core/offline/shift_outbox.dart';
import 'dead_letter_recovery_sheet.dart';

/// Isi antrian offline untuk panel floating: transaksi yang masih akan dikirim
/// dan yang gagal permanen.
class AntrianOffline {
  const AntrianOffline({this.menunggu = const [], this.gagal = const []});
  final List<PendingSale> menunggu;
  final List<PendingSale> gagal;
}

final antrianOfflineProvider = FutureProvider.autoDispose<AntrianOffline>((
  ref,
) async {
  // Dihitung ulang setiap jumlah antrian berubah atau satu transaksi selesai
  // dikirim.
  ref.watch(pendingSyncCountProvider);
  ref.watch(deadLetterCountProvider);
  ref.watch(progresSinkronProvider.select((p) => p.diproses));
  final outbox = ref.read(saleOutboxProvider);
  return AntrianOffline(
    menunggu: await outbox.pending(),
    gagal: await outbox.deadLetters(),
  );
});

/// Status antrian offline yang melayang di atas semua halaman.
///
/// Muncul hanya bila ada sesuatu yang perlu diketahui kasir:
///   - transaksi / operasi shift tersimpan di perangkat, menunggu dikirim;
///   - sedang mengirim (dengan progres "2 dari 5");
///   - baru saja selesai mengirim (beberapa detik, lalu hilang sendiri);
///   - ada yang gagal terkirim.
///
/// Ketuk untuk membuka rincian: daftar transaksi, tombol kirim sekarang, dan
/// pemulihan yang gagal. Bisa digeser ke sisi kiri/kanan layar supaya tidak
/// menutupi tombol kasir.
///
/// Baris merah "gagal terkirim" di [PendingSyncBanner] sengaja TETAP ada:
/// kegagalan permanen tidak boleh bisa disingkirkan dari pandangan dengan
/// menggeser sebuah tombol.
class AntrianOfflineFloating extends HookConsumerWidget {
  const AntrianOfflineFloating({super.key, this.bukaSheetPulihkan});

  /// Pembuka sheet pemulihan. Widget ini berada di luar Navigator aplikasi,
  /// jadi pemanggil memberikan context milik navigator.
  final void Function(WidgetRef ref)? bukaSheetPulihkan;

  /// Lama status "terkirim" tetap tampil setelah pengiriman selesai.
  static const durasiSukses = Duration(seconds: 4);

  // Posisi diingat selama aplikasi berjalan (bukan per halaman).
  static bool _diKanan = false;
  static double _dariBawah = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menunggu = ref.watch(pendingSyncCountProvider);
    final gagal = ref.watch(deadLetterCountProvider);
    final shiftMenunggu = ref.watch(pendingShiftSyncCountProvider);
    final shiftGagal = ref.watch(shiftDeadLetterCountProvider);
    final progres = ref.watch(progresSinkronProvider);
    final status =
        ref.watch(connectivityProvider).value ?? ConnectionStatus.online;
    final offline = status == ConnectionStatus.offline;

    final terbuka = useState(false);
    final diKanan = useState(_diKanan);
    final dariBawah = useState(_dariBawah);
    final geser = useState<Offset?>(null);

    // Status "terkirim" hanya tampil sebentar setelah pengiriman selesai.
    // Status "terkirim" tampil sebentar setelah pengiriman selesai, lalu
    // disembunyikan oleh pewaktunya sendiri. Hasil lama (mis. saat widget
    // baru dipasang) yang sudah lewat durasinya tidak ditampilkan lagi.
    final selesaiPada = progres.selesaiPada;
    final kedaluwarsa = useState<DateTime?>(null);
    final suksesBaru =
        selesaiPada != null &&
        progres.terkirimTerakhir > 0 &&
        kedaluwarsa.value != selesaiPada &&
        DateTime.now().difference(selesaiPada) < durasiSukses;
    useEffect(() {
      if (selesaiPada == null) return null;
      final sisa = durasiSukses - DateTime.now().difference(selesaiPada);
      final t = Future.delayed(sisa.isNegative ? Duration.zero : sisa, () {
        if (context.mounted) kedaluwarsa.value = selesaiPada;
      });
      return () => t.ignore();
    }, [selesaiPada]);

    final adaAntrian = menunggu > 0 || shiftMenunggu > 0;
    final adaGagal = gagal > 0 || shiftGagal > 0;
    final tampil = adaAntrian || adaGagal || progres.berjalan || suksesBaru;
    if (!tampil) {
      if (terbuka.value) terbuka.value = false;
      return const SizedBox.shrink();
    }

    final keadaan = _Keadaan.dari(
      berjalan: progres.berjalan,
      offline: offline,
      adaAntrian: adaAntrian,
      suksesBaru: suksesBaru,
      adaGagal: adaGagal,
    );

    final media = MediaQuery.of(context);
    final lebarLayar = media.size.width;
    final lebarPanel = (lebarLayar - 32).clamp(0.0, 380.0);
    final tinggiMaks = media.size.height * 0.6;
    final batasBawah = media.padding.bottom + 12;
    final batasAtas = media.size.height - media.padding.top - 120;

    Widget isi;
    if (terbuka.value) {
      isi = SizedBox(
        width: lebarPanel,
        child: _Panel(
          keadaan: keadaan,
          menunggu: menunggu,
          shiftMenunggu: shiftMenunggu,
          gagal: gagal,
          shiftGagal: shiftGagal,
          progres: progres,
          offline: offline,
          tinggiMaks: tinggiMaks,
          onTutup: () => terbuka.value = false,
          onKirim: () => ref.read(offlineSyncServiceProvider).sync(),
          onPulihkan: bukaSheetPulihkan == null
              ? null
              : () => bukaSheetPulihkan!(ref),
        ),
      );
    } else {
      isi = _Pil(
        keadaan: keadaan,
        menunggu: menunggu + shiftMenunggu,
        gagal: gagal + shiftGagal,
        progres: progres,
        onTap: () => terbuka.value = true,
      );
    }

    // Saat digeser, ikuti jari; saat dilepas, menempel ke sisi terdekat.
    final posisiGeser = geser.value;
    return Stack(
      children: [
        AnimatedPositioned(
          duration: posisiGeser == null
              ? const Duration(milliseconds: 220)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          left: posisiGeser != null
              ? posisiGeser.dx
              : (diKanan.value ? null : 16),
          right: posisiGeser == null && diKanan.value ? 16 : null,
          bottom: posisiGeser != null ? posisiGeser.dy : dariBawah.value,
          child: GestureDetector(
            onPanStart: terbuka.value
                ? null
                : (d) {
                    final kotak = context.findRenderObject() as RenderBox?;
                    final lokal =
                        kotak?.globalToLocal(d.globalPosition) ??
                        d.globalPosition;
                    geser.value = Offset(
                      (lokal.dx - 60).clamp(0, lebarLayar - 120),
                      dariBawah.value,
                    );
                  },
            onPanUpdate: terbuka.value
                ? null
                : (d) {
                    final s = geser.value;
                    if (s == null) return;
                    geser.value = Offset(
                      (s.dx + d.delta.dx).clamp(0, lebarLayar - 120),
                      (s.dy - d.delta.dy).clamp(batasBawah, batasAtas),
                    );
                  },
            onPanEnd: terbuka.value
                ? null
                : (_) {
                    final s = geser.value;
                    if (s == null) return;
                    diKanan.value = s.dx > lebarLayar / 2 - 60;
                    dariBawah.value = s.dy;
                    _diKanan = diKanan.value;
                    _dariBawah = dariBawah.value;
                    geser.value = null;
                  },
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: diKanan.value
                  ? Alignment.bottomRight
                  : Alignment.bottomLeft,
              child: isi,
            ),
          ),
        ),
      ],
    );
  }
}

/// Keadaan yang ditampilkan, berurutan dari yang paling penting.
enum _Keadaan {
  mengirim,
  gagal,
  offline,
  menunggu,
  terkirim;

  static _Keadaan dari({
    required bool berjalan,
    required bool offline,
    required bool adaAntrian,
    required bool suksesBaru,
    required bool adaGagal,
  }) {
    if (berjalan) return mengirim;
    if (adaAntrian) return offline ? _Keadaan.offline : menunggu;
    if (adaGagal) return gagal;
    if (suksesBaru) return terkirim;
    return menunggu;
  }

  Color get warna => switch (this) {
    mengirim => kPrimary,
    gagal => kDanger,
    _Keadaan.offline => const Color(0xFF334155),
    menunggu => const Color(0xFFB45309),
    terkirim => const Color(0xFF15803D),
  };

  IconData get ikon => switch (this) {
    mengirim => Icons.cloud_sync_outlined,
    gagal => Icons.error_outline_rounded,
    _Keadaan.offline => Icons.cloud_off_outlined,
    menunggu => Icons.cloud_upload_outlined,
    terkirim => Icons.cloud_done_outlined,
  };
}

class _Pil extends StatelessWidget {
  const _Pil({
    required this.keadaan,
    required this.menunggu,
    required this.gagal,
    required this.progres,
    required this.onTap,
  });

  final _Keadaan keadaan;
  final int menunggu;
  final int gagal;
  final ProgresSinkron progres;
  final VoidCallback onTap;

  String get _teks => switch (keadaan) {
    _Keadaan.mengirim =>
      'Mengirim ${(progres.diproses + 1).clamp(1, progres.total)}'
          ' dari ${progres.total}',
    _Keadaan.offline => '$menunggu tersimpan offline',
    _Keadaan.menunggu =>
      progres.tertahanLangganan
          ? '$menunggu menunggu perpanjangan langganan'
          : '$menunggu menunggu dikirim',
    _Keadaan.gagal => '$gagal gagal terkirim',
    _Keadaan.terkirim => '${progres.terkirimTerakhir} terkirim',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$_teks. Ketuk untuk rincian antrian offline.',
      child: Material(
        color: keadaan.warna,
        elevation: 6,
        shadowColor: Colors.black38,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 16, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (keadaan == _Keadaan.mengirim)
                        CircularProgressIndicator(
                          value: progres.total > 0 ? progres.rasio : null,
                          strokeWidth: 2.5,
                          color: Colors.white,
                          backgroundColor: Colors.white24,
                        ),
                      Icon(keadaan.ikon, color: Colors.white, size: 16),
                    ],
                  ),
                ),
                const Gap(8),
                Text(
                  _teks,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // Gagal ditampilkan juga saat keadaan utamanya lain, supaya
                // tidak tertutup oleh antrian yang sedang menunggu.
                if (gagal > 0 && keadaan != _Keadaan.gagal) ...[
                  const Gap(8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: kDanger,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                    child: Text(
                      '$gagal gagal',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends ConsumerWidget {
  const _Panel({
    required this.keadaan,
    required this.menunggu,
    required this.shiftMenunggu,
    required this.gagal,
    required this.shiftGagal,
    required this.progres,
    required this.offline,
    required this.tinggiMaks,
    required this.onTutup,
    required this.onKirim,
    required this.onPulihkan,
  });

  final _Keadaan keadaan;
  final int menunggu;
  final int shiftMenunggu;
  final int gagal;
  final int shiftGagal;
  final ProgresSinkron progres;
  final bool offline;
  final double tinggiMaks;
  final VoidCallback onTutup;
  final VoidCallback onKirim;
  final VoidCallback? onPulihkan;

  String get _judul => switch (keadaan) {
    _Keadaan.mengirim => 'Mengirim ke server…',
    _Keadaan.offline => 'Mode offline',
    _Keadaan.menunggu => 'Menunggu dikirim',
    _Keadaan.gagal => 'Ada yang gagal terkirim',
    _Keadaan.terkirim => 'Semua terkirim',
  };

  String get _keterangan {
    if (keadaan == _Keadaan.mengirim) {
      return '${progres.diproses} dari ${progres.total} selesai diproses.';
    }
    if (keadaan == _Keadaan.terkirim) {
      return '${progres.terkirimTerakhir} data offline sudah tersimpan di server.';
    }
    if (offline) {
      return 'Transaksi aman tersimpan di perangkat ini dan dikirim otomatis '
          'begitu internet kembali. Jangan hapus aplikasi atau datanya '
          'sebelum semua terkirim.';
    }
    if (menunggu + shiftMenunggu > 0) {
      return 'Dikirim otomatis. Bila server belum terjangkau, aplikasi '
          'mencoba lagi setiap 30 detik.';
    }
    return 'Server menolak data berikut. Periksa lalu kirim ulang atau buang.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final antrian = ref.watch(antrianOfflineProvider).value;
    final adaCadangan = ref.watch(izinCadanganProvider);
    final adaAntrian = menunggu + shiftMenunggu + gagal + shiftGagal > 0;
    final bisaKirim =
        !offline && !progres.berjalan && menunggu + shiftMenunggu > 0;

    return Material(
      color: kCard,
      elevation: 10,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: tinggiMaks),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: keadaan.warna,
              padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
              child: Row(
                children: [
                  Icon(keadaan.ikon, color: Colors.white, size: 20),
                  const Gap(10),
                  Expanded(
                    child: Text(
                      _judul,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  // Tanpa tooltip: widget ini di luar Navigator, jadi tak
                  // punya Overlay yang dibutuhkan Tooltip.
                  IconButton(
                    onPressed: onTutup,
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            if (keadaan == _Keadaan.mengirim)
              LinearProgressIndicator(
                value: progres.total > 0 ? progres.rasio : null,
                minHeight: 3,
                color: kPrimary,
                backgroundColor: kPrimary.withValues(alpha: 0.15),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                _keterangan,
                style: TextStyle(fontSize: 12, color: kTextMid, height: 1.4),
              ),
            ),
            // Apakah antrian ini selamat bila aplikasi terhapus.
            if (adaAntrian && adaCadangan != null)
              _BarisInfo(
                ikon: adaCadangan
                    ? Icons.verified_user_outlined
                    : Icons.warning_amber_rounded,
                warna: adaCadangan ? kSuccess : kWarning,
                teks: adaCadangan
                    ? 'Tercadangkan otomatis di perangkat — aman walau '
                          'aplikasi terhapus.'
                    : 'Penyimpanan cadangan belum aktif: transaksi ini hilang '
                          'bila aplikasi terhapus. Aktifkan di Profil › Data '
                          'Offline.',
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (final s in antrian?.menunggu ?? const <PendingSale>[])
                    _BarisTransaksi(
                      sale: s,
                      sedangDikirim:
                          progres.berjalan &&
                          progres.sedangDikirim == s.localId,
                    ),
                  for (final s in antrian?.gagal ?? const <PendingSale>[])
                    _BarisTransaksi(sale: s, gagalPermanen: true),
                  if (shiftMenunggu > 0)
                    _BarisInfo(
                      ikon: Icons.point_of_sale_outlined,
                      teks:
                          '$shiftMenunggu catatan buka/tutup shift ikut '
                          'dikirim',
                    ),
                  if (shiftGagal > 0)
                    _BarisInfo(
                      ikon: Icons.error_outline_rounded,
                      warna: kDanger,
                      teks:
                          '$shiftGagal catatan buka/tutup shift gagal '
                          'terkirim',
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: kDivider),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if ((gagal > 0 || shiftGagal > 0) && onPulihkan != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onPulihkan,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kDanger,
                          side: const BorderSide(color: kDanger),
                        ),
                        child: Text('Pulihkan (${gagal + shiftGagal})'),
                      ),
                    ),
                  if ((gagal > 0 || shiftGagal > 0) && onPulihkan != null)
                    const Gap(10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: bisaKirim ? onKirim : null,
                      style: FilledButton.styleFrom(backgroundColor: kPrimary),
                      icon: progres.berjalan
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: Text(
                        progres.berjalan
                            ? 'Mengirim…'
                            : offline
                            ? 'Menunggu internet'
                            : 'Kirim sekarang',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarisTransaksi extends StatelessWidget {
  const _BarisTransaksi({
    required this.sale,
    this.sedangDikirim = false,
    this.gagalPermanen = false,
  });

  final PendingSale sale;
  final bool sedangDikirim;
  final bool gagalPermanen;

  @override
  Widget build(BuildContext context) {
    final p = sale.payload;
    final total = (p['final_amount'] as num?) ?? 0;
    final items = p['items'];
    final jumlahItem = items is List
        ? items.fold<num>(
            0,
            (n, i) => n + ((i is Map ? i['quantity'] : 0) as num? ?? 0),
          )
        : 0;
    final waktu =
        DateTime.tryParse(p['occurred_at']?.toString() ?? '') ?? sale.createdAt;
    final metode = p['payment_method']?.toString() ?? '';

    final (label, warna) = gagalPermanen
        ? ('Gagal', kDanger)
        : sedangDikirim
        ? ('Mengirim…', kPrimary)
        : sale.attempts > 0
        ? ('Coba ${sale.attempts}/${SaleOutbox.maxSyncAttempts}', kWarning)
        : ('Menunggu', kTextMid);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                formatTime(waktu),
                style: TextStyle(
                  fontSize: 12,
                  color: kTextMid,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Gap(10),
              Expanded(
                child: Text(
                  formatRupiah(total),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: warna.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: warna,
                  ),
                ),
              ),
            ],
          ),
          const Gap(2),
          Text(
            ['$jumlahItem item', if (metode.isNotEmpty) metode].join(' · '),
            style: TextStyle(fontSize: 12, color: kTextMid),
          ),
          if ((sale.lastError ?? '').isNotEmpty &&
              (gagalPermanen || sale.attempts > 0))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                sale.lastError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: kDanger),
              ),
            ),
        ],
      ),
    );
  }
}

class _BarisInfo extends StatelessWidget {
  const _BarisInfo({required this.ikon, required this.teks, this.warna});

  final IconData ikon;
  final String teks;
  final Color? warna;

  @override
  Widget build(BuildContext context) {
    final w = warna ?? kTextMid;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(ikon, size: 16, color: w),
          const Gap(8),
          Expanded(
            child: Text(teks, style: TextStyle(fontSize: 12, color: w)),
          ),
        ],
      ),
    );
  }
}

/// Pembuka sheet pemulihan lewat navigator akar — dipakai app shell.
void bukaPemulihanLewat(GlobalKey<NavigatorState> navigatorKey, WidgetRef ref) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
  showDeadLetterRecoverySheet(ctx, ref);
}
