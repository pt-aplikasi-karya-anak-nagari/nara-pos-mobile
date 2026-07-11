import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../app/app_routes.dart';
import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../shared/widgets/master_detail_scaffold.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../../outlet/data/outlet_service.dart';
import '../data/auth_service.dart';
import '../domain/user.dart';
import '../domain/user_role.dart';
import '../../../core/outlet_scope.dart';
import 'widgets/employee_list_tile.dart';

class EmployeeListPage extends ConsumerWidget {
  const EmployeeListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeOutletId = ref.watch(activeOutletIdProvider);
    final usersAsync = activeOutletId != null
        ? ref.watch(outletEmployeesProvider(activeOutletId))
        : const AsyncValue.data(<User>[]);
    final outlets = ref.watch(outletsProvider).value ?? [];

    String getOutletName(User emp) {
      if (emp.outletRemoteIds.isEmpty) return '-';
      return outlets
              .firstWhereOrNull((o) => o.remoteId == emp.outletRemoteIds.first)
              ?.name ??
          '-';
    }

    return MasterDetailScaffold<User>(
      title: 'Pengguna',
      asyncItems: usersAsync,
      identity: (u) => u.remoteId ?? '',
      onRefresh: () async {
        if (activeOutletId != null) {
          ref.invalidate(outletEmployeesProvider(activeOutletId));
          await ref.read(outletEmployeesProvider(activeOutletId).future);
        }
      },
      onAddPressed: () => context.push(AppRoutes.employeesNew),
      phoneTileBuilder: (ctx, emp) => EmployeeListTile(
        employee: emp,
        outletName: getOutletName(emp),
        onTap: () => context.push(
          AppRoutes.employeesEdit.replaceAll(':id', emp.remoteId ?? ''),
        ),
      ),
      tabletMasterTileBuilder: (ctx, emp, isSelected, onSelect) =>
          EmployeeListTile(
            employee: emp,
            outletName: getOutletName(emp),
            isSelected: isSelected,
            onTap: onSelect,
          ),
      detailBuilder: (ctx, user, isAdding, onSaved, onDeleted) =>
          _EmployeeDetailPanel(
            user: user,
            isAdding: isAdding,
            onSaved: onSaved,
            onDeleted: onDeleted,
          ),
      emptyMessage: 'Belum ada pengguna',
      emptyIcon: AppIcons.person,
    );
  }
}

class _EmployeeDetailPanel extends HookConsumerWidget {
  final User? user;
  final bool isAdding;
  final VoidCallback onSaved;
  final VoidCallback onDeleted;

