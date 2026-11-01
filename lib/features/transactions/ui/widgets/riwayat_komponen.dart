import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../../../app/theme.dart';
import '../../../../core/format.dart';
import '../../data/transaction_repository.dart';
import '../../domain/sale.dart';

// ── Logika murni (diuji di test/riwayat_komponen_test.dart) ─────────────

/// Judul kartu transaksi: nama pelanggan → nomor antrian → "Pelanggan umum".
/// Nomor invoice sengaja tidak dipakai: panjang, terpotong di ponsel, dan
/// tak pernah dipakai kasir untuk mengenali pesanan. Ia ada di halaman detail.
String judulTransaksi(Sale s) {
  final nama = s.customerName.trim();
  if (nama.isNotEmpty) return nama;
  final antrian = s.nomorAntrian;
  if (antrian != null) return 'Antrian $antrian';
  return 'Pelanggan umum';
}

/// "2× Kopi Susu, 1× Roti" — maksimal [maks] baris, sisanya "+N lainnya".
String ringkasItem(Sale s, {int maks = 2}) {
  if (s.items.isEmpty) return '';
  final teks = s.items
      .take(maks)
      .map((it) => '${it.qty}× ${it.productName}')
      .join(', ');
  final sisa = s.items.length - maks;
  return sisa > 0 ? '$teks +$sisa lainnya' : teks;
}

/// Status transaksi untuk lencana kartu.
({String label, Color warna}) statusTransaksi(Sale s) {
  if (s.gagalTerkirim) return (label: 'Gagal terkirim', warna: kDanger);
  if (s.pendingSync) return (label: 'Belum terkirim', warna: kWarning);
  if (s.isRefunded) return (label: 'Diretur', warna: kDanger);
  if (s.isPartiallyRefunded) return (label: 'Retur sebagian', warna: kWarning);
  if (s.isCancelled) return (label: 'Dibatalkan', warna: kTextLightStatic);
  if (s.isUnpaid) return (label: 'Belum bayar', warna: kWarning);
  return (label: 'Lunas', warna: kSuccess);
}

/// Abu-abu netral yang sama di mode terang & gelap (untuk lencana batal).
const kTextLightStatic = Color(0xFF94A3B8);

/// Label kelompok tanggal: "Hari ini", "Kemarin", atau "Sab, 31 Okt 2026".
String labelTanggalRiwayat(DateTime waktu, {DateTime? sekarang}) {
  final now = (sekarang ?? DateTime.now()).toLocal();
  final t = waktu.toLocal();
  final hariIni = DateTime(now.year, now.month, now.day);
  final hari = DateTime(t.year, t.month, t.day);
  final selisih = hariIni.difference(hari).inDays;
  if (selisih == 0) return 'Hari ini';
  if (selisih == 1) return 'Kemarin';
  const namaHari = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  const namaBulan = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  return '${namaHari[t.weekday - 1]}, ${t.day} ${namaBulan[t.month - 1]} ${t.year}';
}

/// True bila [a] dan [b] jatuh pada hari kalender lokal yang sama.
bool hariSama(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

// ── Widget ──────────────────────────────────────────────────────────────

/// Label kelompok tanggal di atas kartu pertama tiap hari.
class LabelTanggalRiwayat extends StatelessWidget {
  final String label;
  const LabelTanggalRiwayat(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: kTextMid,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Ringkasan omzet periode yang sedang dilihat (hari ini / rentang filter).
class KartuRingkasanRiwayat extends StatelessWidget {
  final String periode;
  final RingkasanRiwayat ringkasan;
  const KartuRingkasanRiwayat({
    super.key,
    required this.periode,
    required this.ringkasan,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Omzet $periode',
            style: TextStyle(fontSize: 12, color: kTextMid),
          ),
          const Gap(2),
          Text(
            formatRupiah(ringkasan.omzet),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: kTextDark,
              letterSpacing: -0.3,
            ),
          ),
          const Gap(12),
          Row(
            children: [
              _Angka(label: 'Transaksi', nilai: '${ringkasan.jumlah}'),
              _Angka(
                label: 'Rata-rata',
                nilai: formatRupiah(ringkasan.rataRata),
              ),
              _Angka(
                label: 'Belum bayar',
                nilai: '${ringkasan.belumBayar}',
                warna: ringkasan.belumBayar > 0 ? kWarning : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Angka extends StatelessWidget {
  final String label;
  final String nilai;
  final Color? warna;
  const _Angka({required this.label, required this.nilai, this.warna});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nilai,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: warna ?? kTextDark,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 11, color: kTextMid)),
        ],
      ),
    );
  }
}

/// Kartu satu transaksi di riwayat.
///
///   [antrian]  Pelanggan / Antrian 009            Rp 13.200
///              2× Kopi Susu, 1× Roti               [Lunas]
///              10:31 · Takeaway · Tunai
class KartuTransaksi extends StatelessWidget {
  final Sale sale;
  final bool selected;
  final VoidCallback onTap;
  const KartuTransaksi({
    super.key,
    required this.sale,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = statusTransaksi(sale);
    final items = ringkasItem(sale);
    final antrian = sale.nomorAntrian;
    final detail = <String>[
      formatTime(sale.createdAt),
      if (sale.orderType.trim().isNotEmpty) sale.orderType.trim(),
      if (sale.isDineIn && sale.tableDisplay != null) sale.tableDisplay!,
      if (sale.paymentMethod.trim().isNotEmpty) sale.paymentMethod.trim(),
    ].join(' · ');
    final redup = sale.isCancelled;

    return Material(
      color: selected ? kPrimary.withValues(alpha: 0.06) : kCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? kPrimary : kDivider.withValues(alpha: 0.6),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Lencana(antrian: antrian, sale: sale),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            judulTransaksi(sale),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: redup ? kTextMid : kTextDark,
                            ),
                          ),
                        ),
                        const Gap(8),
                        Text(
                          formatRupiah(sale.total),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: redup ? kTextMid : kTextDark,
                            decoration: redup
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const Gap(3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            items.isEmpty ? detail : items,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: kTextMid),
                          ),
                        ),
                        const Gap(8),
                        _Status(label: status.label, warna: status.warna),
                      ],
                    ),
                    if (items.isNotEmpty) ...[
                      const Gap(3),
                      Row(
                        children: [
                          if (sale.isFromMenuQr) ...[
                            Icon(Icons.qr_code_2, size: 13, color: kPrimary),
                            const Gap(3),
                          ],
                          Expanded(
                            child: Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: kTextLight),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kotak kiri: nomor antrian (pengenal pesanan yang dipakai kasir), atau
/// ikon struk bila tak ada nomor.
class _Lencana extends StatelessWidget {
  final String? antrian;
  final Sale sale;
  const _Lencana({required this.antrian, required this.sale});

  @override
  Widget build(BuildContext context) {
    final warna = sale.pendingSync
        ? (sale.gagalTerkirim ? kDanger : kWarning)
        : kPrimary;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: antrian != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'NO',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: warna.withValues(alpha: 0.7),
                    letterSpacing: 0.6,
                    height: 1,
                  ),
                ),
                const Gap(2),
                FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Text(
                      antrian!,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: warna,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Icon(
              sale.pendingSync
                  ? Icons.cloud_upload_outlined
                  : Icons.receipt_long_outlined,
              size: 20,
              color: warna,
            ),
    );
  }
}

class _Status extends StatelessWidget {
  final String label;
  final Color warna;
  const _Status({required this.label, required this.warna});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: warna,
        ),
      ),
    );
  }
}
