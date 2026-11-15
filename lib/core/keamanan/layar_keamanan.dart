import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../app/theme.dart';
import 'integritas_perangkat.dart';

/// Menutup seluruh aplikasi bila perangkat/aplikasi tidak lolos pemeriksaan
/// integritas (lihat [keputusanIntegritas]). Antrian transaksi offline tidak
/// dibuang — tetap tersimpan dan terkirim setelah aplikasi dibuka di
/// perangkat yang aman.
class LayarPerangkatTidakAman extends StatelessWidget {
  final List<AlasanTolak> alasan;
  const LayarPerangkatTidakAman({super.key, required this.alasan});

  static String teks(AlasanTolak a) => switch (a) {
    AlasanTolak.root =>
      'Perangkat ini di-root / di-jailbreak, sehingga data kasir dan akun '
          'bisa dibaca atau diubah aplikasi lain.',
    AlasanTolak.hook =>
      'Terdeteksi alat penyadap atau pengubah aplikasi (mis. Frida, Xposed).',
    AlasanTolak.debugger =>
      'Aplikasi sedang disambungkan ke debugger.',
    AlasanTolak.apkDiubah =>
      'Aplikasi ini bukan versi resmi NARA — sudah diubah atau dipasang dari '
          'sumber tidak resmi.',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('layar-perangkat-tidak-aman'),
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: kDanger.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.gpp_bad_rounded, size: 36, color: kDanger),
                  ),
                  const Gap(20),
                  Text(
                    'Perangkat tidak aman',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: kTextDark,
                    ),
                  ),
                  const Gap(10),
                  Text(
                    'Demi keamanan transaksi dan akun Anda, NARA POS tidak bisa '
                    'dipakai di perangkat ini.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.5, color: kTextMid),
                  ),
                  const Gap(16),
                  for (final a in alasan)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: kCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kDivider),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded, color: kDanger),
                            const Gap(10),
                            Expanded(
                              child: Text(
                                teks(a),
                                style: TextStyle(fontSize: 13, color: kTextDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Gap(8),
                  Text(
                    'Transaksi yang tersimpan di perangkat ini tidak dihapus. '
                    'Pasang NARA POS resmi di perangkat lain, atau hubungi '
                    'dukungan NARA.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, height: 1.5, color: kTextMid),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bungkus halaman yang menampilkan password / PIN: selama halaman ini
/// terbuka, layar tak bisa di-screenshot atau direkam (Android).
class LayarRahasia extends StatefulWidget {
  final Widget child;
  const LayarRahasia({super.key, required this.child});

  @override
  State<LayarRahasia> createState() => _LayarRahasiaState();
}

class _LayarRahasiaState extends State<LayarRahasia> {
  // Beberapa halaman rahasia bisa bertumpuk; lepas FLAG_SECURE hanya saat
  // halaman terakhir ditutup.
  static int _aktif = 0;

  @override
  void initState() {
    super.initState();
    if (_aktif++ == 0) aturLayarAman(true);
  }

  @override
  void dispose() {
    if (--_aktif == 0) aturLayarAman(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
