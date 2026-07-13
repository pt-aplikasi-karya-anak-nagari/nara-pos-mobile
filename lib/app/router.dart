import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../features/access_rights/ui/access_rights_page.dart';
import '../features/billing/ui/billing_history_page.dart';
import '../features/user/data/auth_service.dart';
import '../features/user/ui/employee_form_page.dart';
import '../features/user/ui/employee_list_page.dart';
import '../features/user/ui/login_page.dart';
import '../features/kasir/ui/kasir_page.dart';
import '../features/laporan/ui/laporan_page.dart';
import '../features/outlet/ui/outlet_form_page.dart';
import '../features/outlet/ui/outlet_list_page.dart';
import '../features/printer/ui/printer_settings_page.dart';
import '../features/products/ui/category_list_page.dart';
import '../features/products/ui/product_form_page.dart';
import '../features/products/ui/product_list_page.dart';
import '../features/modifiers/ui/modifier_groups_page.dart';
import '../features/profil/ui/profil_page.dart';
import '../features/settings/ui/display_settings_page.dart';
import '../features/settings/ui/pin_settings_page.dart';
import '../features/settings/ui/tax_settings_page.dart';
import '../features/transactions/ui/riwayat_page.dart';
import '../features/transactions/ui/transaction_detail_page.dart';
import '../features/order_types/ui/order_type_list_page.dart';
import '../features/attendance/ui/attendance_page.dart';
import '../features/customers/ui/customer_list_page.dart';
import '../features/notifications/ui/notification_list_page.dart';
import '../features/customers/ui/customer_form_page.dart';
import '../features/customers/ui/customer_detail_page.dart';
import '../features/settings/ui/loyalty_settings_page.dart';
import '../features/bahan_baku/ui/bahan_baku_page.dart';
import '../features/bahan_baku/ui/stock_transfer_page.dart';
import '../features/expenses/ui/expenses_page.dart';
import '../features/inventory/ui/inventory_page.dart';
import '../features/tables/ui/table_management_page.dart';
import '../shared/widgets/main_shell.dart';
import 'app_routes.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.kasir,
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final authed = auth.isAuthenticated;
      final location = state.matchedLocation;
      final atLogin = location == AppRoutes.login;

      if (!authed && !atLogin) return AppRoutes.login;

      if (authed && atLogin) {
        return AppRoutes.kasir;
      }
      return null;
    },
    routes: [
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.login,
        name: AppRoutes.loginName,
        builder: (_, _) => const LoginPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.kasir,
                name: AppRoutes.kasirName,
                builder: (_, _) => const KasirPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.riwayat,
                name: AppRoutes.riwayatName,
                builder: (_, _) => const RiwayatPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.notifications,
                name: AppRoutes.notificationsName,
                builder: (_, _) => const NotificationListPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.laporan,
                name: AppRoutes.laporanName,
                builder: (_, _) => const LaporanPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profil,
                name: AppRoutes.profilName,
                builder: (_, _) => const ProfilPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.riwayatDetail,
        name: AppRoutes.riwayatDetailName,
        builder: (_, state) =>
            TransactionDetailPage(saleId: state.pathParameters['id']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.products,
        name: AppRoutes.productsName,
        builder: (_, state) {
          return ProductListPage(
            initialOutletId: state.uri.queryParameters['outletId'],
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.productsNew,
        name: AppRoutes.productsNewName,
        builder: (_, state) {
          return ProductFormPage(
            initialOutletId: state.uri.queryParameters['outletId'],
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.productsEdit,
        name: AppRoutes.productsEditName,
        builder: (_, state) =>
            ProductFormPage(productRemoteId: state.pathParameters['id']),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.categories,
        name: AppRoutes.categoriesName,
        builder: (_, _) => const CategoryListPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.categoriesNew,
        name: AppRoutes.categoriesNewName,
        builder: (_, _) => const CategoryListPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.categoriesEdit,
        name: AppRoutes.categoriesEditName,
        builder: (_, state) => CategoryListPage(
          // CategoryListPage now handles its own selection or we can pass initialId
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.modifiers,
        name: AppRoutes.modifiersName,
        builder: (_, _) => const ModifierGroupsPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.printer,
        name: AppRoutes.printerName,
        builder: (_, _) => const PrinterSettingsPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.tax,
        name: AppRoutes.taxName,
        builder: (_, _) => const TaxSettingsPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.display,
        name: AppRoutes.displayName,
        builder: (_, _) => const DisplaySettingsPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.pinSettings,
        name: AppRoutes.pinSettingsName,
        builder: (_, _) => const PinSettingsPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.outlets,
        name: AppRoutes.outletsName,
        builder: (_, _) => const OutletListPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.outletsNew,
        name: AppRoutes.outletsNewName,
        builder: (_, _) => const OutletFormPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.outletsEdit,
        name: AppRoutes.outletsEditName,
        builder: (_, state) =>
            OutletFormPage(remoteId: state.pathParameters['id']),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.employees,
        name: AppRoutes.employeesName,
        builder: (_, _) => const EmployeeListPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.employeesNew,
        name: AppRoutes.employeesNewName,
        builder: (_, _) => const EmployeeFormPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.employeesEdit,
        name: AppRoutes.employeesEditName,
        builder: (_, state) =>
            EmployeeFormPage(employeeId: state.pathParameters['id']),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.accessRights,
        name: AppRoutes.accessRightsName,
        builder: (_, _) => const AccessRightsPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.orderTypes,
        name: AppRoutes.orderTypesName,
        builder: (_, _) => const OrderTypeListPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.attendance,
        name: AppRoutes.attendanceName,
        builder: (_, _) => const AttendancePage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.customers,
        name: AppRoutes.customersName,
        builder: (_, _) => const CustomerListPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.customersNew,
        name: AppRoutes.customersNewName,
        builder: (_, _) => const CustomerFormPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.customersEdit,
        name: AppRoutes.customersEditName,
        builder: (_, state) =>
            CustomerFormPage(customerId: state.pathParameters['id']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.customersDetail,
        name: AppRoutes.customersDetailName,
        builder: (_, state) =>
            CustomerDetailPage(customerId: state.pathParameters['id']!),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.loyalty,
        name: AppRoutes.loyaltyName,
        builder: (_, _) => const LoyaltySettingsPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.recipes,
        name: AppRoutes.recipesName,
        builder: (_, _) => const BahanBakuPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.expenses,
        name: AppRoutes.expensesName,
        builder: (_, _) => const ExpensesPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.inventory,
        name: AppRoutes.inventoryName,
        builder: (_, _) => const InventoryPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.stockTransfer,
        name: AppRoutes.stockTransferName,
        builder: (_, _) => const StockTransferPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.billing,
        name: AppRoutes.billingName,
        builder: (_, _) => const BillingHistoryPage(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: AppRoutes.tables,
        name: AppRoutes.tablesName,
        builder: (_, _) => const TableManagementPage(),
      ),
    ],
  );
});

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
  }
}
