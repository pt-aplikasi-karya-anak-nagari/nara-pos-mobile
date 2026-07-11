import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:sizer/sizer.dart';
import '../../../app/app_routes.dart';
import '../../../app/theme.dart';
import '../../../app/theme_mode_provider.dart';
import '../../../core/app_icons.dart';
import '../../../core/i18n.dart';
import '../../../core/responsive.dart';
import '../../access_rights/data/access_rights_repository.dart';
import '../../attendance/ui/attendance_page.dart';
import '../../billing/ui/billing_history_page.dart';
import '../../subscription/ui/subscription_banner.dart';
import '../../access_rights/domain/permission.dart';
import '../../access_rights/ui/access_rights_page.dart';
import '../../user/data/auth_service.dart';
import '../../user/domain/user_role.dart';
import '../../user/ui/employee_list_page.dart';
import '../../../core/outlet_scope.dart';
import '../../outlet/ui/outlet_list_page.dart';
import '../../printer/ui/printer_settings_page.dart';
import '../../products/ui/category_list_page.dart';
import '../../products/ui/product_list_page.dart';
import '../../settings/ui/display_settings_page.dart';
import '../../settings/ui/pin_settings_page.dart';
import '../../settings/ui/tax_settings_page.dart';
import '../../order_types/ui/order_type_list_page.dart';
import '../../customers/ui/customer_list_page.dart';
import '../../settings/ui/loyalty_settings_page.dart';
import '../../tables/ui/table_management_page.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../../shifts/data/shift_repository.dart';
import '../../shifts/ui/shift_history_page.dart';
import '../../shifts/ui/shift_management_dialog.dart';
import '../../payments/ui/payment_method_management_page.dart';
import '../data/profil_state.dart';

class ProfilPage extends HookConsumerWidget {
  const ProfilPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTablet = context.isTablet;
    final selectedMenu = ref.watch(selectedProfileMenuProvider);
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final role = user?.role ?? UserRole.cashier;
    final isManagement = role != UserRole.cashier;
    final isEn = ref.watch(localeProvider) == AppLocale.en;

    String outletName = ref.watch(activeOutletProvider)?.name ?? '-';
    final initial = (user?.name.isNotEmpty ?? false)
        ? user!.name[0].toUpperCase()
        : '?';

