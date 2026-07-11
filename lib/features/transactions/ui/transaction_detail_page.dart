import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gap/gap.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/product_image.dart';
import '../../kasir/ui/widgets/summary_row.dart';
import '../../printer/data/printer_service.dart';
import '../../printer/data/printer_settings.dart';
import '../../customers/data/customer_repository.dart';
import '../../shifts/data/shift_repository.dart';
import '../../access_rights/data/access_rights_repository.dart';
import '../../access_rights/domain/permission.dart';
import '../data/transaction_repository.dart';
import '../domain/sale.dart';
import '../domain/sale_item.dart';
import 'widgets/mini_payment_sheet.dart';

class TransactionDetailPage extends ConsumerStatefulWidget {
  final String saleId;

  /// Jika true, halaman ditampilkan sebagai panel (tanpa AppBar back button)
  /// untuk master-detail layout di tablet.
  final bool embedded;
  const TransactionDetailPage({
    super.key,
    required this.saleId,
    this.embedded = false,
  });

  @override
  ConsumerState<TransactionDetailPage> createState() =>
      _TransactionDetailPageState();
}

class _TransactionDetailPageState extends ConsumerState<TransactionDetailPage> {
  final _receiptKey = GlobalKey();
  bool _sharing = false;
  bool _printing = false;
  bool _rejecting = false;
  bool _refunding = false;

