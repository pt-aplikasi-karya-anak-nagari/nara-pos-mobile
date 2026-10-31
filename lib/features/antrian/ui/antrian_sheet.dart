import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/format.dart';
import '../../../core/outlet_scope.dart';
import '../../../shared/widgets/sheet_bawah.dart';
import '../data/antrian_service.dart';
import '../data/pemanggil_suara.dart';
import '../domain/antrian.dart';

/// Buka panel antrian.
Future<void> bukaPanelAntrian(BuildContext context) => tampilkanSheetBawah(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => const AntrianSheet(),
);

/// Panel antrian hari ini: nomor yang sedang dipanggil, total/menunggu/sudah
/// dipanggil, tombol panggil (dengan suara), dan daftar tunggu.
class AntrianSheet extends HookConsumerWidget {
  const AntrianSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ringkasanAntrianProvider);
    final suara = ref.read(pemanggilSuaraProvider);
    final sibuk = useState<String?>(null); // id yang sedang dipanggil / 'next'
    final suaraAktif = useState(suara.aktif);
    final kecepatan = useState(suara.kecepatan);

    Future<void> panggil({String? id}) async {
      final outletId = ref.read(activeOutletIdProvider);
      if (outletId == null || sibuk.value != null) return;
      sibuk.value = id ?? 'next';
      try {
        final api = ref.read(antrianServiceProvider);
        final it = id == null
            ? await api.panggilBerikutnya(outletId)
            : await api.panggil(outletId, id);
        ref.invalidate(ringkasanAntrianProvider);
        // Suara tak ditunggu: daftar langsung diperbarui selagi berbunyi.
        suara.panggil(it.nomor, ulang: it.dipanggilKali > 1);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: kDanger),
          );
        }
      } finally {
        sibuk.value = null;
      }
    }

    final r = async.value;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
        maxWidth: 720,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Gap(10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: kDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Antrian Hari Ini',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: kTextDark,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Muat ulang',
                    onPressed: () => ref.invalidate(ringkasanAntrianProvider),
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: async.hasError && r == null
                  ? _Galat(
                      pesan: '${async.error}',
                      onUlang: () => ref.invalidate(ringkasanAntrianProvider),
                    )
                  : r == null
                  ? const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        _SedangDipanggil(
                          item: r.sedangDipanggil,
                          sibuk: sibuk.value == r.sedangDipanggil?.id,
                          onUlang: r.sedangDipanggil == null
                              ? null
                              : () => panggil(id: r.sedangDipanggil!.id),
                        ),
                        const Gap(12),
                        Row(
                          children: [
                            _Angka(label: 'Total antrian', nilai: r.total),
                            const Gap(8),
                            _Angka(
                              label: 'Menunggu',
                              nilai: r.menunggu,
                              warna: r.menunggu > 0 ? kWarning : null,
                            ),
                            const Gap(8),
                            _Angka(
                              label: 'Sudah dipanggil',
                              nilai: r.dipanggil,
                              warna: kSuccess,
                            ),
                          ],
                        ),
                        const Gap(14),
                        SizedBox(
                          height: 56,
                          child: FilledButton.icon(
                            onPressed:
                                r.berikutnya == null || sibuk.value != null
                                ? null
                                : () => panggil(),
                            style: FilledButton.styleFrom(
                              backgroundColor: kPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: sibuk.value == 'next'
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.campaign_rounded),
                            label: Text(
                              r.berikutnya == null
                                  ? 'Tidak ada antrian menunggu'
                                  : 'Panggil berikutnya · ${r.berikutnya!.nomor}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        if (r.daftarMenunggu.isNotEmpty) ...[
                          const Gap(20),
                          _Judul('Menunggu (${r.menunggu})'),
                          const Gap(8),
                          for (final it in r.daftarMenunggu)
                            _BarisAntrian(
                              item: it,
                              sibuk: sibuk.value == it.id,
                              onPanggil: sibuk.value != null
                                  ? null
                                  : () => panggil(id: it.id),
                            ),
                        ],
                        if (r.riwayatPanggil.length > 1) ...[
                          const Gap(16),
                          _Judul('Baru dipanggil'),
                          const Gap(8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final it in r.riwayatPanggil.skip(1))
                                ActionChip(
                                  label: Text(
                                    it.nomor,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  avatar: const Icon(Icons.replay, size: 16),
                                  tooltip: 'Panggil ulang ${it.nomor}',
                                  onPressed: sibuk.value != null
                                      ? null
                                      : () => panggil(id: it.id),
                                ),
                            ],
                          ),
                        ],
                        const Gap(20),
                        _PengaturanSuara(
                          aktif: suaraAktif.value,
                          kecepatan: kecepatan.value,
                          onAktif: (v) {
                            suaraAktif.value = v;
                            suara.setAktif(v);
                          },
                          onKecepatan: (v) {
                            kecepatan.value = v;
                            suara.setKecepatan(v);
                          },
                          onUji: () => suara.panggil(
                            r.sedangDipanggil?.nomor ?? '001',
                            paksa: true,
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

class _SedangDipanggil extends StatelessWidget {
  const _SedangDipanggil({
    required this.item,
    required this.sibuk,
    required this.onUlang,
  });

  final ItemAntrian? item;
  final bool sibuk;
  final VoidCallback? onUlang;

  @override
  Widget build(BuildContext context) {
    final it = item;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B4FD8), Color(0xFF0EA5E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sedang dipanggil',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Semantics(
                  liveRegion: true,
                  label: it == null
                      ? 'Belum ada nomor yang dipanggil'
                      : 'Nomor antrian ${it.nomor} sedang dipanggil',
                  excludeSemantics: true,
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      it?.nomor ?? '—',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 56,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                  ),
                ),
                Text(
                  it == null
                      ? 'Belum ada nomor yang dipanggil hari ini'
                      : [
                          if (it.keterangan.isNotEmpty) it.keterangan,
                          if (it.dipanggilPada != null)
                            'pukul ${formatTime(it.dipanggilPada!)}',
                          if (it.dipanggilKali > 1)
                            'dipanggil ${it.dipanggilKali}×',
                        ].join(' · '),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
          if (onUlang != null)
            FilledButton.tonalIcon(
              onPressed: sibuk ? null : onUlang,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kPrimary,
              ),
              icon: const Icon(Icons.replay),
              label: const Text('Panggil ulang'),
            ),
        ],
      ),
    );
  }
}

