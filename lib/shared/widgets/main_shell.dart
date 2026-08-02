import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../app/theme.dart';
import '../../core/app_icons.dart';
import '../../core/i18n.dart';
import '../../core/responsive.dart';
import '../../features/drafts/providers.dart';
import '../../features/drafts/ui/draft_list_sheet.dart';
import '../../features/kasir/scan_trigger.dart';
import '../../features/kasir/ui/kasir_page.dart';
import '../../features/kasir/ui/widgets/dialog_kalkulator.dart';
import '../../features/notifications/data/notification_history.dart';
import 'wadah_branch_beranimasi.dart';
import '../../features/tables/ui/table_management_page.dart';
import '../../features/profil/data/profil_state.dart';
import '../../features/user/data/auth_service.dart';
import '../../features/user/domain/user_role.dart';
import 'sheet_bawah.dart';

class NavItem {
  final IconAsset icon;
  final String labelKey;
  final int branch;

  /// Opsional. Bila di-set, badge angka muncul di sudut kanan-atas icon —
  /// di-watch reactive lewat WidgetRef. Return 0 = badge hidden.
  final int Function(WidgetRef ref)? badgeBuilder;
  const NavItem({
    required this.icon,
    required this.labelKey,
    this.branch = -1,
    this.badgeBuilder,
  });
}

/// Indeks branch tiap tab, HARUS sama dengan urutan StatefulShellBranch di
/// app/router.dart.
///
/// # KENAPA KONSTANTA, BUKAN ANGKA DI TEMPATNYA
///
/// Angkanya muncul di dua tempat — daftar tab di bawah dan pemeriksaan di
/// _onTap — dan pernah menyimpang: tab Profil menunjuk branch 4 sementara
/// router hanya punya branch 0..3. goBranch(4) di luar jangkauan, jadi menekan
/// Profil tidak melakukan apa-apa. Sorotan tab pun ikut salah: currentBranch 3
/// tak cocok dengan item mana pun, indexWhere mengembalikan -1, dan jatuh ke
/// tab Kasir.
///
/// Tak satu pun dari keduanya menimbulkan galat yang terlihat.
const int branchKasir = 0;
const int branchRiwayat = 1;
const int branchNotifikasi = 2;
const int branchProfil = 3;

/// Tab yang tampil di bilah bawah, berurutan.
///
/// Berada di tingkat atas supaya bisa diperiksa tes tanpa membangun MainShell
/// beserta seluruh pohon widget-nya.
List<NavItem> navItemsUtama(UserRole role) {
  return [
    const NavItem(
      icon: AppIcons.storefront,
      labelKey: 'nav.kasir',
      branch: branchKasir,
    ),
    const NavItem(
      icon: AppIcons.receiptLong,
      labelKey: 'nav.riwayat',
      branch: branchRiwayat,
    ),
    NavItem(
      icon: AppIcons.notification,
      labelKey: 'nav.notifikasi',
      branch: branchNotifikasi,
      badgeBuilder: (ref) => ref.watch(unreadNotificationCountProvider),
    ),
    const NavItem(
      icon: AppIcons.person,
      labelKey: 'nav.profil',
      branch: branchProfil,
    ),
  ];
}

class MainShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const MainShell({super.key, required this.navigationShell});

  List<NavItem> _getVisibleItems(UserRole role) => navItemsUtama(role);

  void _onTap(int visualIndex, List<NavItem> items, WidgetRef ref) {
    final item = items[visualIndex];
    final branch = item.branch;

    // Reset state profil saat pindah tab — baik masuk tab profil (supaya
    // mulai dari menu utama, bukan submenu terakhir) maupun keluar
    // (supaya saat kembali, fresh state). Selalu reset, jadi logika
    // if-else di sini cuma untuk dokumentasi maksud.
    if (branch == branchProfil) {
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

    // Auto-hide-saat-scroll DIHAPUS, bukan dipindahkan.
    //
    // Controller-nya ada dan digerakkan maju-mundur oleh ScrollNotification,
    // tapi NILAINYA tak pernah dipakai menganimasikan apa pun — tak ada
    // AnimatedBuilder, SlideTransition, atau SizeTransition yang membacanya.
    // Jadi selama ini ia hanya membakar satu ticker per frame scroll tanpa
    // pernah menyembunyikan apa pun.
    //
    // Dengan navigasi pindah ke sisi kanan, menyembunyikannya pun tak lagi ada
    // gunanya: yang langka di layar melintang adalah ruang TEGAK, dan rail di
    // samping justru mengembalikannya.
    final currentBranch = navigationShell.currentIndex;

    // Find visual index that matches current branch
    int activeVisualIndex = visibleItems.indexWhere(
      (item) => item.branch == currentBranch,
    );
    // Fallback if current branch is not in visible items (e.g. redirected)
    if (activeVisualIndex == -1) activeVisualIndex = 0;

    // Rail di kanan untuk layar 600 dp ke atas; bilah bawah untuk ponsel
    // sempit.
    //
    // # KENAPA TIDAK SELALU DI KANAN
    //
    // Di ponsel 360 dp, rail selebar 88 dp memakan seperempat lebar layar —
    // dan lebar itulah yang menentukan berapa kartu produk muat sebaris. Yang
    // langka di ponsel tegak adalah lebar; yang langka di tablet melintang
    // adalah tinggi. Jadi navigasinya mengambil dari sisi yang lapang.
    //
    // 600 dp juga titik saat ponsel dimiringkan jadi melintang — di sana rail
    // sudah menguntungkan, karena tingginya tinggal ~360 dp.
    final pakaiRail = context.pakaiRailNavigasi;

    final isi = Stack(
      children: [
        Positioned.fill(
          child: Image.asset('assets/images/bg.jpg', fit: BoxFit.cover),
        ),
        Positioned.fill(child: Container(color: kBg.withValues(alpha: 0.85))),
        navigationShell,
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: pakaiRail
          ? Row(
              children: [
                Expanded(child: isi),
                RailKanan(
                  items: visibleItems,
                  aktif: activeVisualIndex,
                  onTap: (i) => _onTap(i, visibleItems, ref),
                  // Aksi cepat hanya di tab Kasir. Di tab lain ia tak punya
                  // makna — membuka sheet "Custom Order" dari halaman Profil
                  // hanya membingungkan.
                  tampilkanAksi: currentBranch == branchKasir,
                ),
              ],
            )
          : isi,
      bottomNavigationBar: pakaiRail
          ? null
          : BilahBawah(
              items: visibleItems,
              aktif: activeVisualIndex,
              isTablet: isTablet,
              onTap: (i) => _onTap(i, visibleItems, ref),
            ),
    );
  }
}

/// Navigasi di tepi KANAN layar, untuk layar 600 dp ke atas.
///
/// Kanan, bukan kiri: di tablet yang dipegang dua tangan, ibu jari kanan yang
/// paling sering dipakai kasir — dan panel keranjang memang sudah di sisi itu,
/// jadi perpindahan pandangnya pendek.
class RailKanan extends ConsumerWidget {
  final List<NavItem> items;
  final int aktif;
  final ValueChanged<int> onTap;
  final bool tampilkanAksi;

  const RailKanan({
    super.key,
    required this.items,
    required this.aktif,
    required this.onTap,
    this.tampilkanAksi = false,
  });

  static const double lebar = 88;
  static const double tinggiItem = 68;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Colors.black.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
      ),
      position: DecorationPosition.foreground,
      child: Container(
        width: lebar,
        color: kCard,
        child: SafeArea(
          left: false,
          // Digulir: aksi cepat + tujuan = 8 baris. Di ponsel yang dimiringkan
          // (tinggi ~360 dp) itu tak muat, dan tanpa gulir yang di bawah — tab
          // Profil — jadi tak terjangkau sama sekali.
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    MediaQuery.sizeOf(context).height -
                    MediaQuery.paddingOf(context).vertical,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // AnimatedSize + AnimatedOpacity: saat kasir berpindah ke
                  // tab lain, empat aksi ini menyusut dan memudar alih-alih
                  // lenyap seketika. Tanpa itu, keempat tujuan navigasi
                  // MELOMPAT ke atas dalam satu frame — dan jari yang sudah
                  // mengarah ke "Riwayat" mendarat di tombol lain.
                  AnimatedSize(
                    duration: WadahBranchBeranimasi.durasi,
                    curve: Curves.easeOut,
                    alignment: Alignment.bottomCenter,
                    child: AnimatedOpacity(
                      opacity: tampilkanAksi ? 1 : 0,
                      duration: WadahBranchBeranimasi.durasi,
                      curve: Curves.easeOut,
                      child: tampilkanAksi
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final aksi in _aksiCepat(context, ref))
                                  SizedBox(
                                    height: tinggiItem,
                                    width: lebar,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: aksi,
                                    ),
                                  ),
                                // Pemisah: aksi cepat mengubah PESANAN yang
                                // sedang dibuat, tujuan navigasi memindahkan
                                // HALAMAN. Dua jenis yang berbeda, dan garis
                                // ini yang membedakannya sekilas pandang.
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 8,
                                  ),
                                  child: Divider(
                                    height: 1,
                                    color: Colors.black.withValues(alpha: 0.08),
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox(width: lebar),
                    ),
                  ),
                  for (var i = 0; i < items.length; i++)
                    SizedBox(
                      height: tinggiItem,
                      width: lebar,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: _TombolNav(
                          item: items[i],
                          aktif: i == aktif,
                          onTap: () => onTap(i),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Aksi cepat yang dulu berada di header biru layar Kasir.
///
/// Dipindahkan ke rail supaya header tak lagi menampung dua jenis kendali
/// sekaligus, dan supaya di layar melintang keduanya tak berebut tinggi.
///
/// Handler-nya hidup DI SINI, bukan dioper dari KasirPage. Rail ini berada di
/// luar sub-pohon KasirPage, jadi mengopernya berarti KasirPage harus
/// mendaftarkan callback-nya ke suatu provider dan mencabutnya saat dilepas —
/// daur hidup yang gampang bocor. Yang dibutuhkan aksi ini hanya context dan
/// ref, dan keduanya sudah ada di sini.
List<Widget> _aksiCepat(BuildContext context, WidgetRef ref) {
  return [
    _TombolAksi(
      icon: AppIcons.scan,
      label: 'Scan',
      onTap: () => ref.read(scanTriggerProvider.notifier).trigger(),
    ),
    _TombolAksi(
      icon: HugeIcons.strokeRoundedCalculator,
      label: 'Hitung',
      labelPanjang: 'Kalkulator',
      // Dialog, bukan halaman: kasir memakainya sambil keranjang tetap di
      // layar, dan menutupnya tak boleh mengubah apa pun di belakangnya.
      onTap: () => showDialog(
        context: context,
        builder: (_) => const DialogKalkulator(),
      ),
    ),
    _TombolAksi(
      icon: AppIcons.add,
      label: 'Custom',
      labelPanjang: 'Custom Order',
      onTap: () => tampilkanSheetBawah(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const CustomOrderSheet(),
      ),
    ),
    _TombolAksi(
      icon: HugeIcons.strokeRoundedTable02,
      label: 'Meja',
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: context.isTablet ? 1100 : 500,
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: const TableManagementPage(isReadOnly: true),
          ),
        ),
      ),
    ),
    _TombolAksi(
      icon: AppIcons.task,
      label: 'Draft',
      lencana: (r) => r.watch(draftsCountProvider),
      onTap: () => tampilkanSheetBawah(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const DraftListSheet(),
      ),
    ),
  ];
}

