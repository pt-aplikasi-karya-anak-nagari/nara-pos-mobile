import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:collection/collection.dart';
import '../../../app/app_routes.dart';
import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../shared/widgets/master_detail_scaffold.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../../outlet/data/outlet_service.dart';
import '../data/auth_service.dart';
import '../domain/user.dart';
import '../domain/assignable_role.dart';
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

    final aktifId = ref.watch(activeOutletIdProvider);
    // Daftar peran dari server — sama seperti employee_form_page. Enum lokal
    // cuma punya empat nilai untuk sepuluh peran, dan nama huruf kecil yang
    // dihasilkannya tak dikenal server sama sekali.
    final rolesAsync = aktifId == null
        ? const AsyncValue<List<AssignableRole>>.data([])
        : ref.watch(assignableRolesProvider(aktifId));
    final roles = rolesAsync.value ?? const <AssignableRole>[];

    final nameCtrl = useTextEditingController(text: existing?.name ?? '');
    final role = useState<String>(existing?.roleName ?? '');
    final active = useState<bool>(existing?.active ?? true);

    final currentUser = ref.watch(authProvider).user;
    final isEditingSelf =
        existing != null && currentUser?.remoteId == existing.remoteId;

    void save() async {
      final name = nameCtrl.text.trim();
      final outletId = ref.read(activeOutletIdProvider);

      if (outletId == null) {
        _snack(context, 'Outlet aktif tidak ditemukan');
        return;
      }
      if (name.isEmpty) {
        _snack(context, 'Nama karyawan wajib diisi');
        return;
      }
      if (role.value.isEmpty) {
        _snack(context, 'Pilih peran karyawan dulu');
        return;
      }

      // Tanpa username & password — karyawan tak punya keduanya sejak
      // dipisah ke tabel `employees` (Fase 5), dan server MEMBUANG kedua field
      // itu diam-diam. Lihat employee_form_page.dart untuk alasan lengkapnya.
      //
      // Isi payload mengikuti apa yang benar-benar dibaca server; outletnya
      // diambil dari path URL, bukan dari badan permintaan.
      try {
        if (existing == null) {
          await ref.read(outletServiceProvider).createEmployee(outletId, {
            'full_name': name,
            'role': role.value,
          });
        } else {
          await ref.read(outletServiceProvider).updateEmployee(
                outletId,
                existing.remoteId!,
                {
                  'role': role.value,
                  // Nama ikut dikirim. Sampai commit ini tak ada satu pun
                  // endpoint di seluruh sistem yang bisa memperbaiki nama
                  // karyawan — salah ketik saat mendaftarkan orang jadi
                  // permanen. Handler membacanya sebagai opsional: kosong
                  // berarti "jangan diubah".
                  'full_name': name,
                },
              );
          // Saklar aktif punya endpoint sendiri. Dulu `is_active` ikut
          // dititipkan bersama role dan tak pernah terbaca — handler
          // UpdateEmployee hanya mengikat `{role}`. Dikirim hanya bila memang
          // berubah, supaya tak ada permintaan sia-sia tiap kali menyimpan.
          if (active.value != existing.active) {
            await ref.read(outletServiceProvider).setEmployeeActive(
                  outletId,
                  existing.remoteId!,
                  active.value,
                );
          }
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
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Karyawan tidak punya username maupun password. '
                          'Kehadirannya di kasir disahkan Pemilik lewat kode '
                          'OTP tiap kali mulai bertugas.',
                          style: TextStyle(fontSize: 12, color: kTextMid),
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
                      // Server sudah menyaring Owner, SuperAdminSystem, dan
                      // peran yang dihapus dari katalog. Menyaring ulang di
                      // sini cuma menciptakan aturan kedua yang bisa
                      // berselisih dengan yang pertama.
                      if (roles.isEmpty)
                        Text(
                          'Daftar peran belum bisa dimuat. Periksa koneksi, '
                          'lalu buka ulang halaman ini.',
                          style: const TextStyle(color: kDanger, fontSize: 13),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: roles.map((r) {
                            final selected = r.name == role.value;
                            return ChoiceChip(
                              label: Text(r.label),
                              tooltip:
                                  r.penjelasan.isEmpty ? null : r.penjelasan,
                              selected: selected,
                              onSelected: isEditingSelf && r.name != role.value
                                  ? null
                                  : (_) => role.value = r.name,
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
                      // Dinyatakan, bukan dipilih — server mengambil outlet
                      // dari path URL dan dto.CreateEmployeeRequest tak punya
                      // field outlet sama sekali. Pemilih yang tak mengubah
                      // apa pun membuat orang mengira karyawannya ditempatkan
                      // di cabang lain, padahal tidak.
                      Text(
                        outlets.isEmpty
                            ? 'Belum ada outlet'
                            : 'Karyawan ditambahkan ke outlet yang sedang '
                                'aktif: ${outlets.firstWhereOrNull((o) => o.remoteId == aktifId)?.name ?? '-'}',
                        style: TextStyle(
                          color: outlets.isEmpty ? kDanger : kTextMid,
                          fontSize: 13,
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
