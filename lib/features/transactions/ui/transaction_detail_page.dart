import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import '../../settings/data/app_settings.dart';
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

    // Apakah outlet mewajibkan PIN otorisasi manajer untuk refund? Fetch
    // on-demand (hasilnya di-cache provider). Bila gagal (mis. offline),
    // fallback false lalu andalkan penanganan 403 dari backend.
    bool requirePin = false;
    try {
      requirePin =
          (await ref.read(outletAppSettingsProvider.future)).requirePinRefund;
    } catch (_) {
      requirePin = false;
    }
    if (!mounted) return;

    // Loop retry: bila submit gagal (mis. 403 PIN salah), dialog dibuka ulang
    // dengan pesan backend + input sebelumnya sehingga user bisa perbaiki PIN.
    // Mode & pilihan qty item ikut dipertahankan supaya user tak mengulang.
    String reasonInit = '';
    String pinInit = '';
    bool partialInit = false;
    Map<String, int> qtyInit = {};
    String? errorText;
    while (true) {
      final input = await _askRefundReason(
        sale: sale,
        requirePin: requirePin,
        reasonInit: reasonInit,
        pinInit: pinInit,
        partialInit: partialInit,
        qtyInit: qtyInit,
        errorText: errorText,
      );
      if (input == null) return; // dibatalkan

      setState(() => _refunding = true);
      try {
        await ref.read(transactionRepositoryProvider).refund(
              sale.id,
              reason: input.reason,
              overridePin: input.pin.isEmpty ? null : input.pin,
              // items hanya dikirim di mode "Refund sebagian". Mode penuh
              // mengirim null → backend melakukan refund penuh (default lama).
              items: input.items,
            );
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
        return;
      } catch (e) {
        if (!mounted) return;
        // Pertahankan input & tampilkan pesan backend (mis. "PIN otorisasi
        // salah") di dialog berikutnya supaya user bisa isi ulang.
        reasonInit = input.reason;
        pinInit = input.pin;
        partialInit = input.items != null;
        qtyInit = {
          for (final it in (input.items ?? const <Map<String, dynamic>>[]))
            it['transaction_item_id'] as String: it['quantity'] as int,
        };
        errorText = e.toString();
      } finally {
        if (mounted) setState(() => _refunding = false);
      }
    }
  }

  /// Dialog konfirmasi refund: input alasan (wajib, min 5 char), pilihan mode
  /// "Refund penuh" (default) vs "Refund sebagian", dan — bila [requirePin]
  /// atau percobaan sebelumnya ditolak backend ([errorText] != null) — input
  /// PIN otorisasi manajer (numeric, obscure, 4-6 digit).
  ///
  /// Pada mode "Refund sebagian", user memilih qty tiap item yang diretur
  /// (0..sisa = quantity - refundedQty; item sisa 0 disabled). Minimal 1 item
  /// dengan qty > 0.
  ///
  /// Mengembalikan record `(reason, pin, items)` jika dikonfirmasi, atau null
  /// jika dibatalkan. `items` = null pada mode penuh; berisi daftar
  /// `{transaction_item_id, quantity}` pada mode sebagian. [pin] bisa string
  /// kosong bila PIN tidak diminta.
  Future<({String reason, String pin, List<Map<String, dynamic>>? items})?>
  _askRefundReason({
    required Sale sale,
    required bool requirePin,
    String reasonInit = '',
    String pinInit = '',
    bool partialInit = false,
    Map<String, int> qtyInit = const {},
    String? errorText,
  }) async {
    final reasonController = TextEditingController(text: reasonInit);
    final pinController = TextEditingController(text: pinInit);
    // Tampilkan input PIN bila outlet mewajibkan, atau bila percobaan
    // sebelumnya ditolak backend (403) — supaya user bisa mengisi ulang.
    final showPin = requirePin || errorText != null;

    // Item yang masih bisa diretur (sisa qty > 0) untuk mode sebagian.
    final refundableItems =
        sale.items.where((it) => it.remainingQty > 0).toList();
    final canPartial = refundableItems.length > 1 ||
        (refundableItems.isNotEmpty &&
            refundableItems.any((it) => it.remainingQty > 1)) ||
        sale.isPartiallyRefunded;

    // Qty terpilih per item (key = SaleItem.id). Awalnya 0 supaya user
    // memilih eksplisit; dipulihkan dari qtyInit saat retry.
    final selectedQty = <String, int>{
      for (final it in refundableItems)
        it.id: (qtyInit[it.id] ?? 0).clamp(0, it.remainingQty),
    };
    bool partial = partialInit && canPartial;

    final result = await showDialog<
        ({String reason, String pin, List<Map<String, dynamic>>? items})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final reason = reasonController.text.trim();
          final pin = pinController.text.trim();
          final reasonValid = reason.length >= 5;
          final pinValid = pin.length >= 4 && pin.length <= 6;
          // PIN wajib bila outlet mensyaratkan. Bila hanya muncul akibat 403
          // (bukan requirePin), PIN opsional tapi format tetap divalidasi.
          final pinOk = requirePin ? pinValid : (pin.isEmpty || pinValid);
          final selectedCount =
              selectedQty.values.fold<int>(0, (s, q) => s + q);
          // Mode sebagian wajib ≥1 item qty>0.
          final itemsOk = !partial || selectedCount > 0;
          final valid = reasonValid && pinOk && itemsOk;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              ref.t('refund.confirm_title'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (errorText != null) ...[
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
                    ],
                    Text(
                      partial
                          ? ref.t('refund.select_items_hint')
                          : ref.t('refund.confirm_body'),
                      style: TextStyle(color: kTextMid, height: 1.4),
                    ),
                    // Pemilih mode penuh vs sebagian. Hanya tampil bila memang
                    // ada peluang retur sebagian (item/qty sisa cukup).
                    if (canPartial) ...[
                      const Gap(12),
                      _RefundModeToggle(
                        partial: partial,
                        onChanged: (v) => setLocal(() => partial = v),
                      ),
                    ],
                    if (partial) ...[
                      const Gap(12),
                      Text(
                        ref.t('refund.select_items'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: kTextDark,
                          fontSize: 13,
                        ),
                      ),
                      const Gap(6),
                      for (final it in refundableItems)
                        _RefundItemStepper(
                          item: it,
                          value: selectedQty[it.id] ?? 0,
                          onChanged: (v) =>
                              setLocal(() => selectedQty[it.id] = v),
                        ),
                    ],
                    const Gap(12),
                    TextField(
                      controller: reasonController,
                      autofocus: !partial,
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
                    if (showPin) ...[
                      const Gap(12),
                      TextField(
                        controller: pinController,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => setLocal(() {}),
                        decoration: InputDecoration(
                          labelText: requirePin
                              ? 'PIN Otorisasi Manajer'
                              : 'PIN Otorisasi Manajer (bila diminta)',
                          hintText: '4-6 digit',
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: valid
                    ? () {
                        // Mode sebagian → kirim daftar item qty>0. Mode penuh →
                        // items null supaya backend melakukan refund penuh.
                        final List<Map<String, dynamic>>? items = partial
                            ? [
                                for (final e in selectedQty.entries)
                                  if (e.value > 0)
                                    <String, dynamic>{
                                      'transaction_item_id': e.key,
                                      'quantity': e.value,
                                    },
                              ]
                            : null;
                        Navigator.of(ctx).pop(
                          (reason: reason, pin: pin, items: items),
                        );
                      }
                    : null,
                style: FilledButton.styleFrom(backgroundColor: kDanger),
                child: Text(ref.t('refund.action')),
              ),
            ],
          );
        },
      ),
    );
    reasonController.dispose();
    pinController.dispose();
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

    // Transaksi lunas (atau sudah diretur sebagian) & masih ada item bersisa
    // → user dgn Permission.refund boleh refund. Retur penuh tidak bisa
    // diretur lagi. Tombolnya ada di AppBar (di samping cetak & share).
    final canRefund = sale != null &&
        (sale.isPaid || sale.isPartiallyRefunded) &&
        !sale.isRefunded &&
        sale.hasRefundableItems &&
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
    // lunas yang menampilkan aksi (terima/tolak bukti) di bawah. Transaksi
    // yang sudah diretur (penuh/sebagian) sudah pernah lunas → jangan tampilkan
    // aksi bayar walau payment_status bukan 'paid' lagi.
    final Widget? bottomActions =
        (sale == null || sale.isPaid || sale.isRefunded ||
                sale.isPartiallyRefunded)
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
          if (!sale.isPaid &&
              !sale.isRefunded &&
              !sale.isPartiallyRefunded) ...[
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
          if (sale.isRefunded || sale.isPartiallyRefunded) ...[
            const Gap(12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (sale.isPartiallyRefunded ? kWarning : kDanger)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HugeIcon(
                    icon: AppIcons.alertCircle,
                    color: sale.isPartiallyRefunded ? kWarning : kDanger,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sale.isPartiallyRefunded
                              ? ref.t('refund.status_partial').toUpperCase()
                              : 'TRANSAKSI DI-REFUND',
                          style: TextStyle(
                            color:
                                sale.isPartiallyRefunded ? kWarning : kDanger,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (sale.refundedAmount > 0) ...[
                          const Gap(2),
                          Text(
                            '${ref.t('refund.refunded_amount')}: '
                            '${formatRupiah(sale.refundedAmount)}',
                            style: TextStyle(
                              color: kTextDark,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
                      // Retur per-item: tandai berapa qty item ini yang sudah
                      // diretur supaya kasir tahu sisa yang masih bisa diretur.
                      if (sale.items[i].refundedQty > 0) ...[
                        const Gap(2),
                        Text(
                          '${ref.t('refund.item_refunded')}: '
                          '${sale.items[i].refundedQty} dari ${sale.items[i].qty}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: kWarning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

/// Segmented control mode refund pada dialog: "Refund penuh" (kiri) vs
/// "Refund sebagian" (kanan). Segmen aktif diberi warna primary.
class _RefundModeToggle extends ConsumerWidget {
  final bool partial;
  final ValueChanged<bool> onChanged;
  const _RefundModeToggle({required this.partial, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget seg(String label, bool value) {
      final selected = partial == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? kPrimary : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : kTextMid,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kDivider),
      ),
      child: Row(
        children: [
          seg(ref.t('refund.mode_full'), false),
          seg(ref.t('refund.mode_partial'), true),
        ],
      ),
    );
  }
}

/// Baris item pada mode "Refund sebagian": nama item + sisa qty yang bisa
/// diretur + stepper (− nilai +) dengan batas 0..[SaleItem.remainingQty].
class _RefundItemStepper extends StatelessWidget {
  final SaleItem item;
  final int value;
  final ValueChanged<int> onChanged;
  const _RefundItemStepper({
    required this.item,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final maxQty = item.remainingQty;
    final canDec = value > 0;
    final canInc = value < maxQty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.variant.isEmpty
                      ? item.productName
                      : '${item.productName} (${item.variant})',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: kTextDark,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Sisa bisa diretur: $maxQty',
                  style: TextStyle(fontSize: 11, color: kTextMid),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StepperButton(
            icon: Icons.remove_rounded,
            enabled: canDec,
            onTap: () => onChanged(value - 1),
          ),
          SizedBox(
            width: 30,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: kTextDark,
                fontSize: 15,
              ),
            ),
          ),
          _StepperButton(
            icon: Icons.add_rounded,
            enabled: canInc,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

/// Tombol bulat +/− untuk [_RefundItemStepper]. Dinonaktifkan (abu) saat
/// mencapai batas.
class _StepperButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _StepperButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? kPrimary.withValues(alpha: 0.1) : kBg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? kPrimary : kTextLight,
          ),
        ),
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
