part of 'payment_sheet.dart';

// Bagian pembantu sheet pembayaran: dialog PIN otorisasi dan widget kecil
// yang dipakai PaymentSheet. Dipisah dari payment_sheet.dart supaya berkas itu
// hanya memuat alur pembayarannya; isinya tidak diubah. Berkas `part` berbagi
// impor dan nama privat (_) dengan payment_sheet.dart.

/// B1c: dialog PIN otorisasi manajer saat diskon melampaui batas kasir
/// (`max_discount_percent`). Mengikuti pola dialog PIN void/refund (B1a): input
/// numeric obscure 4-6 digit dengan pesan error backend ("...melebihi batas...")
/// ditampilkan di atas. Mengembalikan PIN bila dikonfirmasi, atau null bila
/// dibatalkan.
Future<String?> _promptManagerPin(
  BuildContext context, {
  required String errorText,
}) async {
  final pinController = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final pin = pinController.text.trim();
        final pinValid = pin.length >= 4 && pin.length <= 6;
        return AlertDialog(
          title: Text(context.t('auth.title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kDanger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  errorText,
                  style: const TextStyle(
                    color: kDanger,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Gap(12),
              Text(context.t('auth.discount_over')),
              const Gap(12),
              TextField(
                controller: pinController,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setLocal(() {}),
                decoration: InputDecoration(
                  labelText: context.t('auth.pin'),
                  hintText: context.t('auth.pin_hint'),
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.t('common.cancel')),
            ),
            FilledButton(
              onPressed: pinValid ? () => Navigator.pop(ctx, pin) : null,
              child: Text(context.t('auth.submit')),
            ),
          ],
        );
      },
    ),
  );
  pinController.dispose();
  return result;
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isCopyable;

  const _InfoRow({
    required this.label,
    required this.value,
    this.isCopyable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: kTextMid)),
        Row(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: kTextDark,
              ),
            ),
            if (isCopyable) ...[
              const Gap(8),
              HugeIcon(icon: AppIcons.copy, color: kPrimary, size: 14),
            ],
          ],
        ),
      ],
    );
  }
}

