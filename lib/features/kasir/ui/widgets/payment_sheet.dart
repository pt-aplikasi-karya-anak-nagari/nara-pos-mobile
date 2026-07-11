import 'dart:io';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';
import 'package:image_picker/image_picker.dart';
import '../../../order_types/data/order_type_repository.dart';
import '../../../../app/theme.dart';
import '../../../../core/image_crop.dart';
import '../../../../core/app_icons.dart';
import '../../../../core/format.dart';
import '../../../../core/i18n.dart';
import '../../../../core/notifications.dart';
import '../../../user/data/auth_service.dart';
import '../../../../core/outlet_scope.dart';
import '../../../printer/data/printer_service.dart';
import '../../../printer/data/printer_settings.dart';
import '../../../payments/data/payment_method_repository.dart';
import '../../../payments/domain/payment_method.dart';
import '../../../customers/data/customer_repository.dart';
import '../../../transactions/data/transaction_repository.dart';
import '../../../transactions/domain/sale.dart';
import '../../providers.dart';
import '../../../shifts/data/shift_repository.dart';
import '../../../settings/data/loyalty_settings.dart';
import '../../../discounts/data/promo_repository.dart';
import '../../../settings/data/tax_settings.dart';
import '../../../tables/data/table_repository.dart';
import '../../../tables/domain/pos_table.dart';
import 'table_selector_sheet.dart';

// Payment methods are now loaded from the database via paymentMethodsFutureProvider

// Dynamic order types will be loaded from the database via orderTypesFutureProvider

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
          title: const Text('Otorisasi Manajer'),
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
              const Text(
                'Diskon melampaui batas kasir. Masukkan PIN otorisasi manajer '
                'berwenang untuk melanjutkan transaksi.',
              ),
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
                  labelText: 'PIN Otorisasi Manajer',
                  hintText: '4-6 digit',
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
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: pinValid ? () => Navigator.pop(ctx, pin) : null,
              child: const Text('Otorisasi'),
            ),
          ],
        );
      },
    ),
  );
  pinController.dispose();
  return result;
}