    Future<void> confirmLogout() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: Text(ref.t('profile.logout_q')),
          content: Text(ref.t('profile.logout_msg')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(ref.t('common.cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text(
                ref.t('profile.logout'),
                style: const TextStyle(color: kDanger),
              ),
            ),
          ],
        ),
      );
      if (ok == true) {
        await ref.read(authProvider.notifier).logout();
      }
    }

    void handleTap(String id, String path) {
      if (isTablet) {
        final current = ref.read(selectedProfileMenuProvider);
        if (current == id) {
          ref.read(selectedProfileMenuProvider.notifier).state = null;
        } else {
          ref.read(selectedProfileMenuProvider.notifier).state = id;
        }
      } else {
        context.push(path);
      }
    }

    final horizontalPad = isTablet
        ? 16.0
        : context.responsive<double>(
            compact: 20,
            medium: 24,
            expanded: 28,
            large: 32,
          );

    Widget buildMenuPane() {
      return ListView(
        padding: EdgeInsets.symmetric(horizontal: horizontalPad, vertical: 0),
        children: [
          ContentConstrained(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProfileHeader(
                  initial: initial,
                  name: user?.name ?? '-',
                  username: user?.username ?? '-',
                  roleLabel: role.label,
                  outletName: outletName,
                ),
                const Gap(12),
                // Info langganan ditampilkan HANYA di halaman profil ini —
                // bukan sebagai banner global di semua halaman. removePadding
                // membatalkan SafeArea-top milik banner (yang hanya relevan
                // saat dia di paling atas layar).
                MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: const SubscriptionBanner(),
                  ),
                ),
                const Gap(24),

                // Group 1: Produk & Inventori
                if (ref.hasPermission(Permission.manageProducts) ||
                    ref.hasPermission(Permission.manageCategories)) ...[
                  _SectionHeader(label: ref.t('profile.group_products')),
                  if (ref.hasPermission(Permission.manageProducts))
                    _Tile(
                      spec: _TileSpec(
                        id: 'products',
                        icon: AppIcons.inventory,
                        label: ref.t('profile.products'),
                        onTap: () => handleTap('products', AppRoutes.products),
                      ),
                      selected: selectedMenu == 'products',
                    ),
                  if (ref.hasPermission(Permission.manageCategories))
                    _Tile(
                      spec: _TileSpec(
                        id: 'categories',
                        icon: AppIcons.barChart,
                        label: ref.t('profile.categories'),
                        onTap: () =>
                            handleTap('categories', AppRoutes.categories),
                      ),
                      selected: selectedMenu == 'categories',
                    ),
                  // Modifier & Add-on — kelola grup add-on (padanan menu web
                  // /dashboard/modifiers). Push langsung agar konsisten di
                  // phone & tablet tanpa panel detail khusus.
                  if (ref.hasPermission(Permission.manageProducts))
                    _Tile(
                      spec: _TileSpec(
                        id: 'modifiers',
                        icon: AppIcons.discount,
                        label: 'Modifier & Add-on',
                        onTap: () => context.push(AppRoutes.modifiers),
                      ),
                      selected: selectedMenu == 'modifiers',
                    ),
                  const Gap(16),
                ],

                // Group 2: Operasional Toko
                if (role.canManageOutlets ||
                    ref.hasPermission(Permission.managePrinter) ||
                    ref.hasPermission(Permission.manageTax)) ...[
                  _SectionHeader(label: ref.t('profile.group_ops')),
                  if (role.canManageOutlets)
                    _Tile(
                      spec: _TileSpec(
                        id: 'outlets',
                        icon: AppIcons.storefront,
                        label: isManagement
                            ? 'Pengaturan Outlet'
                            : ref.t('profile.outlets'),
                        onTap: () {
                          if (isManagement) {
                            final outletId = ref.read(activeOutletIdProvider);
                            if (outletId != null) {
                              handleTap(
                                'outlets',
                                AppRoutes.outletsEdit.replaceAll(
                                  ':id',
                                  outletId,
                                ),
                              );
                            } else {
                              handleTap('outlets', AppRoutes.outlets);
                            }
                          } else {
                            handleTap('outlets', AppRoutes.outlets);
                          }
                        },
                      ),
                      selected: selectedMenu == 'outlets',
                    ),
                  if (ref.hasPermission(Permission.manageTax))
                    _Tile(
                      spec: _TileSpec(
                        id: 'order_types',
                        icon: AppIcons.task,
                        label: ref.t('profile.order_types'),
                        onTap: () =>
                            handleTap('order_types', AppRoutes.orderTypes),
                      ),
                      selected: selectedMenu == 'order_types',
                    ),
                  _Tile(
                    spec: _TileSpec(
                      id: 'tables',
                      icon: AppIcons.storefront,
                      label: ref.t('profile.tables'),
                      onTap: () => handleTap('tables', AppRoutes.tables),
                    ),
                    selected: selectedMenu == 'tables',
                  ),
                  if (ref.hasPermission(Permission.managePrinter))
                    _Tile(
                      spec: _TileSpec(
                        id: 'printer',
                        icon: AppIcons.printer,
                        label: ref.t('profile.print'),
                        onTap: () => handleTap('printer', AppRoutes.printer),
                      ),
                      selected: selectedMenu == 'printer',
                    ),
                  if (isManagement) ...[
                    _Tile(
                      spec: _TileSpec(
                        id: 'shift_history',
                        icon: AppIcons.time,
                        label: ref.t('profile.shifts'),
                        onTap: () =>
                            handleTap('shift_history', '/profil/shift-history'),
                      ),
                      selected: selectedMenu == 'shift_history',
                    ),
                    _Tile(
                      spec: _TileSpec(
                        id: 'payment_methods',
                        icon: AppIcons.money,
                        label: ref.t('profile.payments'),
                        onTap: () => handleTap(
                          'payment_methods',
                          '/profil/payment-methods',
                        ),
                      ),
                      selected: selectedMenu == 'payment_methods',
                    ),
                  ],
                  const Gap(16),
                ],

                // Group 3: Karyawan & Hak Akses
                if (role.canManageEmployees || isManagement) ...[
                  _SectionHeader(label: ref.t('profile.group_users')),
                  if (role.canManageEmployees)
                    _Tile(
                      spec: _TileSpec(
                        id: 'employees',
                        icon: AppIcons.person,
                        label: ref.t('profile.users'),
                        onTap: () =>
                            handleTap('employees', AppRoutes.employees),
                      ),
                      selected: selectedMenu == 'employees',
                    ),
                  if (isManagement)
                    _Tile(
                      spec: _TileSpec(
                        id: 'access_rights',
                        icon: AppIcons.accessRights,
                        label: ref.t('profile.access_rights'),
                        onTap: () =>
                            handleTap('access_rights', AppRoutes.accessRights),
                      ),
                      selected: selectedMenu == 'access_rights',
                    ),
                  const Gap(16),
                ],

                // Group 4: CRM & Pelanggan
                if (isManagement) ...[
                  _SectionHeader(label: ref.t('profile.group_crm')),
                  _Tile(
                    spec: _TileSpec(
                      id: 'customers',
                      icon: AppIcons.person,
                      label: ref.t('profile.customers'),
                      onTap: () => handleTap('customers', AppRoutes.customers),
                    ),
                    selected: selectedMenu == 'customers',
                  ),
                  _Tile(
                    spec: _TileSpec(
                      id: 'loyalty_settings',
                      icon: AppIcons.favorite,
                      label: ref.t('profile.loyalty'),
                      onTap: () =>
                          handleTap('loyalty_settings', AppRoutes.loyalty),
                    ),
                    selected: selectedMenu == 'loyalty_settings',
                  ),
                  _Tile(
                    spec: _TileSpec(
                      id: 'billing',
                      icon: AppIcons.receiptLong,
                      label: 'Billing History',
                      onTap: () => handleTap('billing', AppRoutes.billing),
                    ),
                    selected: selectedMenu == 'billing',
                  ),
                  const Gap(16),
                ],

                // Group 5: Pengaturan Aplikasi
                _SectionHeader(label: ref.t('profile.group_app')),
                if (ref.hasPermission(Permission.manageTax))
                  _Tile(
                    spec: _TileSpec(
                      id: 'tax',
                      icon: AppIcons.percent,
                      label: ref.t('profile.tax'),
                      onTap: () => handleTap('tax', AppRoutes.tax),
                    ),
                    selected: selectedMenu == 'tax',
                  ),
                // Bahan Baku & Resep (B1) — akses sama dengan kelola produk.
                if (ref.hasPermission(Permission.manageProducts))
                  _Tile(
                    spec: _TileSpec(
                      id: 'recipes',
                      icon: AppIcons.inventory,
                      label: 'Bahan Baku & Resep',
                      onTap: () => handleTap('recipes', AppRoutes.recipes),
                    ),
                    selected: selectedMenu == 'recipes',
                  ),
                // Pengeluaran (C2) — parity dengan web; akses lihat laporan.
                if (ref.hasPermission(Permission.viewReports))
                  _Tile(
                    spec: _TileSpec(
                      id: 'expenses',
                      icon: AppIcons.money,
                      label: 'Pengeluaran',
                      onTap: () => handleTap('expenses', AppRoutes.expenses),
                    ),
                    selected: selectedMenu == 'expenses',
                  ),
                // Inventori produk (C1) — cek/restock stok dari HP.
                if (ref.hasPermission(Permission.manageProducts))
                  _Tile(
                    spec: _TileSpec(
                      id: 'inventory',
                      icon: AppIcons.inventory,
                      label: 'Inventori',
                      onTap: () => handleTap('inventory', AppRoutes.inventory),
                    ),
                    selected: selectedMenu == 'inventory',
                  ),
                // Tampilan card produk (toggle "Terjual: N"). Akses sama
                // dengan tax — owner / admin outlet.
                if (ref.hasPermission(Permission.manageTax))
                  _Tile(
                    spec: _TileSpec(
                      id: 'display',
                      icon: AppIcons.fire,
                      label: ref.t('profile.display'),
                      onTap: () => handleTap('display', AppRoutes.display),
                    ),
                    selected: selectedMenu == 'display',
                  ),
                // PIN Otorisasi — self-service, semua role bisa menyetel PIN
                // miliknya untuk mengesahkan void/refund (POST /me/pin).
                _Tile(
                  spec: _TileSpec(
                    id: 'pin_settings',
                    icon: AppIcons.accessRights,
                    label: 'PIN Otorisasi',
                    onTap: () =>
                        handleTap('pin_settings', AppRoutes.pinSettings),
                  ),
                  selected: selectedMenu == 'pin_settings',
                ),
                _LanguageTile(
                  isEn: isEn,
                  label: ref.t('profile.language'),
                  onChanged: (v) => ref
                      .read(localeProvider.notifier)
                      .set(v ? AppLocale.en : AppLocale.id),
                ),
                // Tile pilih tema: Sistem / Terang / Gelap.
                _ThemeTile(
                  currentMode: ref.watch(themeModeProvider),
                  onChanged: (m) =>
                      ref.read(themeModeProvider.notifier).setMode(m),
                ),
                // Absensi pegawai — semua role bisa akses (untuk
                // check-in/out & lihat riwayat sendiri).
                _Tile(
                  spec: _TileSpec(
                    id: 'attendance',
                    icon: AppIcons.time,
                    label: 'Absensi',
                    onTap: () => handleTap('attendance', AppRoutes.attendance),
                  ),
                  selected: selectedMenu == 'attendance',
                ),
                if (ref.watch(activeShiftProvider).value != null)
                  _Tile(
                    spec: _TileSpec(
                      id: 'close_shift',
                      icon: AppIcons.logout,
                      label: ref.t('profile.close_shift'),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) =>
                              const ShiftManagementDialog(isClosing: true),
                        );
                      },
                    ),
                    danger: true,
                  ),
                _Tile(
                  spec: _TileSpec(
                    id: 'logout',
                    icon: AppIcons.logout,
                    label: ref.t('profile.logout'),
                    onTap: confirmLogout,
                  ),
                  danger: true,
                ),
                const Gap(32),
              ],
            ),
          ),
        ],
      );
    }

    Widget buildDetailPane() {
      switch (selectedMenu) {
        case 'products':
          return const ProductListPage();
        case 'categories':
          return const CategoryListPage();
        case 'outlets':
          return const OutletListPage();
        case 'employees':
          return const EmployeeListPage();
        case 'access_rights':
          return const AccessRightsPage();
        case 'printer':
          return const PrinterSettingsPage();
        case 'tax':
          return const TaxSettingsPage();
        case 'display':
          return const DisplaySettingsPage();
        case 'pin_settings':
          return const PinSettingsPage();
        case 'order_types':
          return const OrderTypeListPage();
        case 'tables':
          return const TableManagementPage();
        case 'customers':
          return const CustomerListPage();
        case 'loyalty_settings':
          return const LoyaltySettingsPage();
        case 'billing':
          return const BillingHistoryPage();
        case 'shift_history':
          return const ShiftHistoryPage();
        case 'payment_methods':
          return const PaymentMethodManagementPage();
        case 'attendance':
          return const AttendancePage();
        default:
          return TabletDetailEmptyState(
            icon: AppIcons.person,
            title: ref.t('profile.title'),
            subtitle: ref.t('profile.empty_detail'),
          );
      }
    }

    if (isTablet) {
      final menuWidth = context.responsive<double>(
        compact: 300,
        medium: 340,
        expanded: 360,
        large: 380,
      );

      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Row(
            children: [
              SizedBox(width: menuWidth, child: buildMenuPane()),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16, right: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: buildDetailPane(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(child: buildMenuPane()),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9.sp,
          fontWeight: FontWeight.w800,
          color: kTextMid,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String initial;
  final String name;
  final String username;
  final String roleLabel;
  final String outletName;
  const _ProfileHeader({
    required this.initial,
    required this.name,
    required this.username,
    required this.roleLabel,
    required this.outletName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            width: 5.w,
            height: 5.w,
            decoration: BoxDecoration(
              color: kPrimary,
              borderRadius: BorderRadius.circular(5.w),
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const Gap(12),
          Text(
            name,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.sp,
              color: kTextDark,
            ),
          ),
          const Gap(2),
          Text('@$username', style: TextStyle(fontSize: 12, color: kTextMid)),
          const Gap(8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  roleLabel,
                  style: const TextStyle(
                    color: kPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: kBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  outletName,
                  style: TextStyle(
                    color: kTextMid,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TileSpec {
  final String id;
  final IconAsset icon;
  final String label;
  final VoidCallback onTap;
  const _TileSpec({
    required this.id,
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _Tile extends StatelessWidget {
  final _TileSpec spec;
  final bool danger;
  final bool selected;
  const _Tile({required this.spec, this.danger = false, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? kDanger : (selected ? kPrimary : kTextMid);
    final textColor = danger ? kDanger : (selected ? kPrimary : kTextDark);
    final bgColor = selected ? kPrimary.withValues(alpha: 0.1) : kCard;
    final borderColor = selected
        ? kPrimary.withValues(alpha: 0.3)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: spec.onTap,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: 1.5),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  HugeIcon(icon: spec.icon, size: 20, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      spec.label,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!danger)
                    HugeIcon(
                      icon: AppIcons.chevronRight,
                      color: selected ? kPrimary : kTextMid,
                      size: 20,
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

/// Tile selektor tema: tap row → buka bottom sheet pilih Sistem/Terang/Gelap.
/// Indikator value saat ini muncul di sisi kanan.
class _ThemeTile extends StatelessWidget {
  final ThemeMode currentMode;
  final ValueChanged<ThemeMode> onChanged;
  const _ThemeTile({required this.currentMode, required this.onChanged});

  String _labelFor(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'Terang';
      case ThemeMode.dark:
        return 'Gelap';
      case ThemeMode.system:
        return 'Sistem';
    }
  }

  IconData _iconFor(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
    }
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          top: 12,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: kDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Pilih Tema',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: kTextDark,
                    ),
                  ),
                ],
              ),
            ),
            const Gap(8),
            for (final m in ThemeMode.values)
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: currentMode == m
                        ? kPrimary.withValues(alpha: 0.12)
                        : kBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _iconFor(m),
                    color: currentMode == m ? kPrimary : kTextMid,
                  ),
                ),
                title: Text(
                  _labelFor(m),
                  style: TextStyle(
                    color: kTextDark,
                    fontWeight: currentMode == m
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                subtitle: m == ThemeMode.system
                    ? Text(
                        'Ikuti pengaturan sistem',
                        style: TextStyle(color: kTextMid),
                      )
                    : null,
                trailing: currentMode == m
                    ? const Icon(Icons.check_circle, color: kPrimary)
                    : null,
                onTap: () => Navigator.pop(context, m),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(_iconFor(currentMode), size: 20, color: kTextMid),
              const SizedBox(width: 12),
              Text(
                'Tema',
                style: TextStyle(fontWeight: FontWeight.w500, color: kTextDark),
              ),
              const Spacer(),
              Text(
                _labelFor(currentMode),
                style: TextStyle(
                  fontSize: 12,
                  color: kTextMid,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: kTextMid, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  final bool isEn;
  final String label;
  final ValueChanged<bool> onChanged;
  const _LanguageTile({
    required this.isEn,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            HugeIcon(icon: AppIcons.language, size: 20, color: kTextMid),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w500, color: kTextDark),
            ),
            const Spacer(),
            Text(
              isEn ? 'EN' : 'ID',
              style: TextStyle(
                fontSize: 12,
                color: kTextMid,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: isEn,
              onChanged: onChanged,
              activeThumbColor: kPrimary,
            ),
          ],
        ),
      ),
    );
  }
}