  const _EmployeeDetailPanel({
    required this.user,
    required this.isAdding,
    required this.onSaved,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (user == null && !isAdding) {
      return const TabletDetailEmptyState(
        icon: AppIcons.person,
        title: 'Manajemen Pengguna',
        subtitle:
            'Pilih pengguna dari daftar di sebelah kiri\natau tambahkan pengguna baru.',
      );
    }

    final outlets = ref.watch(outletsProvider).value ?? [];
    final existing = user;
    final isEdit = existing != null;

    final nameCtrl = useTextEditingController(text: existing?.name ?? '');
    final userCtrl = useTextEditingController(text: existing?.username ?? '');
    final passCtrl = useTextEditingController();
    final role = useState<UserRole>(existing?.role ?? UserRole.cashier);
    final selectedOutletIds = useState<Set<String>>(
      existing?.outletRemoteIds.toSet() ??
          (outlets.isNotEmpty ? {outlets.first.remoteId!} : {}),
    );
    final active = useState<bool>(existing?.active ?? true);
    final showPass = useState(false);

    final currentUser = ref.watch(authProvider).user;
    final isEditingSelf =
        existing != null && currentUser?.remoteId == existing.remoteId;

    void save() async {
      final name = nameCtrl.text.trim();
      final username = userCtrl.text.trim();
      final outletId = ref.read(activeOutletIdProvider);

      if (outletId == null) {
        _snack(context, 'Outlet aktif tidak ditemukan');
        return;
      }
      if (name.isEmpty || username.isEmpty) {
        _snack(context, 'Nama dan username wajib diisi');
        return;
      }
      if (existing == null && passCtrl.text.isEmpty) {
        _snack(context, 'Password wajib diisi untuk pengguna baru');
        return;
      }
      if (selectedOutletIds.value.isEmpty) {
        _snack(context, 'Pilih minimal satu outlet');
        return;
      }

      final payload = {
        'full_name': name,
        'username': username,
        'role': role.value.name,
        'is_active': active.value,
        'outlet_ids': selectedOutletIds.value.toList(),
      };

      if (passCtrl.text.isNotEmpty) {
        payload['password'] = passCtrl.text;
      }

      try {
        if (existing == null) {
          await ref.read(outletServiceProvider).createEmployee(outletId, payload);
        } else {
          await ref.read(outletServiceProvider).updateEmployee(
                outletId,
                existing.remoteId!,
                payload,
              );
          if (isEditingSelf) ref.read(authProvider.notifier).refresh();
        }
        ref.invalidate(outletEmployeesProvider(outletId));
        onSaved();
      } catch (e) {
        if (context.mounted) _snack(context, e.toString());
      }
    }

    Future<void> remove() async {
      final outletId = ref.read(activeOutletIdProvider);
      if (existing == null || outletId == null) return;
      if (isEditingSelf) {
        _snack(context, 'Tidak bisa menghapus akun yang sedang dipakai');
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hapus pengguna?'),
          content: const Text('Akun akan dihapus permanen.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus', style: TextStyle(color: kDanger)),
            ),
          ],
        ),
      );
      if (ok == true) {
        try {
          await ref.read(outletServiceProvider).deleteEmployee(
                outletId,
                existing.remoteId!,
              );
          ref.invalidate(outletEmployeesProvider(outletId));
          onDeleted();
        } catch (e) {
          if (context.mounted) _snack(context, e.toString());
        }
      }
    }

    final detailColor = isEdit ? kAccent : kSuccess;

    return Container(
      color: kBg,
      child: Column(
        children: [
          TabletPanelHeader(
            leading: TabletHeaderBadge(
              icon: isEdit ? AppIcons.person : AppIcons.add,
              color: detailColor,
            ),
            title: isEdit ? 'Edit Pengguna' : 'Tambah Pengguna',
            trailing: isEdit && !isEditingSelf
                ? TabletDeleteButton(onTap: remove)
                : null,
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TabletFormIllustration(
                        icon: AppIcons.person,
                        color: detailColor,
                        title: isEdit ? 'Edit Pengguna' : 'Tambah Pengguna',
                      ),
                      const TabletFieldLabel(label: 'Nama Lengkap'),
                      TabletStyledTextField(
                        controller: nameCtrl,
                        icon: AppIcons.person,
                        hint: 'Nama Lengkap',
                      ),
                      const Gap(16),
                      const TabletFieldLabel(label: 'Username'),
                      TabletStyledTextField(
                        controller: userCtrl,
                        icon: HugeIcons.strokeRoundedUser,
                        hint: 'Username',
                      ),
                      const Gap(16),
                      const TabletFieldLabel(label: 'Password'),
                      TabletStyledTextField(
                        controller: passCtrl,
                        icon: HugeIcons.strokeRoundedLockPassword,
                        hint: isEdit ? 'Kosongkan jika tak diubah' : 'Password',
                        obscureText: !showPass.value,
                        suffixIcon: IconButton(
                          icon: Icon(
                            showPass.value
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => showPass.value = !showPass.value,
                        ),
                      ),
                      const Gap(24),
                      Text(
                        'Peran',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: kTextDark,
                        ),
                      ),
                      const Gap(8),
                      Wrap(
                        spacing: 8,
                        children: UserRole.values
                            .where((r) =>
                                r != UserRole.owner && r != UserRole.admin)
                            .map((r) {
                          final selected = r == role.value;
                          return ChoiceChip(
                            label: Text(r.label),
                            selected: selected,
                            onSelected: isEditingSelf && r != role.value
                                ? null
                                : (_) => role.value = r,
                            selectedColor: kPrimary,
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : kTextDark,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }).toList(),
                      ),
                      const Gap(24),
                      Text(
                        'Outlet',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: kTextDark,
                        ),
                      ),
                      const Gap(8),
                      if (outlets.isEmpty)
                        const Text(
                          'Belum ada outlet',
                          style: TextStyle(color: kDanger),
                        )
                      else if (role.value != UserRole.cashier)
                        Column(
                          children: outlets.map((o) {
                            final isSelected = selectedOutletIds.value.contains(
                              o.remoteId,
                            );
                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                o.name,
                                style: const TextStyle(fontSize: 14),
                              ),
                              value: isSelected,
                              activeColor: kPrimary,
                              onChanged: (v) {
                                if (v == true) {
                                  selectedOutletIds.value = {
                                    ...selectedOutletIds.value,
                                    o.remoteId!,
                                  };
                                } else {
                                  selectedOutletIds.value = selectedOutletIds
                                      .value
                                      .where((id) => id != o.remoteId)
                                      .toSet();
                                }
                              },
                            );
                          }).toList(),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: kDivider),
                          ),
                          child: DropdownButton<String>(
                            value: selectedOutletIds.value.firstOrNull,
                            isExpanded: true,
                            underline: const SizedBox.shrink(),
                            items: outlets
                                .map(
                                  (o) => DropdownMenuItem(
                                    value: o.remoteId,
                                    child: Text(o.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) selectedOutletIds.value = {v};
                            },
                          ),
                        ),
                      const Gap(24),
                      SwitchListTile.adaptive(
                        value: active.value,
                        onChanged: isEditingSelf
                            ? null
                            : (v) => active.value = v,
                        title: const Text('Aktif'),
                        subtitle: const Text(
                          'Pengguna nonaktif tidak bisa login',
                        ),
                        activeThumbColor: kPrimary,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const Gap(32),
                      TabletPrimaryButton(
                        label: isEdit ? 'Simpan Perubahan' : 'Tambah Pengguna',
                        onPressed: save,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
