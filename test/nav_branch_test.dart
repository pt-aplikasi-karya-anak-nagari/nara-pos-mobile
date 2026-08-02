import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nara_pos_mobile/app/app_routes.dart';
import 'package:nara_pos_mobile/app/router.dart';
import 'package:nara_pos_mobile/features/user/data/auth_service.dart';
import 'package:nara_pos_mobile/features/user/domain/user_role.dart';
import 'package:nara_pos_mobile/shared/widgets/main_shell.dart';

// Indeks branch tiap tab di bilah bawah.
//
// # KEJADIANNYA
//
// Tab Profil menunjuk `branch: 4`, sementara router hanya punya branch 0..3.
// Akibatnya dua-duanya, dan tak satu pun menimbulkan galat yang terlihat:
//
//   menekan Profil    goBranch(4) di luar jangkauan → tidak terjadi apa-apa.
//                     Kasir menekan berkali-kali dan menyimpulkan aplikasinya
//                     hang, padahal seluruh layar lain berfungsi normal.
//
//   sorotan tab       Saat benar-benar berada di Profil, currentBranch = 3 tak
//                     cocok dengan item mana pun; indexWhere mengembalikan -1
//                     dan jatuh ke 0, jadi pil sorotan menempel di Kasir.
//
// # KENAPA DIUJI TERHADAP ROUTER SUNGGUHAN
//
// Memeriksa "branch-nya 0,1,2,3" saja tak cukup: yang benar-benar menentukan
// adalah URUTAN StatefulShellBranch di app/router.dart. Menukar dua branch di
// sana tanpa menukar tab-nya akan lolos dari pemeriksaan angka, tapi menekan
// Riwayat akan membuka Notifikasi.
//
// Karena itu tes ini membangun router yang sebenarnya dan mencocokkan tiap tab
// dengan PATH branch tujuannya.

/// AuthNotifier tiruan — build() aslinya membaca penyimpanan aman yang tak ada
/// di lingkungan tes. Yang diuji di sini bentuk rutenya, bukan otentikasinya.
class _AuthDiam extends AuthNotifier {
  @override
  AuthState build() => const AuthState();
}

/// Path branch ke-n dari StatefulShellRoute pertama di konfigurasi router.
List<String> pathTiapBranch(GoRouter router) {
  final shell = router.configuration.routes.whereType<StatefulShellRoute>().first;
  return shell.branches
      .map((b) => (b.routes.first as GoRoute).path)
      .toList(growable: false);
}

void main() {
  late ProviderContainer container;
  late GoRouter router;

  setUp(() {
    container = ProviderContainer(
      overrides: [authProvider.overrideWith(_AuthDiam.new)],
    );
    router = container.read(routerProvider);
  });

  tearDown(() => container.dispose());

  test('tiap tab menunjuk branch yang BENAR-BENAR ada di router', () {
    final branches = pathTiapBranch(router);
    final items = navItemsUtama(UserRole.cashier);

    for (final item in items) {
      expect(
        item.branch,
        inInclusiveRange(0, branches.length - 1),
        reason: 'tab "${item.labelKey}" menunjuk branch ${item.branch}, '
            'padahal router hanya punya ${branches.length} branch (0..'
            '${branches.length - 1}). goBranch di luar jangkauan tidak '
            'melakukan apa-apa — tab-nya tampak mati.',
      );
    }
  });

  test('tiap tab membuka halaman yang sesuai namanya', () {
    // Inilah yang tak bisa ditangkap pemeriksaan angka: menukar dua branch di
    // router tanpa menukar tab-nya membuat menekan Riwayat membuka Notifikasi.
    final branches = pathTiapBranch(router);
    final items = navItemsUtama(UserRole.cashier);

    const seharusnya = {
      'nav.kasir': AppRoutes.kasir,
      'nav.riwayat': AppRoutes.riwayat,
      'nav.notifikasi': AppRoutes.notifications,
      'nav.profil': AppRoutes.profil,
    };

    for (final item in items) {
      expect(
        branches[item.branch],
        seharusnya[item.labelKey],
        reason: 'tab "${item.labelKey}" (branch ${item.branch}) membuka '
            '${branches[item.branch]}',
      );
    }
  });

  test('jumlah tab sama dengan jumlah branch', () {
    // Branch tanpa tab tak bisa dijangkau pengguna sama sekali; tab tanpa
    // branch adalah bug yang baru saja diperbaiki.
    expect(navItemsUtama(UserRole.cashier).length, pathTiapBranch(router).length);
  });

  test('tak ada dua tab berbagi branch yang sama', () {
    final branches = navItemsUtama(UserRole.cashier).map((i) => i.branch);
    expect(branches.toSet().length, branches.length,
        reason: 'dua tab menunjuk branch yang sama — salah satunya tak akan '
            'pernah tersorot, karena indexWhere berhenti di yang pertama');
  });

  test('konstanta branch cocok dengan urutan tab', () {
    final branches = pathTiapBranch(router);
    expect(branches[branchKasir], AppRoutes.kasir);
    expect(branches[branchRiwayat], AppRoutes.riwayat);
    expect(branches[branchNotifikasi], AppRoutes.notifications);
    expect(branches[branchProfil], AppRoutes.profil);
  });
}
