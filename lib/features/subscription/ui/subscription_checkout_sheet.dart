import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme.dart';
import '../../../core/format.dart';
import '../../../core/image_crop.dart';
import '../../../core/outlet_scope.dart';
import '../../billing/data/billing_repository.dart';
import '../data/subscription_repository.dart';
import '../domain/subscription.dart';

/// Buka sheet pembayaran/perpanjangan langganan: pilih paket → buat invoice
/// checkout → tampilkan instruksi transfer bank manual + unggah bukti transfer.
Future<void> showSubscriptionCheckoutSheet(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SubscriptionCheckoutSheet(),
  );
}

class _SubscriptionCheckoutSheet extends ConsumerStatefulWidget {
  const _SubscriptionCheckoutSheet();

  @override
  ConsumerState<_SubscriptionCheckoutSheet> createState() =>
      _SubscriptionCheckoutSheetState();
}

class _SubscriptionCheckoutSheetState
    extends ConsumerState<_SubscriptionCheckoutSheet> {
  String? _selectedCode;
  bool _loading = false;
  bool _uploading = false;

  /// Hasil checkout — bila terisi, sheet beralih dari daftar paket ke
  /// instruksi transfer bank + tombol unggah bukti transfer.
  BillingCheckoutResult? _result;

  Future<void> _checkout(String planCode, {String? renewalMode}) async {
    final outletId = ref.read(activeOutletIdProvider);
    if (outletId == null || outletId.isEmpty) {
      _snack('Outlet aktif tidak ditemukan', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await ref
          .read(billingRepositoryProvider)
          .createCheckout(outletId, planCode, renewalMode: renewalMode);
      if (!mounted) return;
      // Invoice pending dibuat → riwayat tagihan berubah.
      ref.invalidate(billingInvoicesProvider);
      // Tampilkan instruksi transfer bank di sheet ini (bukan lagi QR gateway).
      setState(() => _result = result);
    } on RenewalChoiceRequiredException catch (e) {
      if (!mounted) return;
      final mode = await _askRenewalMode(e.message);
      if (mode != null) {
        await _checkout(planCode, renewalMode: mode);
        return;
      }
    } catch (e) {
      _snack(e.toString().replaceAll('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Pilih foto bukti transfer (crop kotak) lalu unggah ke backend. Setelah
  /// sukses tutup sheet — invoice tetap `pending` sampai admin konfirmasi.
  Future<void> _uploadProof(String invoiceId) async {
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
        title: 'Crop bukti transfer',
      );
      if (croppedPath == null) return;
      if (!mounted) return;
      setState(() => _uploading = true);
      await ref
          .read(billingRepositoryProvider)
          .uploadPaymentProof(invoiceId, File(croppedPath));
      if (!mounted) return;
      ref.invalidate(billingInvoicesProvider);
      _snack('Bukti transfer terkirim. Menunggu konfirmasi admin. 🙌');
      Navigator.of(context).pop();
    } catch (e) {
      _snack('Gagal unggah bukti: ${e.toString().replaceAll('Exception: ', '')}',
          error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<String?> _askRenewalMode(String message) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Sudah punya langganan aktif',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: Text(message, style: TextStyle(color: kTextMid, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('renew'),
            child: const Text('Perpanjang paket ini'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('upgrade_replace'),
            child: const Text('Ganti paket'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? kDanger : kSuccess,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const Gap(12),
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
            Expanded(
              child: _result == null
                  ? _buildPlanSelection(scrollController)
                  : _buildInstructions(scrollController, _result!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanSelection(ScrollController scrollController) {
    final plansAsync = ref.watch(subscriptionPlansProvider);
    final currentSub = ref.watch(activeOutletSubscriptionProvider).value;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Perpanjang Langganan',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kTextDark,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: plansAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Gagal memuat paket: $e',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kTextMid),
                ),
              ),
            ),
            data: (plans) {
              if (plans.isEmpty) {
                return Center(
                  child: Text(
                    'Belum ada paket langganan tersedia.',
                    style: TextStyle(color: kTextMid),
                  ),
                );
              }
              // Pre-select: paket aktif saat ini, atau yang di-highlight.
              _selectedCode ??=
                  currentSub?.planCode ??
                  plans
                      .firstWhere(
                        (p) => p.isHighlighted,
                        orElse: () => plans.first,
                      )
                      .code;
              return ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                itemCount: plans.length,
                separatorBuilder: (_, _) => const Gap(12),
                itemBuilder: (context, i) {
                  final plan = plans[i];
                  return _PlanCard(
                    plan: plan,
                    selected: _selectedCode == plan.code,
                    isCurrent: currentSub?.planCode == plan.code,
                    onTap: _loading
                        ? null
                        : () => setState(() => _selectedCode = plan.code),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (_loading || _selectedCode == null)
                  ? null
                  : () => _checkout(_selectedCode!),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Lanjut ke Pembayaran',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInstructions(
    ScrollController scrollController,
    BillingCheckoutResult result,
  ) {
    final pi = result.paymentInstruction;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Transfer Pembayaran',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kTextDark,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nominal transfer',
                      style: TextStyle(color: kTextMid, fontSize: 12),
                    ),
                    const Gap(4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatRupiah(result.amountIdr),
                            style: TextStyle(
                              color: kTextDark,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _CopyIconButton(
                          text: result.amountIdr.toString(),
                          onCopied: () => _snack('Nominal disalin'),
                        ),
                      ],
                    ),
                    const Gap(2),
                    Text(
                      'Invoice ${result.invoiceNo}',
                      style: TextStyle(color: kTextMid, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Gap(16),
              if (pi != null) ...[
                _InstructionRow(label: 'Bank', value: pi.bankName),
                const Gap(10),
                _InstructionRow(
                  label: 'No. rekening',
                  value: pi.bankAccountNo,
                  copyable: true,
                  onCopy: () => _snack('No. rekening disalin'),
                ),
                const Gap(10),
                _InstructionRow(label: 'Atas nama', value: pi.bankAccountName),
                if (pi.instructions.isNotEmpty) ...[
                  const Gap(16),
                  Text(
                    pi.instructions,
                    style: TextStyle(
                      color: kTextMid,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ] else
                Text(
                  'Detail rekening tujuan belum tersedia. Buka Riwayat Tagihan '
                  'untuk mengunggah bukti transfer.',
                  style: TextStyle(color: kTextMid, fontSize: 13, height: 1.5),
                ),
              const Gap(16),
              Text(
                'Transfer sesuai nominal di atas, lalu unggah bukti transfer. '
                'Langganan aktif setelah admin mengonfirmasi transfer masuk.',
                style: TextStyle(color: kTextMid, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _uploading
                      ? null
                      : () => _uploadProof(result.invoiceId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _uploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.upload_file_rounded, size: 20),
                  label: Text(
                    _uploading ? 'Mengunggah…' : 'Unggah bukti transfer',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const Gap(8),
              TextButton(
                onPressed: _uploading
                    ? null
                    : () => Navigator.of(context).pop(),
                child: Text('Nanti saja', style: TextStyle(color: kTextMid)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool selected;
  final bool isCurrent;
  final VoidCallback? onTap;

  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? kPrimary.withValues(alpha: 0.06) : kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? kPrimary : kDivider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? kPrimary : kTextLight,
                  size: 20,
                ),
                const Gap(8),
                Expanded(
                  child: Text(
                    plan.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: kTextDark,
                    ),
                  ),
                ),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: kSuccess.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Paket Saat Ini',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kSuccess,
                      ),
                    ),
                  ),
              ],
            ),
            const Gap(8),
            Text(
              '${formatRupiah(plan.priceIdr)} / bulan',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: kPrimary,
              ),
            ),
            if (plan.description.isNotEmpty) ...[
              const Gap(6),
              Text(
                plan.description,
                style: TextStyle(fontSize: 12, color: kTextMid, height: 1.4),
              ),
            ],
            if (plan.features.isNotEmpty) ...[
              const Gap(10),
              ...plan.features.take(5).map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_rounded, size: 15, color: kSuccess),
                      const Gap(6),
                      Expanded(
                        child: Text(
                          f,
                          style: TextStyle(fontSize: 12, color: kTextDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Baris detail rekening tujuan (label kiri, nilai kanan tebal, opsional
/// tombol salin ke clipboard).
class _InstructionRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;
  final VoidCallback? onCopy;

  const _InstructionRow({
    required this.label,
    required this.value,
    this.copyable = false,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: TextStyle(color: kTextMid, fontSize: 13)),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            style: TextStyle(
              color: kTextDark,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
        if (copyable && value.isNotEmpty)
          _CopyIconButton(text: value, onCopied: onCopy ?? () {}),
      ],
    );
  }
}

/// Tombol salin nilai ke clipboard (mis. nominal / no. rekening).
class _CopyIconButton extends StatelessWidget {
  final String text;
  final VoidCallback onCopied;

  const _CopyIconButton({required this.text, required this.onCopied});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: 'Salin',
      onPressed: text.isEmpty
          ? null
          : () {
              Clipboard.setData(ClipboardData(text: text));
              onCopied();
            },
      icon: Icon(Icons.copy_rounded, size: 18, color: kPrimary),
    );
  }
}
