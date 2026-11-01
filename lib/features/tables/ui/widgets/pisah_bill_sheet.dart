import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';

import '../../../../app/theme.dart';
import '../../../../core/format.dart';
import '../../../transactions/domain/sale.dart';

/// Perkiraan tagihan untuk item yang dipilih: porsi total tagihan sebanding
/// subtotal barisnya (pajak, service, dan promo ikut terbagi). Angka pastinya
/// dihitung server — ini hanya tampilan sebelum kasir menekan tombol.
///
/// Fungsi MURNI supaya bisa diuji tanpa widget.
double perkiraanPisah(Sale sale, Map<String, int> pilihan) {
  double semua = 0, dipilih = 0;
  for (final it in sale.items) {
    semua += it.price * it.qty;
    final n = pilihan[it.id] ?? 0;
    if (n > 0 && it.qty > 0) dipilih += it.price * n.clamp(0, it.qty);
  }
  if (semua <= 0) return 0;
  return (sale.total * dipilih / semua).roundToDouble();
}

/// Alasan pilihan belum bisa dipisah, atau null bila siap.
String? alasanTakBisaPisah(Sale sale, Map<String, int> pilihan) {
  final unitDipilih = pilihan.values.fold<int>(
    0,
    (s, n) => s + (n > 0 ? n : 0),
  );
  if (unitDipilih == 0) return 'Pilih item yang dibayar terpisah';
  final unitSemua = sale.items.fold<int>(0, (s, it) => s + it.qty);
  if (unitDipilih >= unitSemua) {
    return 'Untuk membayar semuanya, pakai tombol Bayar';
  }
  return null;
}

/// Lembar pilih item untuk split bill. Mengembalikan id baris → jumlah yang
/// dipisah, atau null bila dibatalkan.
class PisahBillSheet extends HookWidget {
  final Sale sale;
  const PisahBillSheet({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    final pilihan = useState<Map<String, int>>({});
    final alasan = alasanTakBisaPisah(sale, pilihan.value);
    final perkiraan = perkiraanPisah(sale, pilihan.value);

    void atur(String id, int n) {
      pilihan.value = {...pilihan.value, id: n};
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Gap(14),
            const Text(
              'Pisah Bill',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const Gap(2),
            Text(
              'Pilih item yang dibayar terpisah. Sisanya tetap di tagihan '
              '${sale.invoiceId}.',
              style: TextStyle(fontSize: 12, color: kTextMid),
            ),
            const Gap(12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final it in sale.items)
                    _BarisPilih(
                      nama: it.variant.isEmpty
                          ? it.productName
                          : '${it.productName} (${it.variant})',
                      keterangan: it.bundleItems.isNotEmpty
                          ? 'Isi: ${it.bundleLabel}'
                          : it.modifiersLabel,
                      harga: it.price,
                      maks: it.qty,
                      nilai: pilihan.value[it.id] ?? 0,
                      onUbah: (n) => atur(it.id, n),
                    ),
                ],
              ),
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    alasan ?? 'Perkiraan tagihan terpisah',
                    style: TextStyle(
                      fontSize: 12,
                      color: alasan == null ? kTextMid : kWarning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  formatRupiah(perkiraan),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: kPrimary,
                  ),
                ),
              ],
            ),
            const Gap(12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: alasan != null
                    ? null
                    : () => Navigator.pop(context, {
                        for (final e in pilihan.value.entries)
                          if (e.value > 0) e.key: e.value,
                      }),
                icon: const Icon(Icons.call_split, size: 18),
                label: const Text(
                  'Pisah & Bayar',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarisPilih extends StatelessWidget {
  final String nama;
  final String keterangan;
  final double harga;
  final int maks;
  final int nilai;
  final ValueChanged<int> onUbah;

  const _BarisPilih({
    required this.nama,
    required this.keterangan,
    required this.harga,
    required this.maks,
    required this.nilai,
    required this.onUbah,
  });

  @override
  Widget build(BuildContext context) {
    final aktif = nilai > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: aktif ? kPrimary.withValues(alpha: 0.06) : kBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: aktif ? kPrimary : kDivider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nama,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (keterangan.isNotEmpty)
                  Text(
                    keterangan,
                    style: TextStyle(fontSize: 11, color: kTextMid),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  '${formatRupiah(harga)} · dipesan $maks',
                  style: TextStyle(fontSize: 11, color: kTextMid),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Kurangi',
            onPressed: nilai > 0 ? () => onUbah(nilai - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$nilai',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          IconButton(
            tooltip: 'Tambah',
            onPressed: nilai < maks ? () => onUbah(nilai + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
            color: kPrimary,
          ),
        ],
      ),
    );
  }
}
