import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../app/app_routes.dart';
import '../../../app/theme.dart';
import '../../../app/theme_mode_provider.dart';
import '../../../core/app_icons.dart';
import '../../../core/i18n.dart';
import '../../../core/jenis_usaha.dart';
import '../../../core/responsive.dart';
import '../../access_rights/data/access_rights_repository.dart';
import '../../attendance/ui/attendance_page.dart';
import '../../billing/ui/billing_history_page.dart';
import '../../subscription/data/subscription_repository.dart';
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
import '../../settings/ui/offline_data_page.dart';
import '../../../core/offline/product_folder_store.dart';
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
import '../../user/domain/assignable_role.dart';
import '../../../shared/widgets/sheet_bawah.dart';

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

    final jenis = ref.jenisUsaha;

    List<Widget> grupKatalog() => [
      // Katalog: Menu (F&B) / Layanan (jasa) / Produk (retail).
      if ((ref.hasPermission(Permission.manageProducts) &&
              (ref.hasFeature('product_management') ||
                  ref.fiturTampil('modifiers'))) ||
          (ref.hasPermission(Permission.manageCategories) &&
              ref.hasFeature('product_management'))) ...[
        _Grup(
          judul: isEn ? 'Products' : jenis.judulGrupKatalog,
          children: [
            if (ref.hasPermission(Permission.manageProducts) &&
                ref.hasFeature('product_management'))
              _Tile(
                spec: _TileSpec(
                  id: 'products',
                  icon: AppIcons.inventory,
                  label: isEn
                      ? ref.t('profile.products')
                      : 'Manajemen ${jenis.sebutanKatalog}',
                  onTap: () => handleTap('products', AppRoutes.products),
                ),
                selected: selectedMenu == 'products',
              ),
            if (ref.hasPermission(Permission.manageCategories) &&
                ref.hasFeature('product_management'))
              _Tile(
                spec: _TileSpec(
                  id: 'categories',
                  icon: AppIcons.barChart,
                  label: isEn
                      ? ref.t('profile.categories')
                      : 'Kategori ${jenis.sebutanKatalog}',
                  onTap: () => handleTap('categories', AppRoutes.categories),
                ),
                selected: selectedMenu == 'categories',
              ),
            // Modifier & Add-on — kelola grup add-on (padanan menu web
            // /dashboard/modifiers). Push langsung agar konsisten di
            // phone & tablet tanpa panel detail khusus.
            if (ref.hasPermission(Permission.manageProducts) &&
                ref.fiturTampil('modifiers'))
              _Tile(
                spec: _TileSpec(
                  id: 'modifiers',
                  icon: AppIcons.discount,
                  label: isEn ? 'Modifiers & Add-ons' : jenis.sebutanModifier,
                  onTap: () => context.push(AppRoutes.modifiers),
                ),
                selected: selectedMenu == 'modifiers',
              ),
            // Bahan Baku & Resep (B1) — akses sama dengan kelola produk.
            if (ref.hasPermission(Permission.manageProducts) &&
                ref.fiturTampil('recipe_bom'))
              _Tile(
                spec: _TileSpec(
                  id: 'recipes',
                  icon: AppIcons.inventory,
                  label: 'Bahan Baku & Resep',
                  onTap: () => handleTap('recipes', AppRoutes.recipes),
                ),
                selected: selectedMenu == 'recipes',
              ),
          ],
        ),
      ],
    ];

    List<Widget> grupOps() => [
      // Operasional: meja & tipe pesanan hanya untuk usaha yang memakainya.
      if (role.canManageOutlets ||
          ref.hasPermission(Permission.managePrinter) ||
          ref.hasPermission(Permission.manageTax)) ...[
        _Grup(
          judul: isEn ? ref.t('profile.group_ops') : jenis.judulGrupOperasional,
          children: [
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
                          AppRoutes.outletsEdit.replaceAll(':id', outletId),
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
            if (ref.hasPermission(Permission.manageTax) &&
                ref.fiturTampil('order_types'))
              _Tile(
                spec: _TileSpec(
                  id: 'order_types',
                  icon: AppIcons.task,
                  label: ref.t('profile.order_types'),
                  onTap: () => handleTap('order_types', AppRoutes.orderTypes),
                ),
                selected: selectedMenu == 'order_types',
              ),
            if (ref.fiturTampil('table_management'))
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
            if (isManagement && ref.hasFeature('shift_management'))
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
            if (isManagement && ref.hasFeature('payment_methods'))
              _Tile(
                spec: _TileSpec(
                  id: 'payment_methods',
                  icon: AppIcons.money,
                  label: ref.t('profile.payments'),
                  onTap: () =>
                      handleTap('payment_methods', '/profil/payment-methods'),
                ),
                selected: selectedMenu == 'payment_methods',
              ),
          ],
        ),
      ],
    ];

    List<Widget> grupStok() => [
      // Stok & gudang.
      if (ref.hasPermission(Permission.manageProducts) &&
          (ref.hasFeature('inventory_tracking') ||
              ref.fiturTampil('stock_transfer'))) ...[
        _Grup(
          judul: isEn ? 'Stock & Warehouse' : 'Stok & Gudang',
          children: [
            // Inventori produk (C1) — cek/restock stok dari HP.
            if (ref.hasPermission(Permission.manageProducts) &&
                ref.hasFeature('inventory_tracking'))
              _Tile(
                spec: _TileSpec(
                  id: 'inventory',
                  icon: AppIcons.inventory,
                  label: 'Inventori',
                  onTap: () => handleTap('inventory', AppRoutes.inventory),
                ),
                selected: selectedMenu == 'inventory',
              ),
            // Transfer stok antar-outlet (B2) — server mengunci dengan
            // fitur stock_transfer; tak relevan untuk usaha jasa.
            if (ref.hasPermission(Permission.manageProducts) &&
                ref.fiturTampil('stock_transfer'))
              _Tile(
                spec: _TileSpec(
                  id: 'stock_transfer',
                  icon: AppIcons.storefront,
                  label: 'Transfer Stok',
                  onTap: () =>
                      handleTap('stock_transfer', AppRoutes.stockTransfer),
                ),
                selected: selectedMenu == 'stock_transfer',
              ),
          ],
        ),
      ],
    ];

    List<Widget> grupKaryawan() => [
      // Group 3: Karyawan & Hak Akses
      if ((role.canManageEmployees && ref.hasFeature('employee_management')) ||
          (isManagement && ref.hasFeature('rbac_permissions'))) ...[
        _Grup(
          judul: ref.t('profile.group_users'),
          children: [
            if (role.canManageEmployees &&
                ref.hasFeature('employee_management'))
              _Tile(
                spec: _TileSpec(
                  id: 'employees',
                  icon: AppIcons.person,
                  label: ref.t('profile.users'),
                  onTap: () => handleTap('employees', AppRoutes.employees),
                ),
                selected: selectedMenu == 'employees',
              ),
            if (isManagement && ref.hasFeature('rbac_permissions'))
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
          ],
        ),
      ],
    ];

    List<Widget> grupCrm() => [
      // Group 4: CRM & Pelanggan
      if (isManagement) ...[
        _Grup(
          judul: ref.t('profile.group_crm'),
          children: [
            if (ref.hasFeature('customer_crm'))
              _Tile(
                spec: _TileSpec(
                  id: 'customers',
                  icon: AppIcons.person,
                  label: ref.t('profile.customers'),
                  onTap: () => handleTap('customers', AppRoutes.customers),
                ),
                selected: selectedMenu == 'customers',
              ),
            if (ref.hasFeature('loyalty_program'))
              _Tile(
                spec: _TileSpec(
                  id: 'loyalty_settings',
                  icon: AppIcons.favorite,
                  label: ref.t('profile.loyalty'),
                  onTap: () => handleTap('loyalty_settings', AppRoutes.loyalty),
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
          ],
        ),
      ],
    ];

    Widget buildMenuPane() {
      return ListView(
        padding: EdgeInsets.symmetric(horizontal: horizontalPad, vertical: 0),
        children: [
          ContentConstrained(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Gap(12),
                _ProfileHeader(
                  initial: initial,
                  name: user?.name ?? '-',
                  // Nama peran dari server bila ada — role (UserRole) cuma
                  // keranjang izin berisi empat nilai untuk sepuluh peran,
                  // jadi ia menulis "Kasir" untuk enam peran yang berbeda.
                  roleLabel: (user?.roleName ?? '').isNotEmpty
                      ? labelPeran(user!.roleName)
                      : role.label,
                  outletName: outletName,
                  jenis: jenis,
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
                const Gap(20),

                // Urutan grup mengikuti jenis usaha outlet (lihat core/jenis_usaha):
                // retail mendahulukan stok, jasa mendahulukan pelanggan.
                for (final grup in switch (jenis) {
                  JenisUsaha.fnb => [
                    grupKatalog,
                    grupOps,
                    grupStok,
                    grupKaryawan,
                    grupCrm,
                  ],
                  JenisUsaha.retail => [
                    grupKatalog,
                    grupStok,
                    grupOps,
                    grupKaryawan,
                    grupCrm,
                  ],
                  JenisUsaha.jasa => [
                    grupKatalog,
                    grupOps,
                    grupCrm,
                    grupKaryawan,
                    grupStok,
                  ],
                  JenisUsaha.umum => [
                    grupKatalog,
                    grupStok,
                    grupOps,
                    grupKaryawan,
                    grupCrm,
                  ],
                })
                  ...grup(),

                // Group 5: Pengaturan Aplikasi
                _Grup(
                  judul: ref.t('profile.group_app'),
                  children: [
                    if (ref.hasPermission(Permission.manageTax) &&
                        ref.hasFeature('tax_service_charge'))
                      _Tile(
                        spec: _TileSpec(
                          id: 'tax',
                          icon: AppIcons.percent,
                          label: ref.t('profile.tax'),
                          onTap: () => handleTap('tax', AppRoutes.tax),
                        ),
                        selected: selectedMenu == 'tax',
                      ),
                    // Pengeluaran (C2) — parity dengan web; akses lihat laporan.
                    if (ref.hasPermission(Permission.viewReports))
                      _Tile(
                        spec: _TileSpec(
                          id: 'expenses',
                          icon: AppIcons.money,
                          label: 'Pengeluaran',
                          onTap: () =>
                              handleTap('expenses', AppRoutes.expenses),
                        ),
                        selected: selectedMenu == 'expenses',
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
                    // Data offline — semua role: kasir yang paling butuh katalog
                    // produk saat internet putus. Android saja (folder pilihan).
                    if (ref.read(productFolderStoreProvider).didukung)
                      _Tile(
                        spec: _TileSpec(
                          id: 'offline_data',
                          icon: AppIcons.folder,
                          label: 'Data Offline',
                          onTap: () =>
                              handleTap('offline_data', AppRoutes.offlineData),
                        ),
                        selected: selectedMenu == 'offline_data',
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
                    // check-in/out & lihat riwayat sendiri). Digating plan via
                    // fitur 'attendance'.
                    if (ref.hasFeature('attendance'))
                      _Tile(
                        spec: _TileSpec(
                          id: 'attendance',
                          icon: AppIcons.time,
                          label: 'Absensi',
                          onTap: () =>
                              handleTap('attendance', AppRoutes.attendance),
                        ),
                        selected: selectedMenu == 'attendance',
                      ),
                  ],
                ),
                _Grup(
                  children: [
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
                  ],
                ),
                const Gap(16),
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
        case 'offline_data':
          return const OfflineDataPage();
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

/// Satu grup menu: judul kecil + kartu berisi baris-baris menu yang
/// dipisah garis tipis (gaya pengaturan iOS/Android modern). Baris kosong
/// (menu yang disembunyikan) tak membuat garis ganda karena children sudah
/// disaring di pemanggil.
class _Grup extends StatelessWidget {
  final String? judul;
  final List<Widget> children;
  const _Grup({this.judul, required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (judul != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                judul!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kTextMid,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kDivider.withValues(alpha: 0.6)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 60,
                      color: kDivider.withValues(alpha: 0.6),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ikon menu dalam kotak berwarna lembut — dipakai semua baris menu supaya
/// tingginya seragam.
class _IkonMenu extends StatelessWidget {
  final Widget child;
  final Color warna;
  const _IkonMenu({required this.child, required this.warna});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// Baris menu: [ikon] Label ............ [nilai] ›
class _Baris extends StatelessWidget {
  final Widget ikon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final Color? warnaLabel;
  const _Baris({
    required this.ikon,
    required this.label,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.warnaLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kPrimary.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
            child: Row(
              children: [
                ikon,
                const Gap(12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: warnaLabel ?? (selected ? kPrimary : kTextDark),
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String initial;
  final String name;
  final String roleLabel;
  final String outletName;
  final JenisUsaha jenis;
  const _ProfileHeader({
    required this.initial,
    required this.name,
    required this.roleLabel,
    required this.outletName,
    required this.jenis,
  });

  @override
  Widget build(BuildContext context) {
    final ikonUsaha = switch (jenis) {
      JenisUsaha.fnb => Icons.restaurant_outlined,
      JenisUsaha.jasa => Icons.content_cut_outlined,
      _ => Icons.storefront_outlined,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: kPrimary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: kTextDark,
                        ),
                      ),
                    ),
                    const Gap(8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
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
                  ],
                ),
                const Gap(4),
                Row(
                  children: [
                    Icon(ikonUsaha, size: 14, color: kTextMid),
                    const Gap(4),
                    Flexible(
                      child: Text(
                        [
                          if (outletName.trim().isNotEmpty && outletName != '-')
                            outletName,
                          if (jenis != JenisUsaha.umum) 'Usaha ${jenis.nama}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: kTextMid),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
    final warna = danger ? kDanger : kPrimary;
    return _Baris(
      ikon: _IkonMenu(
        warna: warna,
        child: HugeIcon(icon: spec.icon, size: 18, color: warna),
      ),
      label: spec.label,
      onTap: spec.onTap,
      selected: selected,
      warnaLabel: danger ? kDanger : null,
      trailing: danger
          ? null
          : HugeIcon(
              icon: AppIcons.chevronRight,
              color: selected ? kPrimary : kTextLight,
              size: 18,
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
    final picked = await tampilkanSheetBawah<ThemeMode>(
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
    return _Baris(
      ikon: _IkonMenu(
        warna: kPrimary,
        child: Icon(_iconFor(currentMode), size: 18, color: kPrimary),
      ),
      label: 'Tema',
      onTap: () => _open(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _labelFor(currentMode),
            style: TextStyle(fontSize: 13, color: kTextMid),
          ),
          const Gap(4),
          HugeIcon(icon: AppIcons.chevronRight, color: kTextLight, size: 18),
        ],
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
    return _Baris(
      ikon: _IkonMenu(
        warna: kPrimary,
        child: HugeIcon(icon: AppIcons.language, size: 18, color: kPrimary),
      ),
      label: label,
      onTap: () => onChanged(!isEn),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isEn ? 'English' : 'Indonesia',
            style: TextStyle(fontSize: 13, color: kTextMid),
          ),
          const Gap(4),
          Transform.scale(
            scale: 0.85,
            child: Switch.adaptive(
              value: isEn,
              onChanged: onChanged,
              activeThumbColor: kPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
