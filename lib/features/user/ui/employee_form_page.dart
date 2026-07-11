import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/theme.dart';
import '../../outlet/domain/outlet.dart';
import '../../outlet/data/outlet_service.dart';
import '../data/auth_service.dart';
import '../../../core/outlet_scope.dart';
import 'package:collection/collection.dart';
import '../domain/user_role.dart';
import '../../../core/i18n.dart';

class EmployeeFormPage extends HookConsumerWidget {
  final String? employeeId;
  const EmployeeFormPage({super.key, this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeOutletId = ref.watch(activeOutletIdProvider);
    final employees = activeOutletId != null
        ? ref.watch(outletEmployeesProvider(activeOutletId)).value
        : null;
    final existing = employeeId == null
        ? null
        : employees?.firstWhereOrNull((e) => e.remoteId == employeeId);

    final outlets = ref.watch(outletsProvider).value ?? [];

    final nameCtrl = useTextEditingController(text: existing?.name ?? '');
    final userCtrl = useTextEditingController(text: existing?.username ?? '');
    final passCtrl = useTextEditingController();
    final role = useState<UserRole>(existing?.role ?? UserRole.cashier);
    final selectedOutletRemoteIds = useState<Set<String>>(
      existing?.outletRemoteIds.toSet() ??
          (outlets.isNotEmpty ? {outlets.first.remoteId!} : {}),
    );
    final active = useState<bool>(existing?.active ?? true);
    final showPass = useState(false);

    final currentUser = ref.read(authProvider).user;
    final isEditingSelf =
        existing != null && currentUser?.remoteId == existing.remoteId;

    Future<void> save() async {
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

      final payload = {
        'full_name': name,
        'username': username,
        'role': role.value.name,
        'is_active': active.value,
        'outlet_ids': selectedOutletRemoteIds.value.toList(),
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
        if (context.mounted) context.pop();
      } catch (e) {
        if (context.mounted) _snack(context, e.toString());
      }
    }

    Future<void> remove() async {
      if (existing == null) return;
      if (isEditingSelf) {
        _snack(context, 'Tidak bisa menghapus akun yang sedang dipakai');
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Hapus pengguna?'),
          content: const Text('Akun akan dihapus permanen.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Hapus', style: TextStyle(color: kDanger)),
            ),
          ],
        ),
      );
      if (ok == true) {
        final outletId = ref.read(activeOutletIdProvider);
        if (outletId == null) return;
        try {
          await ref.read(outletServiceProvider).deleteEmployee(
                outletId,
                existing.remoteId!,
              );
          ref.invalidate(outletEmployeesProvider(outletId));
          if (context.mounted) context.pop();
        } catch (e) {
          if (context.mounted) _snack(context, e.toString());
        }
      }
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard,
        elevation: 0,
        iconTheme: IconThemeData(color: kTextDark),
        title: Text(
          existing == null ? ref.t('employee.add') : ref.t('employee.edit'),
          style: TextStyle(color: kTextDark, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (existing != null && !isEditingSelf)
            IconButton(
              onPressed: remove,
              icon: const Icon(Icons.delete_outline, color: kDanger),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: nameCtrl,
            decoration: InputDecoration(labelText: ref.t('employee.name')),
          ),
          const Gap(12),
          TextField(
            controller: userCtrl,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: ref.t('employee.username'),
              hintText: ref.t('employee.username_hint'),
            ),
          ),
          const Gap(12),
          TextField(
            controller: passCtrl,
            obscureText: !showPass.value,
            decoration: InputDecoration(
              labelText: existing == null
                  ? ref.t('login.password')
                  : ref.t('employee.password_hint'),
              suffixIcon: IconButton(
                icon: Icon(
                  showPass.value ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => showPass.value = !showPass.value,
              ),
            ),
          ),
          const Gap(16),
          Text(
            'Role',
            style: TextStyle(fontWeight: FontWeight.w600, color: kTextDark),
          ),
          const Gap(8),
          Wrap(
            spacing: 8,
            children: UserRole.values
                .where((r) => r != UserRole.owner && r != UserRole.admin)
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
          const Gap(16),
          Text(
            'Outlet',
            style: TextStyle(fontWeight: FontWeight.w600, color: kTextDark),
          ),
          const Gap(8),
          if (outlets.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kDanger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                ref.t('outlet.empty_error'),
                style: const TextStyle(color: kDanger, fontSize: 13),
              ),
            )
          else if (role.value != UserRole.cashier)
            // Multi-select for Owner
            Column(
              children: outlets.map((o) {
                final isSelected = selectedOutletRemoteIds.value.contains(
                  o.remoteId,
                );
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(o.name, style: const TextStyle(fontSize: 14)),
                  value: isSelected,
                  activeColor: kPrimary,
                  onChanged: (v) {
                    if (v == true) {
                      selectedOutletRemoteIds.value = {
                        ...selectedOutletRemoteIds.value,
                        o.remoteId!,
                      };
                    } else {
                      selectedOutletRemoteIds.value = selectedOutletRemoteIds
                          .value
                          .where((id) => id != o.remoteId)
                          .toSet();
                    }
                  },
                );
              }).toList(),
            )
          else
            // Single-select for Kasir/Admin
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButton<String>(
                value: selectedOutletRemoteIds.value.firstOrNull,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: outlets
                    .map(
                      (Outlet o) => DropdownMenuItem(
                        value: o.remoteId,
                        child: Text(o.name),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) selectedOutletRemoteIds.value = {v};
                },
              ),
            ),
          const Gap(16),
          SwitchListTile.adaptive(
            value: active.value,
            onChanged: isEditingSelf ? null : (v) => active.value = v,
            title: Text(ref.t('common.active')),
            subtitle: Text(ref.t('employee.active_msg')),
            activeThumbColor: kPrimary,
            contentPadding: EdgeInsets.zero,
          ),
          const Gap(16),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: save,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                ref.t('common.save'),
                style: const TextStyle(fontWeight: FontWeight.w700),
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
