import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/shared_prefs.dart';
import '../../../core/outlet_scope.dart';

import '../../outlet/data/outlet_service.dart';
import '../../user/data/auth_service.dart';
import '../../user/domain/user_role.dart';
import '../domain/permission.dart';

/// Default permission set untuk setiap role. Meniru perilaku hardcoded
/// `UserRoleX` sebelumnya, jadi tanpa konfigurasi apa pun, behaviour lama
/// tetap sama.
Set<Permission> defaultPermissionsFor(UserRole role) {
  switch (role) {
    case UserRole.admin:
    case UserRole.owner:
    case UserRole.adminOutlet:
      return Permission.values.toSet();
    case UserRole.cashier:
      return {Permission.managePrinter, Permission.viewHistory};
  }
}

/// Snapshot state untuk [accessRightsProvider].
class AccessRightsState {
  /// Effective permissions per role.
  final Map<UserRole, Set<Permission>> perms;
  const AccessRightsState(this.perms);

  /// Effective permission set untuk role tertentu.
  Set<Permission> of(UserRole role) =>
      perms[role] ?? defaultPermissionsFor(role);

  /// Cek apakah [role] memiliki permission [p].
  bool has(UserRole role, Permission p) {
    if (role == UserRole.admin || role == UserRole.owner) return true;
    return of(role).contains(p);
  }

  /// Apakah konfigurasi untuk [role] sudah sama persis dengan default.
  bool isDefault(UserRole role) {
    final current = of(role);
    final def = defaultPermissionsFor(role);
    return current.length == def.length && current.containsAll(def);
  }
}

/// Notifier yang membaca / menulis konfigurasi hak akses ke
/// [SharedPreferences]. Setiap role disimpan sebagai JSON list berisi
/// nama-nama [Permission]. adminOwner tidak pernah disimpan — selalu pakai
/// `Permission.values`.
class AccessRightsNotifier extends Notifier<AccessRightsState> {
  static String _keyFor(UserRole role) => 'access_rights.${role.name}';

  @override
  AccessRightsState build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final map = <UserRole, Set<Permission>>{
      UserRole.admin: Permission.values.toSet(),
      UserRole.owner: Permission.values.toSet(),
    };
    for (final role in [UserRole.adminOutlet, UserRole.cashier]) {
      final raw = prefs.getString(_keyFor(role));
      if (raw == null) {
        map[role] = defaultPermissionsFor(role);
        continue;
      }
      try {
        final list = (jsonDecode(raw) as List).cast<dynamic>();
        final set = <Permission>{};
        for (final name in list) {
          final match = Permission.values
              .where((p) => p.name == name)
              .firstOrNull;
          if (match != null) set.add(match);
        }
        map[role] = set;
      } catch (_) {
        map[role] = defaultPermissionsFor(role);
      }
    }
    return AccessRightsState(map);
  }

  Future<void> _persist(UserRole role, Set<Permission> set) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(
      _keyFor(role),
      jsonEncode(set.map((e) => e.name).toList()),
    );
  }

  /// Set satu permission spesifik on/off untuk [role].
  Future<void> setPermission(UserRole role, Permission p, bool enabled) async {
    if (role == UserRole.admin || role == UserRole.owner) return;
    final next = {...state.perms};
    final set = {...(next[role] ?? defaultPermissionsFor(role))};
    if (enabled) {
      set.add(p);
    } else {
      set.remove(p);
    }
    next[role] = set;
    state = AccessRightsState(next);
    await _persist(role, set);
  }

  /// Kembalikan konfigurasi [role] ke default.
  Future<void> resetToDefault(UserRole role) async {
    if (role == UserRole.admin || role == UserRole.owner) return;
    final next = {...state.perms};
    final def = defaultPermissionsFor(role);
    next[role] = def;
    state = AccessRightsState(next);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_keyFor(role));
  }
}

final accessRightsProvider =
    NotifierProvider<AccessRightsNotifier, AccessRightsState>(
      AccessRightsNotifier.new,
    );

/// Permission efektif user dari BACKEND untuk outlet aktif (RBAC yang diatur
/// owner di web). Return set of key (mis. "transactions.refund") atau null
/// bila belum termuat / gagal (offline) → caller fallback ke izin lokal.
final backendPermissionsProvider = FutureProvider<Set<String>?>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return null;
  try {
    final keys = await ref.read(outletServiceProvider).getMyPermissions(outletId);
    return keys.toSet();
  } catch (_) {
    return null; // offline / error → biar fallback ke konfigurasi lokal
  }
});

/// Extension yang memudahkan pengecekan permission di UI.
///
/// Penggunaan:
/// ```dart
/// if (ref.hasPermission(Permission.manageProducts)) { ... }
/// ```
///
/// Sumber kebenaran: untuk permission yang punya padanan di backend
/// ([PermissionX.backendKey] non-null) dan set backend sudah termuat, izin
/// mengikuti konfigurasi owner di web. Selain itu (permission device-only,
/// atau saat offline) pakai konfigurasi lokal.
extension PermissionCheckRef on WidgetRef {
  bool hasPermission(Permission p) {
    final user = watch(authProvider).user;
    if (user == null) return false;
    // Owner/admin selalu punya semua izin (konsisten dengan backend).
    if (user.role == UserRole.admin || user.role == UserRole.owner) return true;

    final key = p.backendKey;
    if (key != null) {
      final backend = watch(backendPermissionsProvider).value;
      if (backend != null) return backend.contains(key);
    }
    return watch(accessRightsProvider).has(user.role, p);
  }
}
