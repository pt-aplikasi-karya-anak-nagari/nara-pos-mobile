import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/theme.dart';
import '../../settings/data/kelola_tarif_pajak.dart';

/// Pilihan tarif pajak sebuah produk di formulir produk (pajak multi-tarif).
///
/// Tidak tampil sama sekali bila outlet belum punya tarif tambahan — produk
/// otomatis memakai tarif utama, seperti sebelumnya. Tarif nonaktif tidak
/// ditawarkan, kecuali sedang dipakai produk ini (supaya pilihannya tetap
/// terlihat dan bisa diganti).
class PilihTarifPajak extends ConsumerWidget {
  const PilihTarifPajak({
    super.key,
    required this.outletId,
    required this.nilai,
    required this.onUbah,
  });

  final String outletId;

  /// ID tarif terpilih; null = tarif utama outlet.
  final String? nilai;
  final ValueChanged<String?> onUbah;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daftar = ref.watch(daftarTarifPajakProvider(outletId)).value;
    if (daftar == null) return const SizedBox.shrink();
    final pilihan = daftar.where((t) => t.aktif || t.id == nilai).toList();
    // Tarif terpilih tidak ada di outlet ini (outlet produk diganti, atau
    // tarifnya sudah dihapus) → kembali ke tarif utama, supaya formulir tidak
    // mengirim ID yang pasti ditolak server.
    if (nilai != null && !daftar.any((t) => t.id == nilai)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onUbah(null));
    }
    if (pilihan.isEmpty) return const SizedBox.shrink();
    final terpilih = pilihan.any((t) => t.id == nilai) ? nilai : null;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: DropdownButtonFormField<String?>(
          key: ValueKey('pilih-tarif-pajak-$outletId-$terpilih'),
          initialValue: terpilih,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Tarif pajak',
            helperText: 'Tarif utama mengikuti Pengaturan Pajak outlet.',
            helperStyle: TextStyle(fontSize: 11, color: kTextMid),
            border: InputBorder.none,
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Tarif utama outlet'),
            ),
            for (final t in pilihan)
              DropdownMenuItem<String?>(
                value: t.id,
                child: Text(t.aktif ? t.label : '${t.label} (nonaktif)'),
              ),
          ],
          onChanged: onUbah,
        ),
      ),
    );
  }
}
