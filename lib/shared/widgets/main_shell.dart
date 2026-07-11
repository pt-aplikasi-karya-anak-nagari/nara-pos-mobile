import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';

import '../../app/theme.dart';
import '../../core/app_icons.dart';
import '../../core/i18n.dart';
import '../../core/responsive.dart';
import '../../features/notifications/data/notification_history.dart';
import '../../features/profil/data/profil_state.dart';

import '../../features/user/data/auth_service.dart';
import '../../features/user/domain/user_role.dart';

class _NavItem {
  final IconAsset icon;
  final String labelKey;
  final int branch;
  /// Opsional. Bila di-set, badge angka muncul di sudut kanan-atas icon —
  /// di-watch reactive lewat WidgetRef. Return 0 = badge hidden.
  final int Function(WidgetRef ref)? badgeBuilder;
  const _NavItem({
    required this.icon,
    required this.labelKey,
    this.branch = -1,
    this.badgeBuilder,
  });
}

class MainShell extends HookConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const MainShell({super.key, required this.navigationShell});

  List<_NavItem> _getVisibleItems(UserRole role) {
    return [
      const _NavItem(
        icon: AppIcons.storefront,
        labelKey: 'nav.kasir',
        branch: 0,
      ),
      const _NavItem(
        icon: AppIcons.receiptLong,
        labelKey: 'nav.riwayat',
        branch: 1,
      ),
      _NavItem(
        icon: AppIcons.notification,
        labelKey: 'nav.notifikasi',
        branch: 2,
        badgeBuilder: (ref) => ref.watch(unreadNotificationCountProvider),
      ),
      const _NavItem(
        icon: AppIcons.barChart,
        labelKey: 'nav.laporan',
        branch: 3,
      ),
      const _NavItem(
        icon: AppIcons.person,
        labelKey: 'nav.profil',
        branch: 4,
      ),
    ];
  }

  // Branch index untuk tab Profil (geser dari 3 setelah Notifikasi disisipkan
  // di branch 2). Disimpan const supaya kalau order tab berubah lagi nanti,
  // ada satu titik tunggal yang harus di-update.
  static const int _profileBranchIndex = 4;

  void _onTap(int visualIndex, List<_NavItem> items, WidgetRef ref) {
    final item = items[visualIndex];
    final branch = item.branch;

    // Reset state profil saat pindah tab — baik masuk tab profil (supaya
    // mulai dari menu utama, bukan submenu terakhir) maupun keluar
    // (supaya saat kembali, fresh state). Selalu reset, jadi logika
    // if-else di sini cuma untuk dokumentasi maksud.
    if (branch == _profileBranchIndex) {
      ref.read(selectedProfileMenuProvider.notifier).state = null;
    } else {
      ref.read(selectedProfileMenuProvider.notifier).state = null;
    }

    navigationShell.goBranch(
      branch,
      // Selalu reset ke root halaman saat pindah tab atau klik tab yang sama
      initialLocation: true,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTablet = context.isTablet;
    final user = ref.watch(authProvider).user;
    final role = user?.role ?? UserRole.cashier;
    final visibleItems = _getVisibleItems(role);

    // Controller untuk animasi auto-hide bottom nav saat scroll.
    // value 1.0 = nav tampil penuh, 0.0 = nav tersembunyi.
    final navAnim = useAnimationController(
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 240),
      initialValue: 1.0,
    );
    final navSize = useMemoized(
      () => CurvedAnimation(parent: navAnim, curve: Curves.easeInOutCubic),
      [navAnim],
    );
    useEffect(() => navSize.dispose, [navSize]);

    // Pastikan nav kembali tampil ketika user pindah tab/branch
    // (mis. setelah hidden lalu navigasi programatik).
    final currentBranch = navigationShell.currentIndex;
    useEffect(() {
      navAnim.forward();
      return null;
    }, [currentBranch]);

    // Find visual index that matches current branch
    int activeVisualIndex = visibleItems.indexWhere(
      (item) => item.branch == currentBranch,
    );
    // Fallback if current branch is not in visible items (e.g. redirected)
    if (activeVisualIndex == -1) activeVisualIndex = 0;

    const double hPad = 8.0;
    const double navH = 58.0;
    const double tabletItemW = 110.0;
    final int totalVisualItems = visibleItems.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/bg.jpg', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(color: kBg.withValues(alpha: 0.85)),
          ),
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // Auto-hide hanya aktif di tab Kasir (branch 0). Tab lain
              // (Riwayat, Laporan, Profil) bukan halaman utama scroll-heavy
              // dan banyak punya form/sheet di dalamnya, jadi nav-nya
              // dibuat selalu tampil supaya tidak menyembunyikan kontrol
              // navigasi tanpa sebab.
              if (navigationShell.currentIndex != 0) return false;
              if (notification.metrics.axis != Axis.vertical) {
                return false;
              }
              // Hide selama scrolling (mulai dari sentuhan user atau fling
              // momentum), tampil lagi setelah scroll benar-benar berhenti.
              // ScrollStartNotification → user mulai scroll
              // ScrollEndNotification  → scroll selesai (termasuk momentum)
              if (notification is ScrollStartNotification) {
                if (navAnim.status != AnimationStatus.dismissed &&
                    navAnim.status != AnimationStatus.reverse) {
                  navAnim.reverse();
                }
              } else if (notification is ScrollEndNotification) {
                if (navAnim.status != AnimationStatus.completed &&
                    navAnim.status != AnimationStatus.forward) {
                  navAnim.forward();
                }
              }
              return false;
            },
            child: navigationShell,
          ),
        ],
      ),
      bottomNavigationBar: SizeTransition(
        sizeFactor: navSize,
        // axisAlignment deprecated post-v3.41 — pakai `alignment` yang
        // memberi kontrol penuh untuk dua sumbu. Untuk mempertahankan
        // perilaku lama (-1.0 axisAlignment → anchor di bottom),
        // alignment vertikal di-set ke +1.0 (kebawah) supaya panel
        // muncul "tumbuh ke atas" saat sizeFactor → 1.
        alignment: const Alignment(0, 1),
        child: DecoratedBox(
          // Hairline separator khas tab bar iOS, di-paint di atas glass.
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Colors.black.withValues(alpha: 0.06),
                width: 0.5,
              ),
            ),
          ),
          position: DecorationPosition.foreground,
          child: Container(
            decoration: BoxDecoration(color: kCard),
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalW = constraints.maxWidth;

                  final double itemW;
                  final double pillLeft;

                  if (isTablet) {
                    itemW = tabletItemW;
                    final innerW = totalW - 2 * hPad;
                    final rowOffset =
                        (innerW - totalVisualItems * tabletItemW) / 2;
                    pillLeft =
                        hPad + rowOffset + activeVisualIndex * tabletItemW;
                  } else {
                    itemW = (totalW - 2 * hPad) / totalVisualItems;
                    pillLeft = hPad + activeVisualIndex * itemW;
                  }

                  return SizedBox(
                    height: navH,
                    child: Stack(
                      children: [
                        // ── Sliding highlight pill ─────────────────────────
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          left: pillLeft,
                          width: itemW,
                          top: 6,
                          bottom: 6,
                          child: Container(
                            decoration: BoxDecoration(
                              color: kPrimary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),

                        // ── Nav items ──────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: hPad),
                          child: Row(
                            mainAxisAlignment: isTablet
                                ? MainAxisAlignment.center
                                : MainAxisAlignment.start,
                            children: List.generate(totalVisualItems, (vi) {
                              final item = visibleItems[vi];

                              // ── Regular nav items ──
                              final active = vi == activeVisualIndex;

                              final tile = GestureDetector(
                                onTap: () => _onTap(vi, visibleItems, ref),
                                behavior: HitTestBehavior.opaque,
                                child: SizedBox(
                                  height: navH,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      AnimatedScale(
                                        scale: active ? 1.1 : 1.0,
                                        duration: const Duration(
                                          milliseconds: 250,
                                        ),
                                        curve: Curves.easeOut,
                                        child: _NavIconWithBadge(
                                          item: item,
                                          active: active,
                                        ),
                                      ),
                                      const Gap(3),
                                      AnimatedDefaultTextStyle(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: active
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                          color: active ? kPrimary : kTextMid,
                                        ),
                                        child: Text(ref.t(item.labelKey)),
                                      ),
                                    ],
                                  ),
                                ),
                              );

                              if (isTablet) {
                                return SizedBox(
                                  width: tabletItemW,
                                  child: tile,
                                );
                              }
                              return Expanded(child: tile);
                            }),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon nav dengan badge angka di sudut kanan-atas. Dipisah jadi
/// ConsumerWidget supaya `ref.watch` hanya men-trigger rebuild di sub-tree
/// icon — bukan entire MainShell (yang besar & punya animation controller).
class _NavIconWithBadge extends ConsumerWidget {
  final _NavItem item;
  final bool active;
  const _NavIconWithBadge({required this.item, required this.active});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = item.badgeBuilder?.call(ref) ?? 0;
    final icon = HugeIcon(
      icon: item.icon,
      color: active ? kPrimary : kTextMid,
      size: 22,
    );
    if (count <= 0) return icon;
    // Stack supaya badge bisa overlap icon di kanan-atas tanpa shift layout.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          top: -4,
          right: -8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            decoration: BoxDecoration(
              color: kDanger,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: kCard, width: 1.5),
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