  Future<void> _printReceipt(Sale sale) async {
    if (_printing) return;
    final settings = ref.read(printerSettingsProvider);
    if (!settings.hasDevice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Printer belum diatur. Buka Profil › Printer Thermal.'),
        ),
      );
      return;
    }
    setState(() => _printing = true);
    try {
      final ok = await ref
          .read(printerServiceProvider)
          .printReceipt(sale, reprint: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Struk dicetak' : 'Gagal mencetak struk'),
            backgroundColor: ok ? kSuccess : kDanger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _shareAsImage(Sale sale) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _receiptKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/resi_${sale.id.toString().padLeft(3, '0')}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text:
              'Resi Transaksi #${sale.invoiceId.isNotEmpty ? sale.invoiceId : sale.id}\nTotal: ${formatRupiah(sale.total)}',
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }


  /// Tolak bukti pembayaran dari customer (QR menu). Sebelum eksekusi,
  /// kasir konfirmasi via dialog supaya tidak salah tap. Backend men-clear
  /// payment_proof_url; customer di nara-scan-qr akan kembali ke flow
  /// upload bukti.
  Future<void> _rejectProof(Sale sale) async {
    if (_rejecting) return;
    final confirmed = await _confirmReject();
    if (confirmed != true) return;

    setState(() => _rejecting = true);
    try {
      await ref
          .read(transactionRepositoryProvider)
          .rejectPaymentProof(sale.id);
      ref.invalidate(transactionDetailProvider(sale.id));
      ref.invalidate(salesFutureProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Bukti pembayaran ditolak. Customer akan diminta upload ulang.',
            ),
            backgroundColor: kWarning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menolak bukti: $e'),
            backgroundColor: kDanger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _rejecting = false);
    }
  }

  Future<bool?> _confirmReject() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Tolak bukti pembayaran?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Bukti yang sudah di-upload customer akan dihapus dari transaksi. '
          'Customer di QR menu akan diminta upload ulang bukti pembayaran. '
          'Status transaksi tetap belum lunas.',
          style: TextStyle(color: kTextMid, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: kDanger),
            child: const Text('Ya, Tolak Bukti'),
          ),
        ],
      ),
    );
  }

  /// Refund transaksi yang sudah lunas. Hanya bisa dipanggil oleh user
  /// dengan [Permission.refund]. Backend mengembalikan stok, set status
  /// refunded, dan mengurangi poin pelanggan. Alasan refund wajib (min 5
  /// karakter di backend) supaya jejak audit jelas.
  Future<void> _refund(Sale sale) async {
    if (_refunding) return;
    final reason = await _askRefundReason();
    if (reason == null) return; // dibatalkan

    setState(() => _refunding = true);
    try {
      await ref.read(transactionRepositoryProvider).refund(sale.id, reason: reason);
      ref.invalidate(transactionDetailProvider(sale.id));
      ref.invalidate(salesFutureProvider);
      // Refund menyentuh laci kas shift aktif (uang keluar) & poin pelanggan,
      // jadi invalidate provider terkait supaya angka konsisten.
      ref.invalidate(activeShiftProvider);
      if (sale.customer?.id.isNotEmpty == true) {
        ref.invalidate(customerDetailProvider(sale.customer!.id));
        ref.invalidate(customerSalesProvider(sale.customer!.id));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ref.t('refund.success')),
            backgroundColor: kSuccess,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal refund: $e'),
            backgroundColor: kDanger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _refunding = false);
    }
  }

  /// Dialog konfirmasi refund dengan input alasan. Mengembalikan alasan
  /// (sudah trim, min 5 char) jika dikonfirmasi, atau null jika dibatalkan.
  Future<String?> _askRefundReason() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final reason = controller.text.trim();
          final valid = reason.length >= 5;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              ref.t('refund.confirm_title'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ref.t('refund.confirm_body'),
                  style: TextStyle(color: kTextMid, height: 1.4),
                ),
                const Gap(12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 3,
                  textInputAction: TextInputAction.newline,
                  onChanged: (_) => setLocal(() {}),
                  decoration: InputDecoration(
                    hintText: 'Alasan refund (min. 5 karakter)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: valid ? () => Navigator.of(ctx).pop(reason) : null,
                style: FilledButton.styleFrom(backgroundColor: kDanger),
                child: Text(ref.t('refund.action')),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _payNow(Sale sale) async {
    // Kalau customer sudah upload bukti (QR menu), metode pembayaran
    // sudah dipilih saat checkout. Kasir tinggal memverifikasi & terima
    // — tidak perlu MiniPaymentSheet lagi. Cukup dialog konfirmasi
    // ringan ("Terima pembayaran?") supaya tap tidak langsung commit.
    final hasProof =
        sale.paymentProofUrl != null && sale.paymentProofUrl!.isNotEmpty;

    if (hasProof) {
      final ok = await _confirmAccept(sale);
      if (ok != true) return;
      await _executeMarkAsPaid(
        sale,
        paymentMethod: sale.paymentMethod,
        cashAmount: 0,
        changeAmount: 0,
        paymentProofUrl: sale.paymentProofUrl,
      );
      return;
    }

    // Tanpa bukti → flow lama: buka sheet untuk input metode & cash.
    final result = await showModalBottomSheet<
      ({String method, double cash, String proofUrl})
    >(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MiniPaymentSheet(total: sale.total),
    );
    if (result == null) return;
    final cashAmount = result.method == 'Tunai' ? result.cash : 0.0;
    final changeAmount =
        (result.method == 'Tunai' && result.cash > sale.total)
        ? result.cash - sale.total
        : 0.0;
    await _executeMarkAsPaid(
      sale,
      paymentMethod: result.method,
      cashAmount: cashAmount,
      changeAmount: changeAmount,
      paymentProofUrl: result.proofUrl.isEmpty ? null : result.proofUrl,
    );
  }

  /// Confirm dialog ringan untuk flow "Terima & Lunaskan" saat bukti
  /// sudah ada. Tampilkan ringkasan: metode bayar (dari customer), total,
  /// dan dua tombol — Batal / Terima & Lunaskan.
  Future<bool?> _confirmAccept(Sale sale) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Terima & Lunaskan?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pastikan bukti pembayaran sudah sesuai dengan total transaksi. '
              'Setelah dikonfirmasi, status akan berubah jadi Lunas.',
              style: TextStyle(color: kTextMid, height: 1.4),
            ),
            const Gap(12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kDivider),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'Metode',
                        style: TextStyle(fontSize: 12, color: kTextMid),
                      ),
                      const Spacer(),
                      Text(
                        sale.paymentMethod,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kTextDark,
                        ),
                      ),
                    ],
                  ),
                  const Gap(6),
                  Row(
                    children: [
                      Text(
                        'Total',
                        style: TextStyle(fontSize: 12, color: kTextMid),
                      ),
                      const Spacer(),
                      Text(
                        formatRupiah(sale.total),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: kPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: kSuccess),
            child: const Text('Terima & Lunaskan'),
          ),
        ],
      ),
    );
  }

  /// Eksekusi markAsPaid + invalidate provider + snackbar.
  /// Dipisah jadi helper supaya 2 jalur (dengan bukti / tanpa bukti)
  /// bisa share. Error message konsisten.
  Future<void> _executeMarkAsPaid(
    Sale sale, {
    required String paymentMethod,
    required double cashAmount,
    required double changeAmount,
    String? paymentProofUrl,
  }) async {
    try {
      await ref
          .read(transactionRepositoryProvider)
          .markAsPaid(
            sale.id,
            paymentMethod: paymentMethod,
            cashAmount: cashAmount,
            changeAmount: changeAmount,
            paymentProofUrl: paymentProofUrl,
          );
      ref.invalidate(transactionDetailProvider(sale.id));
      ref.invalidate(salesFutureProvider);
      ref.invalidate(activeShiftProvider);
      if (sale.customer?.id.isNotEmpty == true) {
        ref.invalidate(customerDetailProvider(sale.customer!.id));
        ref.invalidate(customerSalesProvider(sale.customer!.id));
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Pembayaran berhasil')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal melunasi: $e'),
            backgroundColor: kDanger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(transactionDetailProvider(widget.saleId));
    final sale = detailAsync.value;
    final idLabel = sale?.invoiceId.isNotEmpty == true
        ? sale!.invoiceId
        : widget.saleId;

    // Transaksi lunas & belum di-refund → user dgn Permission.refund boleh
    // refund. Tombolnya ada di AppBar (di samping cetak & share).
    final canRefund = sale != null &&
        sale.isPaid &&
        !sale.isRefunded &&
        ref.hasPermission(Permission.refund);

    final actions = <Widget>[
      if (sale != null)
        IconButton(
          tooltip: 'Cetak struk',
          onPressed: _printing ? null : () => _printReceipt(sale),
          icon: _printing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kPrimary,
                  ),
                )
              : const HugeIcon(icon: AppIcons.printer, color: kPrimary),
        ),
      if (sale != null)
        IconButton(
          tooltip: ref.t('history.share'),
          onPressed: _sharing ? null : () => _shareAsImage(sale),
          icon: _sharing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kPrimary,
                  ),
                )
              : const HugeIcon(icon: AppIcons.share, color: kPrimary),
        ),
      // Refund — hanya untuk transaksi lunas & user berizin. Dipindah ke AppBar
      // (di samping cetak & share) supaya konsisten dgn aksi lain.
      if (sale != null && canRefund)
        IconButton(
          tooltip: ref.t('refund.action'),
          onPressed: _refunding ? null : () => _refund(sale),
          icon: _refunding
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kDanger,
                  ),
                )
              : const Icon(
                  Icons.assignment_return_rounded,
                  color: kDanger,
                ),
        ),
    ];

    final bodyContent = detailAsync.when(
      // Skeleton meniru _ReceiptCard dengan dummy Sale supaya layout struk
      // sudah terlihat siap saat data masih dalam perjalanan.
      loading: () => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Skeletonizer(
              enabled: true,
              child: _ReceiptCard(
                sale: Sale(
                  createdAt: DateTime.now(),
                  subtotal: 25000,
                  tax: 2500,
                  total: 27500,
                  paymentMethod: 'Cash',
                  invoiceId: 'INV-XXXXXXXXXX',
                  outletName: 'Outlet',
                  cashAmount: 50000,
                  changeAmount: 22500,
                )..items = [
                  SaleItem(
                    productName: 'Nama Produk',
                    productEmoji: '📦',
                    price: 10000,
                    qty: 1,
                  ),
                  SaleItem(
                    productName: 'Nama Produk',
                    productEmoji: '📦',
                    price: 15000,
                    qty: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      error: (e, _) => Center(child: Text('Gagal mengambil detail: $e')),
      data: (sale) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: RepaintBoundary(
              key: _receiptKey,
              child: _ReceiptCard(sale: sale),
            ),
          ),
        ),
      ),
    );

    // Tombol-tombol bawah:
    //   - Sudah lunas → tidak ada
    //   - Belum lunas TANPA bukti → 1 tombol "Bayar Sekarang"
    //   - Belum lunas DENGAN bukti → 2 tombol: "Tolak Bukti" (danger
    //     outlined) + "Terima & Lunaskan" (success filled). Kasir
    //     verifikasi bukti di card di atas lalu pilih salah satu.
    final hasProof =
        sale != null &&
        sale.paymentProofUrl != null &&
        sale.paymentProofUrl!.isNotEmpty;
    // Tombol Refund kini ada di AppBar (di samping cetak & share), bukan di
    // bawah. Untuk transaksi LUNAS tak ada bottom bar; hanya transaksi belum
    // lunas yang menampilkan aksi (terima/tolak bukti) di bawah.
    final Widget? bottomActions = sale == null
        ? null
        : sale.isPaid
        ? null
        : SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: hasProof
                ? Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: _rejecting ? null : () => _rejectProof(sale),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kDanger,
                              side: BorderSide(color: kDanger, width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: _rejecting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: kDanger,
                                    ),
                                  )
                                : Icon(Icons.close_rounded, color: kDanger),
                            label: const Text(
                              'Tolak',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 6,
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _rejecting ? null : () => _payNow(sale),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kSuccess,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: Icon(Icons.check_rounded, color: Colors.white),
                            label: const Text(
                              'Terima & Lunaskan',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: () => _payNow(sale),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kSuccess,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const HugeIcon(
                              icon: AppIcons.payment,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Bayar Sekarang',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          );

    if (widget.embedded) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: kDivider)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Transaksi #$idLabel',
                      style: TextStyle(
                        color: kTextDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
            Expanded(child: bodyContent),
            bottomActions ?? const SizedBox.shrink(),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard,
        elevation: 0,
        iconTheme: IconThemeData(color: kTextDark),
        title: Text(
          'Transaksi #$idLabel',
          style: TextStyle(
            color: kTextDark,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        actions: actions,
      ),
      body: bodyContent,
      bottomNavigationBar: bottomActions,
    );
  }
}

class _ReceiptCard extends ConsumerWidget {
  final Sale sale;
  const _ReceiptCard({required this.sale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idLabel = sale.invoiceId.isNotEmpty ? sale.invoiceId : sale.id;
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Text(
                'NARA',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: kTextDark,
                ),
              ),
              const Gap(2),
              Text(
                'Struk Transaksi',
                style: TextStyle(fontSize: 12, color: kTextMid),
              ),
              const Gap(10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '#$idLabel',
                  style: const TextStyle(
                    color: kPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              if (sale.isFromMenuQr) ...[
                const Gap(8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: kPrimary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_2, size: 13, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'Pesanan dari Menu QR',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const Gap(14),
          Divider(color: kDivider, height: 1),
          const Gap(12),
          Row(
            children: [
              HugeIcon(icon: AppIcons.event, color: kTextMid, size: 14),
              const SizedBox(width: 6),
              Text(
                formatDateTime(sale.createdAt),
                style: TextStyle(color: kTextMid, fontSize: 12),
              ),
            ],
          ),
          const Gap(6),
          Row(
            children: [
              HugeIcon(icon: AppIcons.payment, color: kTextMid, size: 14),
              const SizedBox(width: 6),
              Text(
                'Metode: ${sale.paymentMethod}',
                style: TextStyle(color: kTextMid, fontSize: 12),
              ),
            ],
          ),
          const Gap(6),
          Row(
            children: [
              HugeIcon(
                icon: AppIcons.storefront,
                color: kTextMid,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                'Tipe: ${sale.orderType}',
                style: TextStyle(color: kTextMid, fontSize: 12),
              ),
            ],
          ),
          // Info meja untuk dine-in — supaya kasir/owner tahu pesanan
          // dari meja mana, dan customer di struk bisa cross-check.
          // Tidak menambah prefix "Meja:" karena `tableName` dari DB
          // umumnya sudah include kata "Meja" (mis. "Meja 1").
          if (sale.isDineIn && sale.tableDisplay != null) ...[
            const Gap(6),
            Row(
              children: [
                Icon(
                  Icons.table_restaurant_rounded,
                  color: kTextMid,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    sale.tableDisplay!,
                    style: TextStyle(color: kTextMid, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (sale.customerName.isNotEmpty) ...[
            const Gap(6),
            Row(
              children: [
                HugeIcon(
                  icon: AppIcons.person,
                  color: kTextMid,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Pembeli: ${sale.customerName}',
                    style: TextStyle(color: kTextMid, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (sale.cashierName.isNotEmpty) ...[
            const Gap(6),
            Row(
              children: [
                HugeIcon(
                  icon: AppIcons.person,
                  color: kTextMid,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Kasir: ${sale.cashierName}'
                    '${sale.outletName.isNotEmpty ? ' • ${sale.outletName}' : ''}',
                    style: TextStyle(color: kTextMid, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (!sale.isPaid) ...[
            const Gap(12),
            // Label status — beda bila customer sudah upload bukti via
            // QR menu (status = menunggu konfirmasi kasir) vs murni
            // bayar nanti (belum ada bukti sama sekali).
            Builder(
              builder: (_) {
                final hasProof =
                    sale.paymentProofUrl != null &&
                    sale.paymentProofUrl!.isNotEmpty;
                final color = hasProof ? kPrimary : kWarning;
                final label = hasProof
                    ? 'MENUNGGU KONFIRMASI PEMBAYARAN'
                    : 'BELUM DIBAYAR (Bayar Nanti)';
                final icon = hasProof ? AppIcons.time : AppIcons.time;
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      HugeIcon(icon: icon, color: color, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          if (sale.isRefunded) ...[
            const Gap(12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kDanger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HugeIcon(
                    icon: AppIcons.alertCircle,
                    color: kDanger,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TRANSAKSI DI-REFUND',
                          style: TextStyle(
                            color: kDanger,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (sale.refundReason?.isNotEmpty == true) ...[
                          const Gap(2),
                          Text(
                            'Alasan: ${sale.refundReason}',
                            style: TextStyle(color: kTextMid, fontSize: 11),
                          ),
                        ],
                        if (sale.refundedAt != null) ...[
                          const Gap(2),
                          Text(
                            formatDateTime(sale.refundedAt!),
                            style: TextStyle(color: kTextMid, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Bukti pembayaran (foto QRIS scan / struk transfer / dll).
          // Selalu tampil bila `paymentProofUrl` ada — terlepas dari status.
          // Buat paid: jadi arsip/audit; saat unpaid: kasir verifikasi
          // sebelum tap Konfirmasi Pembayaran.
          if (sale.paymentProofUrl != null &&
              sale.paymentProofUrl!.isNotEmpty) ...[
            const Gap(12),
            _PaymentProofCard(
              proofUrl: sale.paymentProofUrl!,
              isPaid: sale.isPaid,
            ),
          ],
          const Gap(14),
          Text(
            'Item',
            style: TextStyle(fontWeight: FontWeight.w700, color: kTextDark),
          ),
          const Gap(8),
          for (int i = 0; i < sale.items.length; i++) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(color: kDivider, height: 1),
              ),
            Row(
              children: [
                ProductImage(
                  name: sale.items[i].productName,
                  size: 36,
                  radius: 10,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sale.items[i].variant.isEmpty
                            ? sale.items[i].productName
                            : '${sale.items[i].productName} (${sale.items[i].variant})',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: kTextDark,
                          fontSize: 13,
                        ),
                      ),
                      if (sale.items[i].discountAmount > 0)
                        Row(
                          children: [
                            Text(
                              formatRupiah(sale.items[i].originalPrice),
                              style: TextStyle(
                                fontSize: 10,
                                color: kTextLight,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Diskon ${sale.items[i].discountLabel}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: kAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      Text(
                        '${sale.items[i].qty} × ${formatRupiah(sale.items[i].price)}',
                        style: TextStyle(fontSize: 11, color: kTextMid),
                      ),
                      if (sale.items[i].note.isNotEmpty) ...[
                        const Gap(4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: kBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: kDivider,
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              HugeIcon(
                                icon: AppIcons.notes,
                                color: kTextMid,
                                size: 11,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  sale.items[i].note,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: kTextDark,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  formatRupiah(sale.items[i].subtotal),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kTextDark,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
          const Gap(14),
          Divider(color: kDivider, height: 1),
          const Gap(12),
          _ReceiptBreakdownRow(
            label: 'Subtotal',
            value: formatRupiah(sale.subtotal),
          ),
          if (sale.discountTotal > 0) ...[
            const Gap(6),
            _ReceiptBreakdownRow(
              label: 'Diskon',
              value: '-${formatRupiah(sale.discountTotal)}',
              color: kAccent,
            ),
          ],
          if (sale.serviceCharge > 0) ...[
            const Gap(6),
            _ReceiptBreakdownRow(
              label: 'Layanan',
              value: formatRupiah(sale.serviceCharge),
            ),
          ],
          if (sale.tax > 0) ...[
            const Gap(6),
            _ReceiptBreakdownRow(label: 'PPN', value: formatRupiah(sale.tax)),
          ],
          Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: kDivider, height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: kTextDark,
                ),
              ),
              Text(
                formatRupiah(sale.total),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: kPrimary,
                ),
              ),
            ],
          ),
          if (sale.cashAmount > 0) ...[
            const Gap(8),
            SummaryRow('Tunai', formatRupiah(sale.cashAmount)),
            const Gap(4),
            SummaryRow('Kembalian', formatRupiah(sale.changeAmount)),
          ],
          const Gap(16),
          Center(
            child: Text(
              'Terima kasih atas kunjungan Anda',
              style: TextStyle(
                fontSize: 11,
                color: kTextMid,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Baris bukti pembayaran dalam bentuk [ListTile]. Ketuk untuk membuka
/// dialog dengan pinch-zoom — dipakai kasir untuk verifikasi nominal /
/// detail bukti sebelum tap "Konfirmasi Pembayaran".
class _PaymentProofCard extends StatelessWidget {
  final String proofUrl;
  final bool isPaid;
  const _PaymentProofCard({required this.proofUrl, required this.isPaid});

  @override
  Widget build(BuildContext context) {
    final absoluteUrl = resolveAssetUrl(proofUrl);
    return Container(
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kDivider, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _showZoomDialog(context, absoluteUrl),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 6,
        ),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: HugeIcon(icon: AppIcons.receipt, color: kPrimary, size: 20),
        ),
        title: Text(
          'Bukti Pembayaran',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: kTextDark,
            fontSize: 13,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            isPaid
                ? 'Ketuk untuk melihat bukti pembayaran.'
                : 'Ketuk untuk verifikasi sebelum konfirmasi pembayaran.',
            style: TextStyle(fontSize: 11, color: kTextMid),
          ),
        ),
        trailing: !isPaid
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Perlu Verifikasi',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: kPrimary,
                  ),
                ),
              )
            : Icon(Icons.chevron_right, color: kTextMid, size: 20),
      ),
    );
  }

  void _showZoomDialog(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _ProofZoomDialog(imageUrl: url),
    );
  }
}

/// Dialog full-bleed berisi gambar bukti pembayaran dengan
/// [InteractiveViewer] (pinch-zoom 0.5×–5× + pan). Tap di area kosong
/// atau tombol close untuk menutup.
class _ProofZoomDialog extends StatelessWidget {
  final String imageUrl;
  const _ProofZoomDialog({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Backdrop tap-to-close di luar gambar.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                },
                errorBuilder: (_, _, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    HugeIcon(
                      icon: AppIcons.alertCircle,
                      color: Colors.white,
                      size: 40,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Gagal memuat bukti pembayaran',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Tombol close pojok kanan atas — anti-flicker walau zoom.
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.close, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptBreakdownRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _ReceiptBreakdownRow({
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
