import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/format.dart';
import '../../../core/outlet_scope.dart';
import '../../billing/data/billing_repository.dart';
import '../data/subscription_repository.dart';
import '../domain/subscription.dart';
import 'subscription_qr_payment_page.dart';

/// Buka sheet pembayaran/perpanjangan langganan: pilih paket → buat invoice
/// checkout → buka link pembayaran Xendit di browser.
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

      final qr = result.gatewayPaymentUrl; // Payments API v3: QR string mentah.
      if (qr == null || qr.isEmpty) {
        _snack('QR pembayaran belum tersedia. Coba lagi sebentar.',
            error: true);
        return;
      }
      if (!mounted) return;

      // Tutup sheet pilih paket, lalu buka halaman QRIS in-app: QR ditampilkan
      // + polling status sampai lunas. Halaman QR yang meng-invalidate provider
      // langganan/billing saat status final, jadi tidak perlu pakai `ref` di
      // sini (state sheet sudah dispose setelah pop).
      final navigator = Navigator.of(context);
      navigator.pop();
      navigator.push<bool>(
        MaterialPageRoute(
          builder: (_) => SubscriptionQrPaymentPage(
            invoiceId: result.invoiceId,
            invoiceNo: result.invoiceNo,
            amountIdr: result.amountIdr,
            qrString: qr,
          ),
        ),
      );
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
    final plansAsync = ref.watch(subscriptionPlansProvider);
    final currentSub = ref.watch(activeOutletSubscriptionProvider).value;

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
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
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
        ),
      ),
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