class PaymentSheet extends HookConsumerWidget {
  final ValueChanged<String> onPaid;
  const PaymentSheet({super.key, required this.onPaid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grossTotal = ref.watch(totalProvider);
    final methodsAsync = ref.watch(paymentMethodsFutureProvider);
    final methods = methodsAsync.when(
      data: (list) => list.where((m) => m.isActive).toList(),
      loading: () => <PaymentMethod>[],
      error: (_, _) => <PaymentMethod>[],
    );

    // Add "Nanti" as a virtual payment method
    final allMethods = [
      ...methods,
      PaymentMethod(name: 'Bayar Nanti', type: 'later', isActive: true),
    ];

    final selectedIndex = useState<int?>(null);

    final orderTypes = ref.watch(orderTypesFutureProvider).value ?? [];
    final activeOrderType = ref.watch(activeOrderTypeProvider);

    final cashAmount = useState(0.0);
    final cashController = useTextEditingController();
    final customerNameController = useTextEditingController();

    // State upload bukti pembayaran (opsional, untuk metode non-cash).
    // proofPath = file lokal yang user pilih; proofUrl = hasil upload
    // dari backend yang kemudian dikirim sebagai payment_proof_url.
    final proofPath = useState<String?>(null);
    final proofUrl = useState<String?>(null);
    final uploadingProof = useState(false);
    // Guard anti double-tap saat checkout sedang diproses.
    final processing = useState(false);

    // E7: split / multi-tender payment. Tiap tender = metode + nominal (porsi
    // tagihan yang ditutup tender itu). Kosong = mode single-method biasa.
    final splitTenders =
        useState<List<({String method, String type, double amount})>>([]);

    // Promo & tukar poin (diskon level-order, di luar diskon item).
    final promoController = useTextEditingController();
    final appliedPromo = useState<AppliedPromo?>(null);
    final promoError = useState<String?>(null);
    final applyingPromo = useState(false);
    final redeemPoints = useState(false);

    final activeCustomer = ref.watch(activeCustomerProvider);
    final activeTable = ref.watch(activeTableProvider);
    final loyaltySettings = ref.watch(loyaltySettingsProvider);
    final isDineIn = activeOrderType?.name == 'Dine In';

    // ── Hitung diskon promo + tukar poin, lalu total yang benar-benar dibayar.
    final cartItems = ref.watch(cartProvider);
    final subtotalNow = ref.watch(subtotalProvider);
    final promoDiscount =
        appliedPromo.value?.discountFor(cartItems, subtotalNow) ?? 0.0;

    final pointValue = loyaltySettings.pointValue;
    final customerPoints = activeCustomer?.points ?? 0;
    // Poin maksimum yang bisa ditukar: dibatasi saldo poin pelanggan DAN agar
    // nilai tukarnya tidak melebihi sisa tagihan setelah promo.
    final afterPromo = grossTotal - promoDiscount;
    final affordablePoints = (loyaltySettings.enabled && pointValue > 0)
        ? (afterPromo / pointValue).floor()
        : 0;
    final maxRedeemablePoints = customerPoints < affordablePoints
        ? customerPoints
        : (affordablePoints < 0 ? 0 : affordablePoints);
    final canRedeemPoints =
        loyaltySettings.enabled &&
        pointValue > 0 &&
        activeCustomer != null &&
        maxRedeemablePoints > 0;
    final pointsToRedeem = (redeemPoints.value && canRedeemPoints)
        ? maxRedeemablePoints
        : 0;
    final pointsDiscount = (pointsToRedeem * pointValue).roundToDouble();

    // Total akhir = total kotor − promo − tukar poin (tidak pernah negatif).
    final rawPayable = grossTotal - promoDiscount - pointsDiscount;
    final total = rawPayable < 0 ? 0.0 : rawPayable;

    // E7: agregat split. splitActive → mode split (abaikan single-method).
    final splitActive = splitTenders.value.isNotEmpty;
    final splitPaid = splitTenders.value.fold<double>(0, (s, t) => s + t.amount);
    final splitRemaining = total - splitPaid;
    final splitCashPaid = splitTenders.value
        .where((t) => t.type == 'cash')
        .fold<double>(0, (s, t) => s + t.amount);

    // E10: mode PPN inklusif → PPN sudah termasuk di harga (label "termasuk"
    // supaya kasir paham PPN tidak ditambah di atas subtotal).
    final taxInclusive =
        ref.watch(activeOutletProvider)?.taxInclusive ?? false;

    // E5: tier & pengali poin pelanggan aktif (untuk badge di checkout).
    final custTier = activeCustomer?.membershipLevel ?? 'Regular';
    final custTierMult = loyaltySettings.multiplierFor(custTier);
    final showTierBadge =
        activeCustomer != null &&
        loyaltySettings.enabled &&
        (custTier != 'Regular' || custTierMult > 1.0);

    Future<void> applyPromo() async {
      final code = promoController.text.trim();
      if (code.isEmpty || applyingPromo.value) return;
      applyingPromo.value = true;
      promoError.value = null;
      try {
        final outlet = ref.read(activeOutletProvider);
        final outletId = outlet?.remoteId;
        if (outletId == null) {
          promoError.value = 'Outlet tidak aktif.';
          return;
        }
        final promo = await ref
            .read(promoRepositoryProvider)
            .validate(outletId, code);
        if (subtotalNow < promo.minPurchaseAmount) {
          appliedPromo.value = null;
          promoError.value =
              'Min. belanja ${formatRupiah(promo.minPurchaseAmount)} untuk promo ini.';
          return;
        }
        final disc = promo.discountFor(cartItems, subtotalNow);
        if (disc <= 0) {
          appliedPromo.value = null;
          promoError.value = 'Promo tidak berlaku untuk item di keranjang.';
          return;
        }
        appliedPromo.value = promo;
        promoError.value = null;
      } catch (e) {
        appliedPromo.value = null;
        promoError.value = 'Kode promo tidak valid / tidak aktif.';
      } finally {
        applyingPromo.value = false;
      }
    }

    void clearPromo() {
      appliedPromo.value = null;
      promoError.value = null;
      promoController.clear();
    }

    useEffect(() {
      if (activeCustomer != null && customerNameController.text.isEmpty) {
        customerNameController.text = activeCustomer.name;
      }
      return null;
    }, [activeCustomer]);

    useEffect(() {
      cashAmount.value = 0;
      cashController.clear();
      // Reset bukti pembayaran tiap kali user pindah metode — relevansi
      // foto-nya bisa berbeda antar metode (mis. QR code beda dari struk
      // transfer).
      proofPath.value = null;
      proofUrl.value = null;
      return null;
    }, [selectedIndex.value]);

    Future<void> pickPaymentProof() async {
      try {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1280,
          maxHeight: 1280,
          imageQuality: 80,
        );
        if (picked == null) return;
        final croppedPath = await ImageCrop.square(
          picked.path,
          title: 'Crop bukti pembayaran',
        );
        if (croppedPath == null) return;
        proofPath.value = croppedPath;
        uploadingProof.value = true;
        try {
          final url = await ref
              .read(transactionRepositoryProvider)
              .uploadPaymentProof(croppedPath);
          proofUrl.value = url;
        } finally {
          uploadingProof.value = false;
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal upload bukti: $e')),
          );
        }
      }
    }

