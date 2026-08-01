import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/theme.dart';
import '../../outlet/data/outlet_service.dart';
import '../data/auth_service.dart';
import '../../../core/outlet_scope.dart';
import 'package:collection/collection.dart';
import '../domain/assignable_role.dart';
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

    // Daftar peran datang dari server, bukan dari enum lokal. Enum UserRole
    // hanya punya empat nilai untuk sepuluh peran yang benar-benar ada, dan
    // nama yang dihasilkannya ('cashier' huruf kecil) tak dikenal server sama
    // sekali — GetRoleByName mencocokkan persis dengan 'Cashier'.
    final rolesAsync = activeOutletId == null
        ? const AsyncValue<List<AssignableRole>>.data([])
        : ref.watch(assignableRolesProvider(activeOutletId));
    final roles = rolesAsync.value ?? const <AssignableRole>[];

    final nameCtrl = useTextEditingController(text: existing?.name ?? '');
    // Menyimpan NAMA peran dari server apa adanya — inilah yang dikirim balik.
    final role = useState<String>(existing?.roleName ?? '');
    final active = useState<bool>(existing?.active ?? true);

    final currentUser = ref.read(authProvider).user;
    final isEditingSelf =
        existing != null && currentUser?.remoteId == existing.remoteId;

    Future<void> save() async {
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
        // Bisa terjadi kalau daftar peran gagal dimuat. Lebih baik berhenti di
        // sini daripada mengirim peran kosong yang pasti ditolak server dengan
        // pesan yang tak berarti apa-apa bagi penggunanya.
        _snack(context, 'Pilih peran karyawan dulu');
        return;
      }

      // Tanpa username & password.
      //
      // Karyawan tak punya keduanya sejak dipisah ke tabel `employees`
      // (Fase 5): mereka masuk lewat sesi kasir atas persetujuan Pemilik,
      // bukan dengan kredensial sendiri. Server MEMBUANG kedua field itu
      // diam-diam — jadi yang lama memaksa penggunanya mengarang username dan
      // password yang tak pernah tersimpan dan tak pernah bisa dipakai.
      //
      // Isi payload mengikuti apa yang benar-benar dibaca server:
      //   POST /employees/create → dto.CreateEmployeeRequest {full_name, phone, role}
      //   PUT  /employees/:id    → {role}
      // Outletnya diambil server dari path URL, bukan dari badan permintaan.
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
                {'role': role.value},
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
          // Pengganti kolom username & password: keduanya dibuang karena
          // karyawan memang tak punya keduanya. Diberi tahu terang-terangan,
          // bukan dibiarkan jadi pertanyaan "kok tidak ada isian login-nya".
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Karyawan tidak punya username maupun password. '
              'Kehadirannya di kasir disahkan Pemilik lewat kode OTP '
              'tiap kali mulai bertugas.',
              style: TextStyle(fontSize: 12, color: kTextMid),
            ),
          ),
          const Gap(16),
          Text(
            'Role',
            style: TextStyle(fontWeight: FontWeight.w600, color: kTextDark),
          ),
          const Gap(8),
          // Owner & SuperAdminSystem tidak perlu disaring di sini — server
          // sudah menyingkirkannya lewat filterAssignableRoles, berikut peran
          // yang sudah dihapus dari katalog. Menyaring ulang di aplikasi cuma
          // menciptakan aturan kedua yang bisa berselisih dengan yang pertama.
          if (rolesAsync.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (roles.isEmpty)
            // Sengaja tanpa daftar cadangan lokal. Menawarkan tebakan di sini
            // berarti mengundang penyimpanan yang pasti ditolak server —
            // persis kegagalan senyap yang sedang diperbaiki.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kDanger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Daftar peran belum bisa dimuat. Periksa koneksi, lalu buka '
                'ulang halaman ini.',
                style: TextStyle(color: kDanger, fontSize: 13),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: roles.map((r) {
                final selected = r.name == role.value;
                return ChoiceChip(
                  label: Text(r.label),
                  tooltip: r.penjelasan.isEmpty ? null : r.penjelasan,
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
          const Gap(16),
          Text(
            'Outlet',
            style: TextStyle(fontWeight: FontWeight.w600, color: kTextDark),
          ),
          const Gap(8),
          // Ditampilkan, bukan dipilih.
          //
          // Sebelumnya di sini ada pemilih outlet — dropdown untuk kasir dan
          // daftar centang "Multi-select for Owner". Keduanya tak berpengaruh
          // apa pun: server mengambil outlet dari path URL
          // (`/outlets/{id}/employees/create`), dan dto.CreateEmployeeRequest
          // tak punya field outlet sama sekali. Cabang multi-outletnya bahkan
          // sudah mati lebih dulu, karena Owner memang tak pernah bisa dipilih
          // dari form ini.
          //
          // Pemilih yang tak mengubah apa pun lebih buruk daripada tidak ada:
          // ia membuat orang mengira karyawannya sudah ditempatkan di cabang
          // lain, padahal tidak.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              outlets.isEmpty
                  ? ref.t('outlet.empty_error')
                  : 'Karyawan ditambahkan ke outlet yang sedang aktif: '
                        '${outlets.firstWhereOrNull((o) => o.remoteId == activeOutletId)?.name ?? '-'}',
              style: TextStyle(
                color: outlets.isEmpty ? kDanger : kTextMid,
                fontSize: 13,
              ),
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
