import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:collection/collection.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../user/data/auth_service.dart';
import '../../user/domain/user.dart';
import '../../user/domain/user_role.dart';
import '../../../app/app_routes.dart';
import '../../../app/theme.dart';
import '../data/outlet_service.dart';
import '../domain/outlet.dart';

class OutletFormPage extends HookConsumerWidget {
  final String? remoteId;
  const OutletFormPage({super.key, this.remoteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outletsAsync = ref.watch(outletsProvider);
    final existing = remoteId == null
        ? null
        : outletsAsync.value?.firstWhereOrNull((o) => o.remoteId == remoteId);
    final nameCtrl = useTextEditingController(text: existing?.name ?? '');
    final addrCtrl = useTextEditingController(text: existing?.address ?? '');
    final phoneCtrl = useTextEditingController(text: existing?.phone ?? '');
    final currentUser = ref.watch(authProvider).user;
    final staffAsync = remoteId != null
        ? ref.watch(outletEmployeesProvider(remoteId!))
        : const AsyncValue.data(<User>[]);
    final isLoading = useState(false);

    Future<void> save() async {
      final name = nameCtrl.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nama outlet wajib diisi')),
        );
        return;
      }
      try {
        isLoading.value = true;
        final o = existing ?? Outlet(name: name);
        o.name = name;
        o.address = addrCtrl.text.trim();
        o.phone = phoneCtrl.text.trim();
        // Creator logic removed since it was legacy ObjectBox relationship

        if (existing == null) {
          await ref.read(outletServiceProvider).createOutlet(o);
        } else {
          await ref.read(outletServiceProvider).updateOutlet(o);
        }

        if (context.mounted) {
          ref.invalidate(outletsProvider);
          context.pop();
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: kDanger),
          );
        }
      } finally {
        isLoading.value = false;
      }
    }

    Future<void> remove() async {
      if (existing == null) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Hapus outlet?'),
          content: const Text(
            'Karyawan yang terhubung tidak akan ikut dihapus.',
          ),
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
        try {
          isLoading.value = true;
          await ref.read(outletServiceProvider).deleteOutlet(existing);
          if (context.mounted) {
            ref.invalidate(outletsProvider);
            context.pop();
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.toString()), backgroundColor: kDanger),
            );
          }
        } finally {
          isLoading.value = false;
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
          existing == null ? 'Tambah Outlet' : 'Edit Outlet',
          style: TextStyle(color: kTextDark, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (existing != null)
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
            enabled: !isLoading.value,
            decoration: const InputDecoration(labelText: 'Nama Outlet'),
          ),
          const Gap(12),
          TextField(
            controller: addrCtrl,
            enabled: !isLoading.value,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Alamat'),
          ),
          const Gap(12),
          TextField(
            controller: phoneCtrl,
            enabled: !isLoading.value,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Telepon'),
          ),
          const Gap(24),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: isLoading.value ? null : save,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isLoading.value
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Simpan',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          if (existing != null) ...[
            const Gap(32),
            Row(
              children: [
                const Text(
                  'Daftar Karyawan',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    // Navigate to add employee page
                    // We might want to pre-select this outlet in the future,
                    // but for now just go to the list/new page.
                    context.push(AppRoutes.employeesNew);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tambah'),
                ),
              ],
            ),
            const Gap(8),
            staffAsync.when(
              data: (staffMembers) {
                if (staffMembers.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'Belum ada karyawan',
                        style: TextStyle(
                            color: kTextMid, fontStyle: FontStyle.italic),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: staffMembers.length,
                  separatorBuilder: (_, _) => const Gap(8),
                  itemBuilder: (ctx, i) {
                    final user = staffMembers[i];
                    final isMe = user.remoteId == currentUser?.remoteId;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kDivider),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: kPrimary.withValues(alpha: 0.1),
                            child: Text(
                              (user.name.characters.firstOrNull ?? '?')
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: kPrimary,
                              ),
                            ),
                          ),
                          const Gap(12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  user.role.label.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: kPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isMe)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: kPrimary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'KAMU',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(e.toString()),
            ),
          ],
        ],
      ),
    );
  }
}
