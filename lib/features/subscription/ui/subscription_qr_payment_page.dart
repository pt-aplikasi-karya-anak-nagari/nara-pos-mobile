import 'dart:async';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/format.dart';
import '../../billing/data/billing_repository.dart';
import '../data/subscription_repository.dart';

/// Halaman pembayaran QRIS in-app (Xendit Payments API v3).
///
/// Menampilkan QR dari Payment Request lalu polling status invoice tiap
/// beberapa detik sampai final (paid/failed/expired). Saat paid, langganan
/// otomatis aktif (backend) dan provider langganan/billing di-invalidate.
class SubscriptionQrPaymentPage extends ConsumerStatefulWidget {
  final String invoiceId;
  final String invoiceNo;
  final int amountIdr;
  final String qrString;
  final String? planName;

  const SubscriptionQrPaymentPage({
    super.key,
    required this.invoiceId,
    required this.invoiceNo,
    required this.amountIdr,
    required this.qrString,
    this.planName,
  });

  @override
  ConsumerState<SubscriptionQrPaymentPage> createState() =>
      _SubscriptionQrPaymentPageState();
}

class _SubscriptionQrPaymentPageState
    extends ConsumerState<SubscriptionQrPaymentPage> {
  Timer? _timer;
  String _status = 'pending';
  bool _checking = false;
  int _attempts = 0;

  // ~10 menit pada interval 4 detik. Setelah itu polling berhenti; owner masih
  // bisa tekan "Cek Status" manual.
  static const int _maxAttempts = 150;
  static const Duration _interval = Duration(seconds: 4);

  bool get _isFinal => _status != 'pending' && _status != 'unpaid';

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_interval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll({bool manual = false}) async {
    if (_checking || _isFinal) return;
    if (!manual && _attempts >= _maxAttempts) {
      _timer?.cancel();
      return;
    }
    setState(() => _checking = true);
    _attempts++;
    try {
      final updated = await ref
          .read(billingRepositoryProvider)
          .syncInvoice(widget.invoiceId);
      if (!mounted) return;
      if (updated.status != 'pending' && updated.status != 'unpaid') {
        _timer?.cancel();
        setState(() => _status = updated.status);
        // Status final → refresh langganan & riwayat tagihan.
        ref.invalidate(activeOutletSubscriptionProvider);
        ref.invalidate(billingInvoicesProvider);
      }
    } catch (_) {
      // Error sync tidak fatal — coba lagi di tick berikutnya.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paid = _status == 'paid';
    final failed =
        _status == 'failed' || _status == 'expired' || _status == 'void';

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Pembayaran QRIS'),
        backgroundColor: kCard,
        foregroundColor: kTextDark,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: paid
                ? _ResultView(
                    color: kSuccess,
                    icon: Icons.check_circle_rounded,
                    title: 'Pembayaran Berhasil',
                    message: widget.planName != null
                        ? 'Langganan ${widget.planName} kamu sudah aktif. Terima kasih!'
                        : 'Langganan kamu sudah aktif. Terima kasih!',
                    primaryLabel: 'Selesai',
                    onPrimary: () => Navigator.of(context).pop(true),
                  )
                : failed
                    ? _ResultView(
                        color: kDanger,
                        icon: Icons.cancel_rounded,
                        title: 'Pembayaran Gagal',
                        message:
                            'Pembayaran tidak selesai atau kedaluwarsa. Tidak ada biaya ditagihkan — silakan buat invoice baru untuk mencoba lagi.',
                        primaryLabel: 'Tutup',
                        onPrimary: () => Navigator.of(context).pop(false),
                      )
                    : _buildQrView(),
          ),
        ),
      ),
    );
  }

  Widget _buildQrView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kDivider),
          ),
          child: BarcodeWidget(
            barcode: Barcode.qrCode(),
            data: widget.qrString,
            width: 240,
            height: 240,
            backgroundColor: Colors.white,
            color: Colors.black,
          ),
        ),
        const Gap(20),
        Text(
          formatRupiah(widget.amountIdr),
          style: TextStyle(
            color: kTextDark,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const Gap(2),
        Text(
          widget.invoiceNo,
          style: TextStyle(color: kTextMid, fontSize: 12),
        ),
        const Gap(16),
        Text(
          'Scan QR ini pakai aplikasi bank / e-wallet apa pun yang mendukung '
          'QRIS (GoPay, OVO, DANA, ShopeePay, mobile banking). Langganan aktif '
          'otomatis setelah pembayaran terbaca.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kTextMid, fontSize: 13, height: 1.4),
        ),
        const Gap(20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: kPrimary.withValues(alpha: _checking ? 1 : 0.4),
              ),
            ),
            const Gap(8),
            Text(
              _checking ? 'Mengecek pembayaran…' : 'Menunggu pembayaran…',
              style: TextStyle(color: kTextMid, fontSize: 12),
            ),
          ],
        ),
        const Gap(20),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            onPressed: _checking ? null : () => _poll(manual: true),
            style: OutlinedButton.styleFrom(
              foregroundColor: kPrimary,
              side: BorderSide(color: kPrimary.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Cek Status Pembayaran'),
          ),
        ),
        const Gap(8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Tutup', style: TextStyle(color: kTextMid)),
        ),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;

  const _ResultView({
    required this.color,
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 48),
        ),
        const Gap(18),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const Gap(8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: kTextMid, fontSize: 14, height: 1.45),
        ),
        const Gap(24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: onPrimary,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(primaryLabel),
          ),
        ),
      ],
    );
  }
}