    final change = cashAmount.value - total;
    final isTableSelected = !isDineIn || activeTable != null;

    final selectedPM =
        allMethods.isNotEmpty &&
            selectedIndex.value != null &&
            selectedIndex.value! < allMethods.length
        ? allMethods[selectedIndex.value!]
        : null;

    final canPay = splitActive
        ? (splitRemaining.abs() < 0.5 &&
              activeOrderType != null &&
              isTableSelected &&
              !uploadingProof.value &&
              !processing.value &&
              allMethods.isNotEmpty)
        : (selectedPM != null &&
              activeOrderType != null &&
              (selectedPM.type != 'cash' || cashAmount.value >= total) &&
              isTableSelected &&
              !uploadingProof.value &&
              !processing.value &&
              allMethods.isNotEmpty);

    Future<void> confirmPay() async {
      if (processing.value) return;
      final cart = ref.read(cartProvider);
      final subtotal = ref.read(subtotalProvider);
      final originalSubtotal = ref.read(originalSubtotalProvider);
      final tax = ref.read(taxProvider);
      final discountTotal = ref.read(discountTotalProvider);
      final serviceCharge = ref.read(serviceChargeProvider);

      // E7: mode split → metode "Split" (atau nama tunggal bila 1 tender),
      // selalu lunas. Mode single → metode terpilih.
      if (!splitActive && selectedPM == null) return;
      final method = splitActive
          ? (splitTenders.value.length > 1
                ? 'Split'
                : splitTenders.value.first.method)
          : selectedPM!.name;
      final isPaid = splitActive ? true : selectedPM!.type != 'later';
      final isCashPayment =
          splitActive ? splitCashPaid > 0 : selectedPM!.type == 'cash';

      final currentUser = ref.read(authProvider).user;
      // Untuk owner: outlet aktif yang dipilih lewat outlet-picker.
      // Untuk kasir/admin: outlet yang melekat pada akun mereka.
      final outlet = ref.read(activeOutletProvider);
      // Poin: base dikirim ke backend (backend yang mem-boost sesuai tier —
      // JANGAN kirim yang sudah di-boost, nanti dobel). awardedPoints = base ×
      // multiplier (rumus round sama dgn backend) dipakai untuk struk/Sale lokal
      // agar tampilan cocok dengan yang diberikan.
      final basePoints =
          (loyaltySettings.enabled &&
              isPaid &&
              activeCustomer != null &&
              loyaltySettings.amountPerPoint > 0)
          ? (total / loyaltySettings.amountPerPoint).floor()
          : 0;
      final awardedPoints = (basePoints * custTierMult).round();
      processing.value = true;
      try {
      // B1c: diskon melampaui batas kasir → backend menolak checkout (400,
      // pesan mengandung "melebihi batas"). Bungkus panggilan checkout dalam
      // loop retry: bila ditolak karena batas, minta PIN otorisasi manajer
      // (dialog mengikuti pola PIN void/refund B1a) lalu ulangi checkout dengan
      // `override_pin`. Diskon di bawah batas tidak pernah memicu dialog.
      Sale? saleResult;
      String? overridePin;
      while (saleResult == null) {
        try {
          saleResult = await ref
              .read(transactionRepositoryProvider)
              .saveFromCart(
            cart: cart,
            subtotal: subtotal,
            originalSubtotal: originalSubtotal,
            tax: tax,
            // discountTotal mencakup diskon item + promo + tukar poin supaya
            // laporan mencerminkan seluruh potongan. total (final_amount) sudah
            // dikurangi promo & poin di atas.
            discountTotal: discountTotal + promoDiscount + pointsDiscount,
            serviceCharge: serviceCharge,
            total: total,
            promoCode: appliedPromo.value?.code,
            paymentMethod: method,
            cashAmount: splitActive
                ? splitCashPaid
                : (selectedPM!.type == 'cash' ? cashAmount.value : 0),
            // Mode split: kembalian tak berlaku (amount = porsi tagihan).
            changeAmount: splitActive
                ? 0
                : (selectedPM!.type == 'cash' && change > 0 ? change : 0),
            // E7: rincian tender untuk backend (transaction_payments).
            payments: splitActive
                ? splitTenders.value
                      .map((t) => {
                        'payment_method': t.method,
                        // Kirim type supaya backend deteksi porsi tunai andal
                        // (tak bergantung nama metode).
                        'payment_type': t.type,
                        'amount': t.amount,
                      })
                      .toList()
                : null,
            customerName: customerNameController.text.trim(),
            orderType: activeOrderType?.name ?? 'Dine In',
            cashierId: currentUser?.remoteId ?? '',
            cashierName: currentUser?.name ?? '',
            outletRemoteId: outlet?.remoteId,
            outletName: outlet?.name ?? '',
            isPaid: isPaid,
            customerId: activeCustomer?.id,
            // base ke backend (backend mem-boost sesuai tier); awarded (boosted)
            // untuk Sale/struk lokal supaya cocok dengan poin yang diberikan.
            pointsEarned: basePoints,
            displayPointsEarned: awardedPoints,
            pointsUsed: pointsToRedeem,
            tableId: activeTable?.id,
            tableName: activeTable?.name,
            paymentProofUrl: proofUrl.value,
            overridePin: overridePin,
          );
        } catch (e) {
          final msg = e.toString().replaceAll('Exception: ', '');
          // Hanya error "diskon melebihi batas" yang boleh dilewati via PIN
          // manajer. Error lain (stok habis, shift tak aktif, dll) diteruskan
          // ke penanganan di bawah supaya tampil apa adanya ke kasir.
          if (!msg.contains('melebihi batas') || !context.mounted) rethrow;
          final pin = await _promptManagerPin(context, errorText: msg);
          // Dibatalkan → keluar tanpa error; keranjang dipertahankan agar kasir
          // bisa menyesuaikan diskon atau mencoba lagi.
          if (pin == null) return;
          overridePin = pin;
          // Ulangi checkout dengan override_pin. Bila PIN salah, backend
          // membalas pesan "melebihi batas" lagi → dialog dibuka ulang.
        }
      }
      final sale = saleResult;

      // Status meja kini diupdate otomatis oleh TransactionRepository.saveFromCart

      // Refresh cache yang terkait pelanggan agar poin, analisa, dan riwayat
      // pembelian di halaman detail pelanggan langsung sinkron.
      final customerId = activeCustomer?.id;
      if (customerId != null && customerId.isNotEmpty) {
        ref.invalidate(customerDetailProvider(customerId));
        ref.invalidate(customerSalesProvider(customerId));
        ref.invalidate(customersFutureProvider);
      }

      // Refresh laporan & dashboard agar revenue + produk terlaris terupdate.
      ref.invalidate(salesFutureProvider);
      ref.invalidate(activeShiftProvider);

      // Refresh list meja & area: backend baru saja menandai meja
      // (kalau dine-in) jadi occupied, perubahan ini perlu tercermin di
      // selektor meja & manajemen meja tanpa harus restart.
      //
      // Invalidate seluruh family `activeTableTransactionsProvider` (tanpa
      // argumen) supaya tidak cuma cache untuk activeTable yang ter-flush;
      // kalau ada dialog detail untuk meja LAIN yang masih hidup di tree
      // (jarang, tapi mungkin via split bill), mereka juga ikut refresh.
      if (activeTable != null) {
        ref.invalidate(tablesFutureProvider);
        ref.invalidate(tableGroupsFutureProvider);
      }
      ref.invalidate(activeTableTransactionsProvider);

      ref.read(cartProvider.notifier).clear();
      ref.read(activeCustomerProvider.notifier).set(null);
      ref.read(activeTableProvider.notifier).set(null);
      await ref
          .read(notificationServiceProvider)
          .showTransactionSuccess(
            saleId: sale.id,
            invoiceId: sale.invoiceId,
            total: total,
            paymentMethod: method,
            customerName: customerNameController.text.trim(),
            isPaid: isPaid,
          );
      final printerSettings = ref.read(printerSettingsProvider);
      if (printerSettings.autoPrint && printerSettings.hasDevice) {
        await ref.read(printerServiceProvider).printReceipt(sale);
      }
      // E11: cetak otomatis tiket dapur/bar per stasiun. `cart` di-snapshot di
      // awal confirmPay (sebelum keranjang di-clear di atas), jadi kategori
      // produk untuk routing masih tersedia. Gated toggle terpisah; perilaku
      // lama tak berubah saat toggle mati.
      if (printerSettings.autoPrintKitchen && printerSettings.hasDevice) {
        await ref.read(printerServiceProvider).printKitchenTickets(sale, cart);
      }
      // Buka laci kas otomatis bila ada porsi tunai. No-op aman bila
      // printer/laci tidak terpasang.
      if (isCashPayment) {
        await ref.read(printerServiceProvider).openCashDrawer();
      }
      // Transaksi offline: dialog sukses (yang fetch detail backend) tidak
      // akan muncul, jadi beri konfirmasi tersendiri di sini.
      if (sale.pendingSync && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tersimpan offline. Transaksi otomatis disinkronkan saat koneksi kembali.',
            ),
            backgroundColor: kWarning,
            duration: Duration(seconds: 4),
          ),
        );
      }
      onPaid(sale.id);
      } catch (e) {
        // Error checkout online nyata (4xx/5xx: stok habis, shift tak aktif,
        // produk dihapus, dll). Error offline sudah ditangani saveFromCart
        // (di-queue). Tampilkan ke kasir, JANGAN clear cart — biar bisa
        // diperbaiki/diulang tanpa kehilangan keranjang.
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Gagal menyimpan transaksi: ${e.toString().replaceAll('Exception: ', '')}',
              ),
              backgroundColor: kDanger,
            ),
          );
        }
      } finally {
        processing.value = false;
      }
    }

    // E7: dialog tambah tender split. Pilih metode (real, non-"Bayar Nanti") +
    // nominal (prefill sisa tagihan), lalu append ke splitTenders.
    Future<void> addSplitTender() async {
      if (methods.isEmpty) return;
      var chosen = methods.first;
      final remaining = splitRemaining < 0 ? 0.0 : splitRemaining;
      final amountCtrl = TextEditingController(
        text: remaining > 0 ? formatRupiah(remaining) : '',
      );
      var amountVal = remaining;
      final result = await showModalBottomSheet<
        ({String method, String type, double amount})
      >(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              return Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tambah Pembayaran',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: kTextDark,
                      ),
                    ),
                    const Gap(4),
                    Text(
                      'Sisa tagihan: ${formatRupiah(remaining)}',
                      style: TextStyle(color: kTextMid, fontSize: 12),
                    ),
                    const Gap(16),
                    Text(
                      'Metode',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: kTextDark,
                      ),
                    ),
                    const Gap(8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: methods.map((m) {
                        final active = m.name == chosen.name;
                        return GestureDetector(
                          onTap: () => setModalState(() => chosen = m),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: active
                                  ? kPrimary.withValues(alpha: 0.1)
                                  : kBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: active ? kPrimary : kDivider,
                              ),
                            ),
                            child: Text(
                              m.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: active ? kPrimary : kTextDark,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const Gap(16),
                    Text(
                      'Nominal',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: kTextDark,
                      ),
                    ),
                    const Gap(8),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                      autofocus: false,
                      onChanged: (v) =>
                          amountVal = parseRupiahInput(v).toDouble(),
                      decoration: InputDecoration(
                        hintText: 'Rp 0',
                        filled: true,
                        fillColor: kBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const Gap(16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          if (amountVal <= 0) return;
                          Navigator.pop(ctx, (
                            method: chosen.name,
                            type: chosen.type,
                            amount: amountVal,
                          ));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Tambah',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
      if (result != null && result.amount > 0) {
        splitTenders.value = [...splitTenders.value, result];
      }
    }

    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final available = screenHeight - viewInsets;
    final sheetHeight = (screenHeight * 0.82).clamp(0.0, available - 24);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        height: sheetHeight,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            MediaQuery.of(context).padding.bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kDivider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Pembayaran',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: kTextDark,
                ),
              ),
              const Gap(4),
              Text(
                'Total yang harus dibayar',
                style: TextStyle(fontSize: 13, color: kTextMid),
              ),
              const Gap(6),
              Text(
                formatRupiah(total),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: kPrimary,
                ),
              ),
              const Gap(12),
              // ── Panel Breakdown Transparansi Harga ──
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kDivider),
                ),
                child: Column(
                  children: [
                    _SheetBreakdownRow(
                      label: 'Subtotal',
                      // Pakai subtotal SEBELUM diskon item supaya baris
                      // "Subtotal − Diskon" foot ke total (kalau pakai subtotal
                      // setelah diskon, baris Diskon terlihat dobel-potong).
                      value: formatRupiah(ref.watch(originalSubtotalProvider)),
                    ),
                    if (ref.watch(discountTotalProvider) > 0) ...[
                      const Gap(6),
                      _SheetBreakdownRow(
                        label: 'Diskon',
                        value:
                            '- ${formatRupiah(ref.watch(discountTotalProvider))}',
                        color: kSuccess,
                      ),
                    ],
                    if (ref.watch(serviceChargeProvider) > 0) ...[
                      const Gap(6),
                      _SheetBreakdownRow(
                        label:
                            '${ref.watch(taxSettingsProvider).serviceChargeName} (${_payFmtPct(ref.watch(taxSettingsProvider).serviceChargePercent)}%)',
                        value: formatRupiah(ref.watch(serviceChargeProvider)),
                        color: kTextMid,
                      ),
                    ],
                    if (ref.watch(taxSettingsProvider).enabled) ...[
                      const Gap(6),
                      _SheetBreakdownRow(
                        label:
                            'PPN (${_payFmtPct(ref.watch(taxSettingsProvider).percent)}%)${taxInclusive ? ' · termasuk' : ''}',
                        value: formatRupiah(ref.watch(taxProvider)),
                        color: kTextMid,
                      ),
                    ],
                    if (promoDiscount > 0) ...[
                      const Gap(6),
                      _SheetBreakdownRow(
                        label:
                            'Promo${appliedPromo.value != null ? ' (${appliedPromo.value!.code})' : ''}',
                        value: '- ${formatRupiah(promoDiscount)}',
                        color: kSuccess,
                      ),
                    ],
                    if (pointsDiscount > 0) ...[
                      const Gap(6),
                      _SheetBreakdownRow(
                        label: 'Tukar $pointsToRedeem poin',
                        value: '- ${formatRupiah(pointsDiscount)}',
                        color: kSuccess,
                      ),
                    ],
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(color: kDivider, height: 1),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Bayar',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: kTextDark,
                          ),
                        ),
                        Text(
                          formatRupiah(total),
                          style: const TextStyle(
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
              const Gap(12),
              // ── Kode promo ──
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kDivider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: promoController,
                            enabled:
                                appliedPromo.value == null &&
                                !applyingPromo.value,
                            textCapitalization: TextCapitalization.characters,
                            onSubmitted: (_) => applyPromo(),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Kode promo',
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: kDivider),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: kDivider),
                              ),
                            ),
                          ),
                        ),
                        const Gap(8),
                        appliedPromo.value == null
                            ? ElevatedButton(
                                onPressed: applyingPromo.value
                                    ? null
                                    : applyPromo,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: applyingPromo.value
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Terapkan'),
                              )
                            : OutlinedButton(
                                onPressed: clearPromo,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kTextMid,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text('Hapus'),
                              ),
                      ],
                    ),
                    if (promoError.value != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          promoError.value!,
                          style: TextStyle(
                            color: Colors.red.shade400,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (appliedPromo.value != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Promo "${appliedPromo.value!.name}" diterapkan.',
                          style: TextStyle(color: kSuccess, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              // ── Tukar poin ──
              if (canRedeemPoints) ...[
                const Gap(10),
                Container(
                  decoration: BoxDecoration(
                    color: kBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kDivider),
                  ),
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    value: redeemPoints.value,
                    onChanged: (v) => redeemPoints.value = v,
                    activeThumbColor: kPrimary,
                    activeTrackColor: kPrimary.withValues(alpha: 0.5),
                    title: const Text(
                      'Tukar poin',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      '$customerPoints poin tersedia · tukar $maxRedeemablePoints poin = ${formatRupiah(maxRedeemablePoints * pointValue)}',
                      style: TextStyle(color: kTextMid, fontSize: 12),
                    ),
                  ),
                ),
              ],
              const Gap(20),
              Text(
                ref.t('order.type'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kTextDark,
                ),
              ),
              const Gap(8),
              Row(
                children: List.generate(orderTypes.length, (i) {
                  final ot = orderTypes[i];
                  final active =
                      (activeOrderType?.id.isNotEmpty == true &&
                          ot.id.isNotEmpty == true)
                      ? activeOrderType?.id == ot.id
                      : activeOrderType?.name == ot.name;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        ref.read(activeOrderTypeProvider.notifier).set(ot);
                        ref.read(cartProvider.notifier).setOrderType(ot);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: EdgeInsets.only(
                          right: i < orderTypes.length - 1 ? 8 : 0,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: active ? kPrimary.withValues(alpha: 0.1) : kBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: active ? kPrimary : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          children: [
                            HugeIcon(
                              icon: _getIcon(ot.iconName),
                              color: active ? kPrimary : kTextMid,
                              size: 20,
                            ),
                            const Gap(4),
                            Text(
                              ot.name,
                              style: TextStyle(
                                color: active ? kPrimary : kTextMid,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
              if (isDineIn) ...[
                const Gap(16),
                Text(
                  'Meja',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kTextDark,
                  ),
                ),
                const Gap(8),
                _TablePickerCard(activeTable: activeTable),
              ],
              const Gap(16),
              Text(
                ref.t('payment.customer_name'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kTextDark,
                ),
              ),
              const Gap(8),
              TextField(
                controller: customerNameController,
                readOnly: activeCustomer != null,
                textCapitalization: TextCapitalization.words,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: activeCustomer != null ? kTextMid : kTextDark,
                ),
                decoration: InputDecoration(
                  hintText: ref.t('payment.customer_name_hint'),
                  prefixIcon: Padding(
                    padding: EdgeInsets.all(12),
                    child: HugeIcon(
                      icon: AppIcons.person,
                      color: kTextMid,
                      size: 18,
                    ),
                  ),
                  filled: true,
                  fillColor: activeCustomer != null
                      ? kDivider.withValues(alpha: 0.3)
                      : kBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              // ── E5: badge tier + pengali poin pelanggan ──
              if (showTierBadge) ...[
                const Gap(10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _tierColor(custTier).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.workspace_premium_rounded,
                            color: _tierColor(custTier),
                            size: 14,
                          ),
                          const Gap(5),
                          Text(
                            custTier,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                              color: _tierColor(custTier),
                            ),
                          ),
                          if (custTierMult > 1.0) ...[
                            const Gap(6),
                            Text(
                              'poin ×${_fmtMult(custTierMult)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                color: _tierColor(custTier),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              const Gap(18),
              if (!splitActive) ...[
              Text(
                "Tipe Pembayaran",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kTextDark,
                ),
              ),
              const Gap(8),

              Row(
                children: List.generate(allMethods.length, (i) {
                  final active = selectedIndex.value == i;
                  final m = allMethods[i];
                  final color = _getColor(m.type);
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => selectedIndex.value = i,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: EdgeInsets.only(
                          right: i < allMethods.length - 1 ? 8 : 0,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: active ? color.withValues(alpha: 0.1) : kBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: active ? color : Colors.transparent,
                          ),
                        ),
                        child: Column(
                          children: [
                            HugeIcon(
                              icon: _getPMIcon(m.type),
                              color: active ? color : kTextMid,
                              size: 22,
                            ),
                            const Gap(4),
                            Text(
                              m.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: active ? color : kTextMid,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
              ], // ── akhir grid single-method (disembunyikan saat split) ──

              // ── E7: Split / multi-tender payment ──
              if (total > 0) ...[
                const Gap(14),
                if (!splitActive)
                  GestureDetector(
                    onTap: addSplitTender,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 14,
                      ),
                      decoration: BoxDecoration(
                        color: kBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kDivider),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.call_split_rounded,
                              color: kPrimary, size: 18),
                          const Gap(8),
                          Text(
                            'Bagi jadi beberapa metode (Split)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: kPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Split Pembayaran',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: kTextDark,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => splitTenders.value = [],
                        child: Text(
                          'Reset',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: kDanger,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(10),
                  ...List.generate(splitTenders.value.length, (i) {
                    final t = splitTenders.value[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: kBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kDivider),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.method,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: kTextDark,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            formatRupiah(t.amount),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: kTextDark,
                              fontSize: 13,
                            ),
                          ),
                          const Gap(6),
                          GestureDetector(
                            onTap: () {
                              final next = [...splitTenders.value]
                                ..removeAt(i);
                              splitTenders.value = next;
                            },
                            child: Icon(
                              Icons.close_rounded,
                              color: kDanger,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (splitRemaining > 0.5)
                    GestureDetector(
                      onTap: addSplitTender,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kPrimary),
                        ),
                        child: Text(
                          '+ Tambah metode',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: kPrimary,
                          ),
                        ),
                      ),
                    ),
                  const Gap(10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (splitRemaining.abs() < 0.5 ? kSuccess : kWarning)
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          splitRemaining.abs() < 0.5
                              ? 'Lunas'
                              : (splitRemaining > 0 ? 'Sisa tagihan' : 'Kelebihan'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: kTextDark,
                          ),
                        ),
                        Text(
                          formatRupiah(splitRemaining.abs()),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: splitRemaining.abs() < 0.5
                                ? kSuccess
                                : kWarning,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],

              // Dynamic Payment Details (QRIS / Transfer)
              if (!splitActive && selectedPM != null) ...[
                if (selectedPM.type == 'qris' &&
                    selectedPM.qrData != null &&
                    selectedPM.qrData!.isNotEmpty) ...[
                  const Gap(20),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kDivider),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Scan QRIS untuk Bayar',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: kTextMid,
                            ),
                          ),
                          const Gap(8),
                          Text(
                            formatRupiah(total),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                              color: kPrimary,
                            ),
                          ),
                          const Gap(16),
                          BarcodeWidget(
                            barcode: Barcode.qrCode(),
                            data: selectedPM.qrData!,
                            width: 180,
                            height: 180,
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else if (selectedPM.type == 'transfer' &&
                    selectedPM.accountNumber != null) ...[
                  const Gap(20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kDivider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detail Rekening Transfer',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: kTextDark,
                          ),
                        ),
                        const Divider(height: 24),
                        _InfoRow(
                          label: 'Bank',
                          value: selectedPM.providerName ?? '-',
                        ),
                        const Gap(8),
                        _InfoRow(
                          label: 'Nomor Rekening',
                          value: selectedPM.accountNumber!,
                          isCopyable: true,
                        ),
                        const Gap(8),
                        _InfoRow(
                          label: 'Atas Nama',
                          value: selectedPM.accountName ?? '-',
                        ),
                      ],
                    ),
                  ),
                ],
              ],

              if (!splitActive && selectedPM?.type == 'cash') ...[
                const Gap(20),
                Text(
                  'Jumlah Uang Tunai',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kTextDark,
                  ),
                ),
                const Gap(8),
                TextField(
                  controller: cashController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  onChanged: (v) =>
                      cashAmount.value = parseRupiahInput(v).toDouble(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: kTextDark,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Rp 0',
                    filled: true,
                    fillColor: kBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const Gap(10),
                Builder(
                  builder: (context) {
                    final denoms = [
                      1000,
                      2000,
                      5000,
                      10000,
                      20000,
                      50000,
                      100000,
                    ];
                    final suggestions = <double>{total}; // Start with Uang Pas

                    for (final d in denoms) {
                      final rounded = (total / d).ceil() * d.toDouble();
                      if (rounded > total) {
                        suggestions.add(rounded);
                      }
                    }

                    // Common large bills if not already present and total is below them
                    if (total < 50000) suggestions.add(50000);
                    if (total < 100000) suggestions.add(100000);

                    final sorted = suggestions.toList()..sort();
                    // Take top 6 most relevant suggestions
                    final finalItems = sorted.take(6).toList();

                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: finalItems.map((v) {
                        final isTotal = v == total;
                        final isActive = v == cashAmount.value;
                        return GestureDetector(
                          onTap: () {
                            cashAmount.value = v;
                            cashController.value = TextEditingValue(
                              text: formatRupiah(v),
                              selection: TextSelection.collapsed(
                                offset: formatRupiah(v).length,
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? kPrimary.withValues(alpha: 0.1)
                                  : kBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isActive ? kPrimary : kDivider,
                              ),
                            ),
                            child: Text(
                              isTotal ? 'Uang Pas' : formatRupiah(v),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isActive ? kPrimary : kTextDark,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                if (cashAmount.value >= total) ...[
                  const Gap(16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kSuccess.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            HugeIcon(
                              icon: AppIcons.checkCircle,
                              color: kSuccess,
                              size: 16,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Kembalian',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: kTextDark,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          formatRupiah(change),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: kSuccess,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              // ── Upload bukti pembayaran (opsional, untuk metode non-cash) ──
              if (!splitActive &&
                  selectedPM != null &&
                  selectedPM.type != 'cash' &&
                  selectedPM.type != 'later') ...[
                const Gap(20),
                _PaymentProofPicker(
                  filePath: proofPath.value,
                  uploading: uploadingProof.value,
                  onPick: pickPaymentProof,
                  onClear: () {
                    proofPath.value = null;
                    proofUrl.value = null;
                  },
                ),
              ],
              // ── Breakdown Transparan ──
              const Gap(24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: canPay ? confirmPay : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    disabledBackgroundColor: kTextLight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    (!splitActive && selectedPM?.type == 'later')
                        ? 'Simpan Pesanan (Bayar Nanti)'
                        : 'Konfirmasi Pembayaran',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconAsset _getPMIcon(String type) {
    switch (type) {
      case 'cash':
        return AppIcons.money;
      case 'qris':
        return AppIcons.qrCode;
      case 'card':
        return AppIcons.creditCard;
      case 'transfer':
        return AppIcons.payment;
      default:
        return AppIcons.time;
    }
  }

  Color _getColor(String type) {
    switch (type) {
      case 'cash':
        return kSuccess;
      case 'qris':
        return kAccent;
      case 'card':
        return kPrimary;
      case 'later':
        return kTextMid;
      default:
        return kPrimary;
    }
  }

  IconAsset _getIcon(String name) {
    switch (name) {
      case 'takeaway':
        return AppIcons.takeaway;
      case 'delivery':
        return AppIcons.delivery;
      default:
        return AppIcons.storefront;
    }
  }
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
        showModalBottomSheet(
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
                    activeTable != null ? activeTable!.name : 'Pilih Meja',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: activeTable != null ? kPrimary : kTextDark,
                    ),
                  ),
                  Text(
                    activeTable != null
                        ? '${activeTable!.group?.name ?? 'Meja'} — ${activeTable!.capacity} Kursi'
                        : 'Belum ada meja dipilih',
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
        const Text(
          'Bukti Pembayaran (opsional)',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        const Gap(2),
        Text(
          'Foto QRIS scan, struk transfer, atau receipt mesin EDC.',
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
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.white,
                        ),
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
            label: const Text('Upload Foto Bukti'),
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
