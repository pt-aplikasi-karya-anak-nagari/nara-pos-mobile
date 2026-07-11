import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../app/theme.dart';
import '../../subscription/data/subscription_repository.dart';
import '../../subscription/ui/subscription_qr_payment_page.dart';
import '../../../core/app_icons.dart';
import '../../../core/format.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/responsive.dart';
import '../data/billing_repository.dart';
import '../domain/billing_invoice.dart';

class BillingHistoryPage extends ConsumerWidget {
  const BillingHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(billingInvoicesProvider);
    final isTablet = context.isTablet;

    return Scaffold(
      backgroundColor: kBg,
      appBar: isTablet
          ? null
          : AppBar(
              backgroundColor: kCard,
              elevation: 0,
              iconTheme: IconThemeData(color: kTextDark),
              title: Text(
                'Billing History',
                style: TextStyle(color: kTextDark, fontWeight: FontWeight.w800),
              ),
            ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(billingInvoicesProvider);
            await ref.read(billingInvoicesProvider.future);
          },
          child: invoicesAsync.when(
            loading: () => const _LoadingList(),
            error: (error, _) => _ErrorState(message: error.toString()),
            data: (invoices) {
              if (invoices.isEmpty) return const _EmptyState();
              return ListView.separated(
                padding: EdgeInsets.all(isTablet ? 24 : 16),
                itemCount: invoices.length + 1,
                separatorBuilder: (_, index) =>
                    index == 0 ? const Gap(16) : const Gap(12),
                itemBuilder: (context, index) {
                  if (index == 0) return _Header(invoices: invoices);
                  return _InvoiceCard(invoice: invoices[index - 1]);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final List<BillingInvoice> invoices;

  const _Header({required this.invoices});

  @override
  Widget build(BuildContext context) {
    final totalPaid = invoices
        .where((invoice) => invoice.isPaid)
        .fold<int>(0, (sum, invoice) => sum + invoice.amountIdr);
    final proofCount = invoices
        .where((invoice) => (invoice.paymentProofUrl ?? '').isNotEmpty)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Riwayat pembayaran',
          style: TextStyle(
            color: kTextDark,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
        const Gap(6),
        Text(
          'Invoice subscription, tanggal bayar, bukti bayar, dan nominal snapshot.',
          style: TextStyle(color: kTextMid, height: 1.4),
        ),
        const Gap(16),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Total paid',
                value: formatRupiah(totalPaid),
                icon: AppIcons.money,
              ),
            ),
            const Gap(12),
            Expanded(
              child: _MetricTile(
                label: 'Bukti bayar',
                value: '$proofCount file',
                icon: AppIcons.imageNotFound,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconAsset icon;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider),
      ),
      child: Row(
        children: [
          HugeIcon(icon: icon, color: kPrimary, size: 22),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: kTextMid,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const Gap(3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: kTextDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceCard extends ConsumerStatefulWidget {
  final BillingInvoice invoice;

  const _InvoiceCard({required this.invoice});

  @override
  ConsumerState<_InvoiceCard> createState() => _InvoiceCardState();
}

class _InvoiceCardState extends ConsumerState<_InvoiceCard> {
  bool _downloading = false;
  bool _paying = false;
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: HugeIcon(
                  icon: AppIcons.receiptLong,
                  color: kPrimary,
                  size: 23,
                ),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.invoiceNo,
                      style: TextStyle(
                        color: kTextDark,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Gap(4),
                    Text(
                      '${invoice.planName} • ${formatShortDate(invoice.periodStart)} - ${formatShortDate(invoice.periodEnd)}',
                      style: TextStyle(color: kTextMid, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _StatusPill(status: invoice.status),
            ],
          ),
          const Gap(16),
          _InfoRow(
            label: 'Tanggal bayar',
            value: invoice.paidAt == null
                ? '-'
                : formatDateTime(invoice.paidAt!),
          ),
          const Gap(8),
          _InfoRow(
            label: 'Metode bayar',
            value: invoice.paymentMethodName ?? 'QRIS (Xendit)',
          ),
          const Gap(8),
          _InfoRow(label: 'Rekening tujuan', value: _paymentAccount(invoice)),
          if ((invoice.failureReason ?? '').isNotEmpty) ...[
            const Gap(8),
            _InfoRow(label: 'Alasan gagal', value: invoice.failureReason!),
          ],
          const Gap(8),
          _InfoRow(
            label: 'Nominal snapshot',
            value: formatRupiah(invoice.amountIdr),
            strong: true,
          ),
          if (invoice.isPayable) ...[
            const Gap(12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _paying ? null : _pay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _paying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.payment_rounded, size: 18),
                label: Text(_paying ? 'Membuka…' : 'Bayar Sekarang'),
              ),
            ),
          ],
          // Tombol cek status untuk invoice yang belum lunas. Berguna saat
          // webhook Xendit belum sampai (mis. dev pakai localhost) — backend
          // query langsung ke Xendit lalu update status & aktifkan langganan.
          if (invoice.status == 'pending' || invoice.status == 'unpaid') ...[
            const Gap(8),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                onPressed: _checking ? null : _checkStatus,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kPrimary,
                  side: BorderSide(color: kPrimary.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  _checking ? 'Mengecek…' : 'Cek Status Pembayaran',
                ),
              ),
            ),
            const Gap(6),
            Text(
              'Sudah scan & bayar QRIS tapi masih "Menunggu Bayar"? Tunggu '
              'beberapa detik lalu tekan "Cek Status Pembayaran". Status '
              '"Penyelesaian/Settlement" di Xendit itu pencairan dana (1–2 hari '
              'kerja), bukan status bayar — abaikan saja.',
              style: TextStyle(color: kTextMid, fontSize: 11, height: 1.35),
            ),
          ],
          const Gap(12),
          Row(
            children: [
              if ((invoice.paymentProofUrl ?? '').isNotEmpty)
                TextButton.icon(
                  onPressed: () =>
                      _showProof(context, invoice.paymentProofUrl!),
                  icon: HugeIcon(
                    icon: AppIcons.imageNotFound,
                    color: kPrimary,
                    size: 18,
                  ),
                  label: const Text('Lihat bukti'),
                )
              else
                Text(
                  'Bukti bayar belum ada',
                  style: TextStyle(color: kTextMid, fontSize: 12),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _downloading ? null : _shareInvoice,
                icon: _downloading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const HugeIcon(
                        icon: AppIcons.download,
                        color: Colors.white,
                        size: 18,
                      ),
                label: Text(_downloading ? 'Menyiapkan' : 'Invoice'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Buka halaman QRIS in-app (Payments API v3) untuk invoice yang masih
  /// pending: tampilkan QR + polling status sampai lunas.
  Future<void> _pay() async {
    final qr = widget.invoice.gatewayPaymentUrl; // QR string mentah (v3).
    if (qr == null || qr.isEmpty) return;
    setState(() => _paying = true);
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => SubscriptionQrPaymentPage(
            invoiceId: widget.invoice.id,
            invoiceNo: widget.invoice.invoiceNo,
            amountIdr: widget.invoice.amountIdr,
            qrString: qr,
            planName: widget.invoice.planName,
          ),
        ),
      );
      if (!mounted) return;
      ref.invalidate(billingInvoicesProvider);
      ref.invalidate(activeOutletSubscriptionProvider);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  /// Tanya backend untuk sinkronkan status invoice ini dari Xendit.
  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    try {
      final updated = await ref
          .read(billingRepositoryProvider)
          .syncInvoice(widget.invoice.id);
      if (!mounted) return;
      ref.invalidate(billingInvoicesProvider);
      // Kalau jadi lunas, langganan ikut aktif → refresh status langganan.
      ref.invalidate(activeOutletSubscriptionProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updated.isPaid
                ? 'Pembayaran terkonfirmasi! Langganan aktif. 🎉'
                : 'Pembayaran belum terbaca. Kalau kamu sudah scan & bayar QRIS, tunggu beberapa detik lalu cek lagi.',
          ),
          backgroundColor: updated.isPaid ? kSuccess : kWarning,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Gagal cek status: ${e.toString().replaceAll('Exception: ', '')}',
          ),
          backgroundColor: kDanger,
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _shareInvoice() async {
    setState(() => _downloading = true);
    try {
      await ref.read(billingRepositoryProvider).shareInvoice(widget.invoice);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal download invoice: $e')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _showProof(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: CachedNetworkImage(
            imageUrl: resolveAssetUrl(url),
            fit: BoxFit.contain,
            errorWidget: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Bukti bayar tidak bisa dimuat'),
            ),
          ),
        ),
      ),
    );
  }
}

String _paymentAccount(BillingInvoice invoice) {
  final parts = <String>[
    if ((invoice.paymentChannel ?? '').isNotEmpty) invoice.paymentChannel!,
    if ((invoice.paymentAccountNo ?? '').isNotEmpty) invoice.paymentAccountNo!,
    if ((invoice.paymentAccountName ?? '').isNotEmpty)
      invoice.paymentAccountName!,
  ];
  if (parts.isEmpty) return '-';
  return parts.join(' - ');
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _InfoRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: kTextMid, fontSize: 12)),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: kTextDark,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _label(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  // `void`/`expired` BUKAN kegagalan bayar (checkout dibatalkan/kedaluwarsa),
  // jadi warnanya netral — bukan merah seperti `failed`.
  Color _color() {
    switch (status.toLowerCase()) {
      case 'paid':
        return kSuccess;
      case 'pending':
      case 'unpaid':
        return kWarning;
      case 'failed':
        return kDanger;
      default: // void, expired, unknown
        return kTextMid;
    }
  }

  String _label() {
    switch (status.toLowerCase()) {
      case 'paid':
        return 'LUNAS';
      case 'pending':
        return 'MENUNGGU BAYAR';
      case 'unpaid':
        return 'BELUM BAYAR';
      case 'void':
        return 'DIBATALKAN';
      case 'expired':
        return 'KEDALUWARSA';
      case 'failed':
        return 'GAGAL';
      default:
        return status.toUpperCase();
    }
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        separatorBuilder: (_, _) => const Gap(12),
        itemBuilder: (_, _) => const _SkeletonCard(),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Bone.text(words: 2),
          Gap(12),
          Bone.text(words: 5),
          Gap(12),
          Bone.text(words: 3),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Gap(80),
        HugeIcon(icon: AppIcons.receiptLong, color: kTextMid, size: 48),
        const Gap(16),
        Text(
          'Belum ada invoice',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: kTextDark,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        const Gap(8),
        Text(
          'Invoice billing akan muncul setelah outlet melakukan subscription berbayar.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kTextMid, height: 1.4),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: kDanger),
        ),
      ),
    );
  }
}