class _Angka extends StatelessWidget {
  const _Angka({required this.label, required this.nilai, this.warna});

  final String label;
  final int nilai;
  final Color? warna;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kDivider),
        ),
        child: Column(
          children: [
            Text(
              '$nilai',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: warna ?? kTextDark,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: kTextMid),
            ),
          ],
        ),
      ),
    );
  }
}

class _Judul extends StatelessWidget {
  const _Judul(this.teks);
  final String teks;

  @override
  Widget build(BuildContext context) => Text(
    teks,
    style: TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 14,
      color: kTextDark,
    ),
  );
}

class _BarisAntrian extends StatelessWidget {
  const _BarisAntrian({
    required this.item,
    required this.sibuk,
    required this.onPanggil,
  });

  final ItemAntrian item;
  final bool sibuk;
  final VoidCallback? onPanggil;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kDivider),
      ),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 64),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              item.nomor,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.keterangan.isEmpty ? 'Pelanggan' : item.keterangan,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kTextDark,
                  ),
                ),
                if (item.dibuatPada != null)
                  Text(
                    'Masuk ${formatTime(item.dibuatPada!)}'
                    '${item.tipePesanan.isNotEmpty ? ' · ${item.tipePesanan}' : ''}',
                    style: TextStyle(fontSize: 11, color: kTextMid),
                  ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPanggil,
            icon: sibuk
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.campaign_outlined, size: 18),
            label: const Text('Panggil'),
          ),
        ],
      ),
    );
  }
}

class _PengaturanSuara extends StatelessWidget {
  const _PengaturanSuara({
    required this.aktif,
    required this.kecepatan,
    required this.onAktif,
    required this.onKecepatan,
    required this.onUji,
  });

  final bool aktif;
  final double kecepatan;
  final ValueChanged<bool> onAktif;
  final ValueChanged<double> onKecepatan;
  final VoidCallback onUji;

  @override
  Widget build(BuildContext context) {
    // Material (bukan Container berwarna): SwitchListTile menggambar efek
    // sentuhnya di Material terdekat.
    return Material(
      color: kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: kDivider),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 10, 10),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: aktif,
              onChanged: onAktif,
              title: const Text(
                'Suara panggilan',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Bunyikan bel & sebut nomornya di perangkat ini',
              ),
            ),
            Row(
              children: [
                Text(
                  'Kecepatan',
                  style: TextStyle(color: kTextMid, fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: kecepatan,
                    min: 0.3,
                    max: 0.6,
                    divisions: 6,
                    label: kecepatan < 0.4
                        ? 'Pelan'
                        : kecepatan > 0.5
                        ? 'Cepat'
                        : 'Normal',
                    onChanged: aktif ? onKecepatan : null,
                  ),
                ),
                TextButton.icon(
                  onPressed: onUji,
                  icon: const Icon(Icons.volume_up_outlined, size: 18),
                  label: const Text('Uji suara'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Galat extends StatelessWidget {
  const _Galat({required this.pesan, required this.onUlang});
  final String pesan;
  final VoidCallback onUlang;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Antrian belum bisa dimuat.\n$pesan',
          textAlign: TextAlign.center,
          style: TextStyle(color: kTextMid),
        ),
        const Gap(12),
        OutlinedButton(onPressed: onUlang, child: const Text('Coba lagi')),
      ],
    ),
  );
}