class _TablePickerCard extends StatelessWidget {
  final PosTable? activeTable;
  const _TablePickerCard({required this.activeTable});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        tampilkanSheetBawah(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => const TableSelectorSheet(),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: activeTable != null ? kPrimary.withValues(alpha: 0.05) : kBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: activeTable != null ? kPrimary : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.table_restaurant,
              color: activeTable != null ? kPrimary : kTextMid,
              size: 20,
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activeTable != null
                        ? activeTable!.name
                        : context.t('pay.pick_table'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: activeTable != null ? kPrimary : kTextDark,
                    ),
                  ),
                  Text(
                    activeTable != null
                        ? context.tf('pay.table_seats', {
                            'group':
                                activeTable!.group?.name ??
                                context.t('pay.table'),
                            'n': activeTable!.capacity,
                          })
                        : context.t('pay.no_table'),
                    style: TextStyle(fontSize: 12, color: kTextMid),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: activeTable != null ? kPrimary : kTextLight,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetBreakdownRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _SheetBreakdownRow({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color ?? kTextMid,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: color ?? kTextDark,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

String _payFmtPct(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}

/// UI compact untuk pilih + preview foto bukti pembayaran.
///
/// Dipakai di kasir checkout (non-cash) supaya kasir bisa langsung
/// melampirkan struk transfer / hasil scan QRIS sebelum konfirmasi
/// pembayaran. Sifat opsional — checkout tetap bisa lanjut tanpa foto.
class _PaymentProofPicker extends StatelessWidget {
  final String? filePath;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onClear;
  const _PaymentProofPicker({
    required this.filePath,
    required this.uploading,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('pay.proof_title'),
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        const Gap(2),
        Text(
          context.t('pay.proof_sub'),
          style: TextStyle(fontSize: 11, color: kTextMid),
        ),
        const Gap(10),
        if (filePath != null)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kDivider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Image.file(
                  File(filePath!),
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
                if (uploading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.4),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        height: 28,
                        width: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: kDanger,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: uploading ? null : onClear,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: Text(context.t('pay.proof_upload')),
            style: OutlinedButton.styleFrom(
              foregroundColor: kPrimary,
              side: const BorderSide(color: kPrimary),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
      ],
    );
  }
}

// ── E5: helper badge tier pelanggan ──

/// Warna aksen per tier loyalty. Fallback ke primary untuk tier custom/Regular.
Color _tierColor(String level) {
  switch (level.toLowerCase()) {
    case 'platinum':
      return const Color(0xFF7C6FF0);
    case 'gold':
      return const Color(0xFFD69E2E);
    case 'silver':
      return const Color(0xFF718096);
    default:
      return kPrimary;
  }
}

/// Format pengali poin ringkas: 1.25 → "1.25", 1.5 → "1.5", 1.0 → "1".
String _fmtMult(double m) {
  var s = m.toStringAsFixed(2);
  while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Kartu QRIS di layar bayar.
///
/// # APA YANG BERUBAH
///
/// Sebelumnya kartu ini menggambar QRIS STATIS milik outlet apa adanya, dengan
/// nominal ditulis sebagai TEKS di atasnya. Pelanggan memindai, lalu harus
/// mengetik sendiri angka yang ia baca di layar — dan salah ketik satu digit
/// baru ketahuan saat rekonsiliasi kas, kalau ketahuan.
///
/// Sekarang nominalnya disuntikkan ke dalam payload QRIS-nya oleh server, jadi
/// yang terpindai sudah membawa angkanya.
///
/// # KENAPA ANGKA YANG DITAMPILKAN DATANG DARI SERVER
///
/// QRIS hanya membawa rupiah bulat. Total Rp11.000,40 jadi Rp11.000 di dalam
/// kode. Kalau kartu ini menampilkan totalnya sendiri, layar dan QR menyebut
/// dua angka berbeda — dan yang membayar tak punya cara tahu mana yang benar.
/// Karena itu yang ditampilkan adalah `amount` dari respons, bukan [nominal].
///
/// # KENAPA GAGALNYA TIDAK DISEMBUNYIKAN
///
/// Bila server tak terjangkau, kartu ini KEMBALI ke QRIS statis dan mengatakan
/// terus terang bahwa nominalnya harus diketik pelanggan. QRIS statis tetap
/// menerima uang — hanya kurang nyaman. Layar bayar yang kosong, atau QR statis
/// yang berpura-pura dinamis, jauh lebih mahal: yang pertama menghentikan
/// antrean, yang kedua membuat kasir mengira nominalnya sudah terkunci padahal
/// pelanggan bebas mengetik angka lain.
class KartuQris extends ConsumerWidget {
  final PaymentMethod metode;
  final double nominal;

  const KartuQris({super.key, required this.metode, required this.nominal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // id kosong → metode ini belum pernah sinkron ke server (mis. dibuat
    // offline), jadi tak ada yang bisa diminta. Langsung pakai yang statis.
    final id = metode.id;
    final dinamis = id.isEmpty
        ? null
        : ref.watch(qrisDinamisProvider(KunciQrisDinamis(id, nominal)));

    final data = dinamis?.asData?.value;
    final gagal = dinamis?.hasError ?? true;
    final memuat = dinamis?.isLoading ?? false;

    final payload = (data?['qr_data'] as String?) ?? metode.qrData!;
    final terkunci = data != null;
    final tampilNominal = (data?['amount'] as num?)?.toDouble() ?? nominal;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kDivider),
      ),
      child: Column(
        children: [
          Text(
            terkunci
                ? context.t('pay.qris_scan_filled')
                : context.t('pay.qris_scan'),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: kTextMid,
            ),
            textAlign: TextAlign.center,
          ),
          const Gap(8),
          Text(
            formatRupiah(tampilNominal),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: kPrimary,
            ),
          ),
          const Gap(16),
          Stack(
            alignment: Alignment.center,
            children: [
              // QR-nya tetap tergambar selama memuat, hanya diredupkan. Kalau
              // ia hilang lalu muncul lagi, kasir yang sudah mengarahkan ponsel
              // pelanggan ke layar harus mengulang.
              Opacity(
                opacity: memuat ? 0.25 : 1,
                child: BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: payload,
                  width: 180,
                  height: 180,
                ),
              ),
              if (memuat)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
            ],
          ),
          if (gagal && !memuat) ...[
            const Gap(12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: kWarning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HugeIcon(
                    icon: AppIcons.alertCircle,
                    size: 14,
                    color: kWarning,
                  ),
                  const Gap(6),
                  Flexible(
                    child: Text(
                      context.tf('pay.qris_manual', {
                        'amount': formatRupiah(nominal),
                      }),
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: kWarning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Jatuh tempo tagihan Bayar Nanti. Kosong = hari ini. Pemilik melihat
/// tagihan yang lewat jatuh tempo di halaman Piutang & mendapat pengingat.
class _PilihJatuhTempo extends StatelessWidget {
  const _PilihJatuhTempo({required this.nilai, required this.onUbah});

  final DateTime? nilai;
  final ValueChanged<DateTime?> onUbah;

  @override
  Widget build(BuildContext context) {
    final label = nilai == null
        ? context.t('pay.today')
        : formatTanggalJatuhTempo(nilai!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kDivider),
      ),
      child: Row(
        children: [
          Icon(Icons.event_outlined, size: 20, color: kTextMid),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('pay.due'),
                  style: TextStyle(fontSize: 12, color: kTextMid),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kTextDark,
                  ),
                ),
              ],
            ),
          ),
          if (nilai != null)
            IconButton(
              tooltip: context.t('pay.due_reset'),
              onPressed: () => onUbah(null),
              icon: const Icon(Icons.close, size: 18),
            ),
          TextButton(
            onPressed: () async {
              final kini = DateTime.now();
              final hari = DateTime(kini.year, kini.month, kini.day);
              final dipilih = await showDatePicker(
                context: context,
                initialDate: nilai ?? hari,
                firstDate: hari,
                // Sama dengan batas server (piutang.MaksHariJatuhTempo).
                lastDate: hari.add(const Duration(days: 365)),
                helpText: context.t('pay.due_help'),
              );
              if (dipilih != null) onUbah(dipilih);
            },
            child: Text(context.t('common.change')),
          ),
        ],
      ),
    );
  }
}
