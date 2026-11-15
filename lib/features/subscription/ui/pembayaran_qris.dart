import 'dart:async';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/format.dart';
import '../../billing/data/billing_repository.dart';

/// Layar bayar langganan lewat QRIS (Xendit): kode QR, sisa waktu, dan
/// PEMERIKSAAN STATUS SENDIRI. Begitu Pemilik membayar dari aplikasi bank /
/// e-wallet, server dilunasi lewat webhook dan layar ini memanggil [onLunas]
/// tanpa perlu ditekan apa pun.
class PembayaranQris extends ConsumerStatefulWidget {
  const PembayaranQris({
    super.key,
    required this.outletId,
    required this.hasil,
    required this.onLunas,
    required this.onBuatUlang,
    this.membuatUlang = false,
    this.pemeriksa,
    this.jam,
  });

  final String outletId;
  final BillingCheckoutResult hasil;

  /// Invoice sudah lunas & langganan aktif.
  final VoidCallback onLunas;

  /// Minta kode QR baru untuk tagihan yang sama (kode lama kedaluwarsa).
  final VoidCallback onBuatUlang;
  final bool membuatUlang;

  /// Untuk tes: pengganti panggilan ke server.
  final Future<BillingCheckoutResult> Function()? pemeriksa;

  /// Untuk tes: sumber waktu.
  final DateTime Function()? jam;

  /// Jarak antar pengecekan status. Server sendiri membatasi pertanyaan ke
  /// Xendit, jadi lebih rapat dari ini tidak mempercepat apa pun.
  static const jedaCek = Duration(seconds: 5);

  @override
  ConsumerState<PembayaranQris> createState() => _PembayaranQrisState();
}

class _PembayaranQrisState extends ConsumerState<PembayaranQris>
    with WidgetsBindingObserver {
  late BillingCheckoutResult _hasil = widget.hasil;
  Timer? _detak;
  Timer? _polling;
  bool _memeriksa = false;
  bool _manual = false;
  bool _selesai = false;
  String? _galat;

  DateTime get _kini => (widget.jam ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Hitung mundur.
    _detak = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _polling = Timer.periodic(PembayaranQris.jedaCek, (_) => _periksa());
  }

  @override
  void didUpdateWidget(covariant PembayaranQris lama) {
    super.didUpdateWidget(lama);
    // Induk memberi hasil baru (mis. setelah "Buat kode QR baru").
    if (!identical(lama.hasil, widget.hasil)) _hasil = widget.hasil;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pemilik biasanya pindah ke aplikasi bank lalu kembali ke sini: periksa
    // seketika, jangan menunggu detak polling berikutnya.
    if (state == AppLifecycleState.resumed) _periksa();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detak?.cancel();
    _polling?.cancel();
    super.dispose();
  }

  Future<void> _periksa({bool manual = false}) async {
    if (_memeriksa || _selesai || !mounted) return;
    _memeriksa = true;
    if (manual) setState(() => _manual = true);
    try {
      final baru = widget.pemeriksa != null
          ? await widget.pemeriksa!()
          : await ref
                .read(billingRepositoryProvider)
                .cekPembayaran(widget.outletId, _hasil.invoiceId);
      if (!mounted) return;
      setState(() {
        _hasil = baru;
        _galat = null;
      });
      if (baru.lunas) {
        _selesai = true;
        _polling?.cancel();
        _detak?.cancel();
        widget.onLunas();
      }
    } catch (e) {
      // Gagal sesekali (sinyal) tidak ditampilkan saat polling otomatis;
      // percobaan berikutnya menyusul. Hanya tombol manual yang melapor.
      if (manual && mounted) {
        setState(() => _galat = e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      _memeriksa = false;
      if (manual && mounted) setState(() => _manual = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pi = _hasil.paymentInstruction;
    final sisa = sisaWaktuQris(pi?.expiresAt, _kini);
    final adaQr = (pi?.qrString ?? '').isNotEmpty;

    if (!adaQr || sisa.habis) return _kedaluwarsa();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Pindai dengan aplikasi bank atau e-wallet',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: kTextDark,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const Gap(12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kDivider),
          ),
          child: BarcodeWidget(
            barcode: Barcode.qrCode(),
            data: pi!.qrString,
            width: 220,
            height: 220,
          ),
        ),
        const Gap(12),
        Text(
          'Total pembayaran',
          style: TextStyle(color: kTextMid, fontSize: 12),
        ),
        Text(
          formatRupiah(_hasil.amountIdr),
          style: TextStyle(
            color: kTextDark,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const Gap(4),
        Text(
          'Berlaku ${sisa.teks} lagi',
          style: TextStyle(
            color: sisa.mendesak ? kDanger : kTextMid,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const Gap(10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const Gap(8),
            Flexible(
              child: Text(
                'Menunggu pembayaran — layar ini memperbarui sendiri',
                style: TextStyle(color: kTextMid, fontSize: 12),
              ),
            ),
          ],
        ),
        const Gap(8),
        Text(
          'Nominal sudah tertera di kode QR. Langganan aktif otomatis beberapa '
          'detik setelah pembayaran berhasil; tidak perlu mengunggah bukti.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kTextMid, fontSize: 11, height: 1.4),
        ),
        _tombolPeriksa(),
      ],
    );
  }

  Widget _kedaluwarsa() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('⌛', style: TextStyle(fontSize: 40)),
        const Gap(8),
        Text(
          'Kode QR sudah kedaluwarsa',
          style: TextStyle(
            color: kTextDark,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        const Gap(6),
        Text(
          'Belum ada pembayaran yang masuk untuk kode ini. Buat kode baru '
          'untuk tagihan yang sama — nomor invoice tidak berubah.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kTextMid, fontSize: 13, height: 1.4),
        ),
        const Gap(14),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: widget.membuatUlang ? null : widget.onBuatUlang,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              widget.membuatUlang ? 'Membuat kode…' : 'Buat kode QR baru',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        _tombolPeriksa(),
      ],
    );
  }

  Widget _tombolPeriksa() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: _manual ? null : () => _periksa(manual: true),
          child: Text(
            _manual ? 'Memeriksa…' : 'Saya sudah membayar — periksa status',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        if (_galat != null)
          Text(
            _galat!,
            textAlign: TextAlign.center,
            style: TextStyle(color: kDanger, fontSize: 12),
          ),
      ],
    );
  }
}
