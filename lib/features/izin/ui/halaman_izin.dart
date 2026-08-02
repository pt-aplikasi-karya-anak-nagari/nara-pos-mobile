import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/permission_service.dart';
import '../gerbang_izin.dart';

/// Halaman pertama aplikasi: meminta seluruh izin sistem yang wajib, sebelum
/// login.
///
/// # KENAPA DI DEPAN, BUKAN SAAT DIBUTUHKAN
///
/// Pola "minta saat dipakai" gagal justru di saat yang paling mahal. Kasir
/// menekan Cetak dengan pelanggan berdiri di depannya, lalu dialog izin
/// Bluetooth baru muncul — pertama kali seumur hidup aplikasi itu, di tengah
/// antrean. Kalau ia salah tekan "Tolak", strukhya tak keluar dan tak ada
/// dialog kedua.
///
/// Meminta semuanya di muka memindahkan momen itu ke saat perangkat sedang
/// disiapkan, oleh orang yang memang sedang menyiapkannya.
///
/// # TIDAK ADA TOMBOL LEWATI
///
/// Ini permintaan yang disengaja: tanpa ketiganya, aplikasi tak bisa
/// menjalankan pekerjaan intinya. Tapi "tak bisa dilewati" TIDAK boleh berarti
/// "tak ada jalan keluar" — Android dan iOS berhenti menampilkan dialog setelah
/// penolakan permanen, jadi tanpa jalan ke Pengaturan halaman ini akan jadi
/// layar mati yang hanya bisa diperbaiki dengan memasang ulang aplikasi. Karena
/// itu status ditolakPermanen memunculkan tombol menuju Pengaturan, dan
/// izinnya diperiksa ulang setiap kali pengguna kembali ke aplikasi.
class HalamanIzin extends ConsumerStatefulWidget {
  const HalamanIzin({super.key});

  @override
  ConsumerState<HalamanIzin> createState() => _HalamanIzinState();
}

class _HalamanIzinState extends ConsumerState<HalamanIzin>
    with WidgetsBindingObserver {
  Map<IzinAplikasi, StatusIzin>? _status;
  bool _sedangMeminta = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _muat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Satu-satunya jalan keluar dari penolakan permanen adalah halaman
    // Pengaturan — yang berada DI LUAR aplikasi ini. Tanpa memeriksa ulang saat
    // kembali, pengguna yang baru saja menyalakan izinnya di Pengaturan
    // kembali ke halaman yang masih berkata izinnya belum ada.
    if (state == AppLifecycleState.resumed) _muat();
  }

  Future<void> _muat() async {
    final hasil = await ref.read(systemPermissionServiceProvider).periksaSemua();
    if (!mounted) return;
    setState(() => _status = hasil);
    await ref.read(gerbangIzinProvider.notifier).periksa();
  }

  Future<void> _mintaSemua() async {
    setState(() => _sedangMeminta = true);
    final svc = ref.read(systemPermissionServiceProvider);
    for (final izin in IzinAplikasi.values) {
      if (_status?[izin] == StatusIzin.diberikan) continue;
      // Berurutan, bukan serentak: dialog izin sistem hanya boleh satu dalam
      // satu waktu. Meminta ketiganya sekaligus membuat dua di antaranya
      // ditolak diam-diam tanpa pernah terlihat pengguna.
      await svc.minta(izin);
    }
    if (!mounted) return;
    setState(() => _sedangMeminta = false);
    await _muat();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final adaPermanen = status?.values.contains(StatusIzin.ditolakPermanen) ??
        false;
    final semuaOk =
        status != null && status.values.every((s) => s == StatusIzin.diberikan);

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // Aplikasi ini juga dipakai di tablet melintang. Tanpa batas lebar,
            // barisnya melar sampai teksnya sulit dibaca.
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: kPrimary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedShield01,
                            color: kPrimary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Izin yang dibutuhkan',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: kTextDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'NARA POS membutuhkan izin berikut untuk bisa '
                          'mencetak struk, memindai barcode, dan memberi tahu '
                          'kasir saat ada pesanan baru. Semuanya wajib.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: kTextMid,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (status == null)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else
                          for (final izin in IzinAplikasi.values) ...[
                            _BarisIzin(izin: izin, status: status[izin]!),
                            const SizedBox(height: 10),
                          ],
                        if (adaPermanen) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: kWarning.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: kWarning.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              'Sebagian izin ditolak permanen, jadi sistem '
                              'tidak akan menampilkan dialognya lagi. Nyalakan '
                              'lewat Pengaturan, lalu kembali ke sini.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: kTextMid,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          key: const ValueKey('izin-tombol-utama'),
                          onPressed: (_sedangMeminta || status == null)
                              ? null
                              : (adaPermanen
                                    ? () => ref
                                          .read(systemPermissionServiceProvider)
                                          .bukaPengaturan()
                                    : _mintaSemua),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _sedangMeminta
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  adaPermanen
                                      ? 'Buka Pengaturan'
                                      : 'Izinkan Semua',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                      // Tombol ini hanya muncul saat izinnya SUDAH lengkap.
                      // Router yang sebenarnya memindahkan halaman; ini ada
                      // supaya pengguna yang kembali dari Pengaturan punya
                      // sesuatu yang jelas untuk ditekan, bukan menunggu
                      // halaman berpindah sendiri.
                      if (semuaOk) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: TextButton(
                            key: const ValueKey('izin-lanjut'),
                            onPressed: () =>
                                ref.read(gerbangIzinProvider.notifier).periksa(),
                            child: Text(
                              'Lanjut',
                              style: TextStyle(
                                color: kPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarisIzin extends StatelessWidget {
  final IzinAplikasi izin;
  final StatusIzin status;
  const _BarisIzin({required this.izin, required this.status});

  IconAsset get _ikon => switch (izin) {
    IzinAplikasi.perangkatSekitar => AppIcons.bluetooth,
    IzinAplikasi.kamera => AppIcons.scan,
    IzinAplikasi.notifikasi => AppIcons.notification,
  };

  @override
  Widget build(BuildContext context) {
    final ok = status == StatusIzin.diberikan;
    final permanen = status == StatusIzin.ditolakPermanen;
    final warna = ok ? kSuccess : (permanen ? kDanger : kTextMid);

    return Container(
      key: ValueKey('izin-${izin.name}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ok ? kSuccess.withValues(alpha: 0.35) : kDivider,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: warna.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: HugeIcon(icon: _ikon, color: warna, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  izin.judul,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: kTextDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  izin.alasan,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: kTextMid,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          HugeIcon(
            icon: ok ? AppIcons.checkCircle : HugeIcons.strokeRoundedAlert02,
            color: warna,
            size: 20,
          ),
        ],
      ),
    );
  }
}