/// Satu tombol aksi cepat di rail. Bentuknya sengaja mirip tombol navigasi
/// supaya sentuhannya terasa sama, tapi warnanya netral — ia bukan tujuan, jadi
/// tak pernah "aktif".
class _TombolAksi extends ConsumerWidget {
  final IconAsset icon;
  final String label;
  final String? labelPanjang;
  final int Function(WidgetRef)? lencana;
  final VoidCallback onTap;

  const _TombolAksi({
    required this.icon,
    required this.label,
    required this.onTap,
    this.labelPanjang,
    this.lencana,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jumlah = lencana?.call(ref) ?? 0;
    return Semantics(
      button: true,
      label: labelPanjang ?? label,
      child: GestureDetector(
        key: ValueKey('aksi-$label'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                HugeIcon(icon: icon, color: kTextDark, size: 22),
                if (jumlah > 0)
                  Positioned(
                    top: -4,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      decoration: BoxDecoration(
                        color: kPrimary,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: kCard, width: 1.5),
                      ),
                      child: Text(
                        jumlah > 99 ? '99+' : '$jumlah',
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
            ),
            const Gap(3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: kTextMid,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bilah navigasi di bawah, untuk ponsel sempit.
class BilahBawah extends ConsumerWidget {
  final List<NavItem> items;
  final int aktif;
  final bool isTablet;
  final ValueChanged<int> onTap;

  const BilahBawah({
    super.key,
    required this.items,
    required this.aktif,
    required this.isTablet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DecoratedBox(
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
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _TombolNav(
                        item: items[i],
                        aktif: i == aktif,
                        onTap: () => onTap(i),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Satu tombol navigasi — bentuknya sama untuk rail maupun bilah bawah.
///
/// Sorotannya kini menempel pada tombolnya sendiri, bukan pil melayang yang
/// digeser AnimatedPositioned. Pil itu posisinya dihitung dari lebar layar dan
/// jumlah item; untuk rail ia harus dihitung ulang dari TINGGI — dua rumus
/// untuk satu hal yang sama, dan yang satu pasti akan lupa diperbarui.
class _TombolNav extends ConsumerWidget {
  final NavItem item;
  final bool aktif;
  final VoidCallback onTap;

  const _TombolNav({
    required this.item,
    required this.aktif,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      selected: aktif,
      label: ref.t(item.labelKey),
      child: GestureDetector(
        // Key stabil: teks yang tampil ikut bahasa aktif, jadi mencari tombol
        // lewat teksnya membuat tesnya pecah begitu terjemahannya diubah.
        key: ValueKey('nav-${item.labelKey}'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: aktif ? kPrimary.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: aktif ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: _NavIconWithBadge(item: item, active: aktif),
              ),
              const Gap(3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: aktif ? FontWeight.w700 : FontWeight.w400,
                  color: aktif ? kPrimary : kTextMid,
                ),
                child: Text(
                  ref.t(item.labelKey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
  final NavItem item;
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
