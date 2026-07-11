import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/outlet_scope.dart';
import '../data/subscription_repository.dart';
import '../domain/subscription.dart';
import 'subscription_checkout_sheet.dart';

class SubscriptionExpiryDialogListener extends ConsumerStatefulWidget {
  final Widget child;

  const SubscriptionExpiryDialogListener({super.key, required this.child});

  @override
  ConsumerState<SubscriptionExpiryDialogListener> createState() =>
      _SubscriptionExpiryDialogListenerState();
}

class _SubscriptionExpiryDialogListenerState
    extends ConsumerState<SubscriptionExpiryDialogListener> {
  String? _shownForOutletId;

  @override
  Widget build(BuildContext context) {
    ref.listen<
      AsyncValue<OutletSubscription?>
    >(activeOutletSubscriptionProvider, (previous, next) {
      next.whenData((subscription) {
        final outlet = ref.read(activeOutletProvider);
        final outletId = outlet?.remoteId;
        if (outlet == null || outletId == null || outletId.isEmpty) return;

        final expired = subscription == null || !subscription.isUsable;
        if (!expired) {
          if (_shownForOutletId == outletId) _shownForOutletId = null;
          return;
        }
        if (_shownForOutletId == outletId) return;
        _shownForOutletId = outletId;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: kCard,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              actionsPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              title: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: kDanger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: HugeIcon(
                        icon: AppIcons.alertCircle,
                        color: kDanger,
                        size: 23,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Subscription sudah habis',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              content: Text(
                'Langganan outlet ${outlet.name} sudah habis. Silakan subscription ulang untuk melanjutkan akses operasional outlet.',
                style: TextStyle(
                  color: kTextMid,
                  fontSize: 14,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Nanti'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    showSubscriptionCheckoutSheet(context, ref);
                  },
                  child: const Text('Subscription ulang'),
                ),
              ],
            ),
          );
        });
      });
    });

    return widget.child;
  }
}

class SubscriptionBanner extends ConsumerWidget {
  const SubscriptionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outlet = ref.watch(activeOutletProvider);
    if (outlet == null) return const SizedBox.shrink();

    final asyncSub = ref.watch(activeOutletSubscriptionProvider);
    return asyncSub.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => _BannerShell(
        color: kDanger,
        icon: AppIcons.alertCircle,
        text: 'Status langganan ${outlet.name} belum bisa dimuat',
      ),
      data: (subscription) {
        void openSheet() => showSubscriptionCheckoutSheet(context, ref);
        if (subscription == null) {
          return _BannerShell(
            color: kWarning,
            icon: AppIcons.alertCircle,
            text: 'Outlet ${outlet.name} belum punya langganan aktif',
            onTap: openSheet,
          );
        }
        return _SubscriptionStateBanner(
          outletName: outlet.name,
          subscription: subscription,
          onRenew: openSheet,
        );
      },
    );
  }
}

class _SubscriptionStateBanner extends StatelessWidget {
  final String outletName;
  final OutletSubscription subscription;
  final VoidCallback onRenew;

  const _SubscriptionStateBanner({
    required this.outletName,
    required this.subscription,
    required this.onRenew,
  });

  @override
  Widget build(BuildContext context) {
    if (!subscription.isUsable) {
      return _BannerShell(
        color: kDanger,
        icon: AppIcons.alertCircle,
        text: 'Langganan $outletName sudah berakhir — ketuk untuk perpanjang',
        onTap: onRenew,
      );
    }

    final planName = subscription.planName ?? subscription.planCode;
    final expiringSoon =
        subscription.isTrial || subscription.daysRemaining <= 3;
    final color = expiringSoon ? kWarning : kPrimary;
    final text = subscription.isTrial
        ? 'Trial Basic $outletName tersisa ${subscription.daysRemaining} hari'
        : '$planName aktif ${subscription.daysRemaining} hari lagi';

    return _BannerShell(
      color: color,
      icon: subscription.isTrial ? AppIcons.time : AppIcons.checkCircle,
      text: text,
      // Saat trial / mau habis, banner bisa diketuk untuk perpanjang dini.
      onTap: expiringSoon ? onRenew : null,
    );
  }
}

class _BannerShell extends StatelessWidget {
  final Color color;
  final IconAsset icon;
  final String text;
  final VoidCallback? onTap;

  const _BannerShell({
    required this.color,
    required this.icon,
    required this.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.11),
      child: InkWell(
        onTap: onTap,
        child: SafeArea(
          bottom: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: color.withValues(alpha: 0.22)),
              ),
            ),
            child: Row(
              children: [
                HugeIcon(icon: icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.chevron_right_rounded, color: color, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
