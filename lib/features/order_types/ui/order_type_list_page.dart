import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/outlet_scope.dart';
import '../../../shared/widgets/master_detail_scaffold.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../../outlet/data/outlet_service.dart';
import '../data/order_type_repository.dart';
import '../domain/order_type.dart';
import 'widgets/order_type_list_tile.dart';

class OrderTypeListPage extends HookConsumerWidget {
  const OrderTypeListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outletsAsync = ref.watch(outletsProvider);
    final outlets = outletsAsync.value ?? [];
    final effectiveId = ref.watch(activeOutletIdProvider);
    final orderTypesAsync = effectiveId != null
        ? ref.watch(orderTypesFutureProvider)
        : const AsyncValue<List<OrderType>>.loading();

    final activeOutletName = ref.watch(activeOutletLabelProvider);

    if (outlets.isEmpty) {
      return Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(title: const Text('Tipe Pesanan')),
        body: const Center(child: Text('Belum ada outlet')),
      );
    }

    return MasterDetailScaffold<OrderType>(
      title: 'Tipe Pesanan',
      asyncItems: orderTypesAsync,
      identity: (ot) => ot.id,
      onRefresh: () async {
        ref.invalidate(orderTypesFutureProvider);
        await Future.delayed(const Duration(milliseconds: 500));
      },
      onAddPressed: () => _showForm(context, ref),
      phoneHeaderSubtitle: Text(
        activeOutletName,
        style: TextStyle(color: kTextMid, fontSize: 12),
      ),
      tabletMasterHeaderBottom: null,
      phoneTileBuilder: (ctx, ot) => OrderTypeListTile(
        orderType: ot,
        onTap: () {
          // Tipe sistem (Dine In, Takeaway) terkunci — beri tahu user via
          // snackbar lalu jangan buka form edit.
          if (ot.isSystem) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                content: Text(
                  '"${ot.name}" adalah tipe sistem dan tidak dapat diubah.',
                ),
              ),
            );
            return;
          }
          _showForm(context, ref, ot);
        },
      ),
      tabletMasterTileBuilder: (ctx, ot, isSelected, onSelect) =>
          OrderTypeListTile(
            orderType: ot,
            isSelected: isSelected,
            onTap: () {
              if (ot.isSystem) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(
                      '"${ot.name}" adalah tipe sistem dan tidak dapat diubah.',
                    ),
                  ),
                );
                return;
              }
              onSelect();
            },
          ),
      detailBuilder: (ctx, ot, isAdding, onSaved, onDeleted) =>
          _OrderTypeDetailPanel(
            orderType: ot,
            outletId: effectiveId!,
            isAdding: isAdding,
            onSaved: onSaved,
            onDeleted: onDeleted,
          ),
      emptyMessage: 'Belum ada tipe pesanan',
      emptyIcon: AppIcons.storefront,
    );
  }

  void _showForm(BuildContext context, WidgetRef ref, [OrderType? existing]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderTypeForm(existing: existing),
    );
  }
}

class _OrderTypeDetailPanel extends HookConsumerWidget {
  final OrderType? orderType;
  final String outletId;
  final bool isAdding;
  final VoidCallback onSaved;
  final VoidCallback onDeleted;

  const _OrderTypeDetailPanel({
    required this.orderType,
    required this.outletId,
    required this.isAdding,
    required this.onSaved,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (orderType == null && !isAdding) {
      return const TabletDetailEmptyState(
        icon: AppIcons.storefront,
        title: 'Manajemen Tipe Pesanan',
        subtitle:
            'Pilih tipe pesanan dari daftar di sebelah kiri\natau tambahkan tipe pesanan baru.',
      );
    }

    final repo = ref.read(orderTypeRepositoryProvider);
    final existing = orderType;
    final isEdit = existing != null;

    final nameCtrl = useTextEditingController(text: existing?.name ?? '');
    final isDefault = useState(existing?.isDefault ?? false);
    final iconName = useState(existing?.iconName ?? 'storefront');
    final isSystem = existing?.isSystem ?? false;

    void save() {
      final name = nameCtrl.text.trim();
      if (name.isEmpty) {
        _snack(context, 'Nama tipe pesanan wajib diisi');
        return;
      }
      final sameName = repo.getByName(name);
      if (sameName != null && sameName.id != (existing?.id ?? '')) {
        _snack(
          context,
          'Tipe pesanan dengan nama tersebut sudah ada',
          isError: true,
        );
        return;
      }
      final ot = OrderType(
        id: existing?.id ?? '',
        name: name,
        isDefault: isDefault.value,
        iconName: iconName.value,
        isSystem: isSystem,
        // Pertahankan flag visibilitas yang diset dari web — form mobile
        // tidak mengeditnya, jadi JANGAN reset ke default true saat edit.
        showInSelection: existing?.showInSelection ?? true,
        showInReceipt: existing?.showInReceipt ?? true,
        showInHistory: existing?.showInHistory ?? true,
        showInReport: existing?.showInReport ?? true,
      );
      ot.outletRemoteId = outletId;
      
      // Fixed: Await the save operation and invalidate the provider
      Future<void> doSave() async {
        try {
          await repo.save(ot);
          ref.invalidate(orderTypesFutureProvider);
          onSaved();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gagal menyimpan: $e'), backgroundColor: kDanger),
            );
          }
        }
      }
      
      doSave();
    }

    Future<void> confirmDelete() async {
      if (existing == null) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hapus tipe pesanan?'),
          content: const Text('Tipe pesanan ini akan dihapus secara permanen.'),
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
        // Fixed: Await the delete operation and invalidate the provider
        await repo.delete(existing.id.toString());
        ref.invalidate(orderTypesFutureProvider);
        onDeleted();
      }
    }

    final detailColor = isEdit ? kAccent : kSuccess;

    return Container(
      color: kBg,
      child: Column(
        children: [
          TabletPanelHeader(
            leading: TabletHeaderBadge(
              icon: isEdit ? AppIcons.storefront : AppIcons.add,
              color: detailColor,
            ),
            title: isEdit ? 'Edit Tipe Pesanan' : 'Tambah Tipe Pesanan',
            trailing: isEdit && !isSystem ? TabletDeleteButton(onTap: confirmDelete) : null,
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
                        icon: AppIcons.storefront,
                        color: detailColor,
                        title: isEdit
                            ? 'Edit Tipe Pesanan'
                            : 'Tambah Tipe Pesanan',
                        subtitle: isEdit
                            ? 'Ubah informasi tipe pesanan'
                            : 'Tambahkan tipe pesanan baru untuk bisnis Anda',
                      ),
                      const TabletFieldLabel(label: 'Nama Tipe Pesanan'),
                      TabletStyledTextField(
                        controller: nameCtrl,
                        hint: 'Contoh: Dine In',
                        icon: AppIcons.storefront,
                        autofocus: !isEdit,
                        enabled: !isSystem,
                      ),
                      const Gap(16),
                      const TabletFieldLabel(label: 'Ikon'),
                      const Gap(8),
                      Row(
                        children: [
                          _IconOption(
                            icon: AppIcons.storefront,
                            active: iconName.value == 'storefront',
                            onTap: isSystem ? () {} : () => iconName.value = 'storefront',
                          ),
                          const Gap(8),
                          _IconOption(
                            icon: AppIcons.takeaway,
                            active: iconName.value == 'takeaway',
                            onTap: isSystem ? () {} : () => iconName.value = 'takeaway',
                          ),
                          const Gap(8),
                          _IconOption(
                            icon: AppIcons.delivery,
                            active: iconName.value == 'delivery',
                            onTap: isSystem ? () {} : () => iconName.value = 'delivery',
                          ),
                        ],
                      ),
                      const Gap(20),
                      SwitchListTile(
                        title: const Text('Jadikan Default'),
                        value: isDefault.value,
                        onChanged: (v) => isDefault.value = v,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const Gap(28),
                      TabletPrimaryButton(
                        label: isEdit
                            ? 'Simpan Perubahan'
                            : 'Tambah Tipe Pesanan',
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

  void _snack(BuildContext context, String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? kDanger : null),
    );
  }
}

class _OrderTypeForm extends HookConsumerWidget {
  final OrderType? existing;
  const _OrderTypeForm({this.existing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nameCtrl = useTextEditingController(text: existing?.name ?? '');
    final isDefault = useState(existing?.isDefault ?? false);
    final iconName = useState(existing?.iconName ?? 'storefront');
    final isSystem = existing?.isSystem ?? false;
    final effectiveId = ref.watch(activeOutletIdProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                existing == null ? 'Tambah Tipe Pesanan' : 'Edit Tipe Pesanan',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const Gap(24),
              const TabletFieldLabel(label: 'Nama Tipe Pesanan'),
              TabletStyledTextField(
                controller: nameCtrl,
                hint: 'Contoh: Dine In',
                icon: AppIcons.storefront,
                enabled: !isSystem,
              ),
              const Gap(16),
              const TabletFieldLabel(label: 'Ikon'),
              const Gap(8),
              Row(
                children: [
                  _IconOption(
                    icon: AppIcons.storefront,
                    active: iconName.value == 'storefront',
                    onTap: isSystem ? () {} : () => iconName.value = 'storefront',
                  ),
                  const Gap(8),
                  _IconOption(
                    icon: AppIcons.takeaway,
                    active: iconName.value == 'takeaway',
                    onTap: isSystem ? () {} : () => iconName.value = 'takeaway',
                  ),
                  const Gap(8),
                  _IconOption(
                    icon: AppIcons.delivery,
                    active: iconName.value == 'delivery',
                    onTap: isSystem ? () {} : () => iconName.value = 'delivery',
                  ),
                ],
              ),
              const Gap(20),
              SwitchListTile(
                title: const Text('Jadikan Default'),
                value: isDefault.value,
                onChanged: (v) => isDefault.value = v,
                contentPadding: EdgeInsets.zero,
              ),
              const Gap(24),
              TabletPrimaryButton(
                label: existing == null ? 'Tambah' : 'Simpan',
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final repo = ref.read(orderTypeRepositoryProvider);
                  final ot = OrderType(
                    id: existing?.id ?? '',
                    name: name,
                    isDefault: isDefault.value,
                    iconName: iconName.value,
                    isSystem: isSystem,
                    // Pertahankan flag visibilitas dari web (form mobile tak
                    // mengeditnya) — jangan reset ke true saat edit.
                    showInSelection: existing?.showInSelection ?? true,
                    showInReceipt: existing?.showInReceipt ?? true,
                    showInHistory: existing?.showInHistory ?? true,
                    showInReport: existing?.showInReport ?? true,
                  );
                  ot.outletRemoteId = effectiveId;
                  
                  // Fixed: Await the save operation and invalidate the provider
                  Future<void> doSave() async {
                    try {
                      await repo.save(ot);
                      ref.invalidate(orderTypesFutureProvider);
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Gagal menyimpan: $e'), backgroundColor: kDanger),
                        );
                      }
                    }
                  }
                  
                  doSave();
                },
              ),
              if (existing != null && !isSystem) ...[
                const Gap(12),
                TabletDangerButton(
                  label: 'Hapus Tipe Pesanan',
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Hapus tipe pesanan?'),
                        content: const Text(
                          'Tipe pesanan ini akan dihapus secara permanen.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Batal'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              'Hapus',
                              style: TextStyle(color: kDanger),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      // Fixed: Await the delete operation and invalidate the provider
                      await ref
                          .read(orderTypeRepositoryProvider)
                          .delete(existing!.id.toString());
                      ref.invalidate(orderTypesFutureProvider);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconOption extends StatelessWidget {
  final IconAsset icon;
  final bool active;
  final VoidCallback onTap;
  const _IconOption({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: active ? kPrimary.withValues(alpha: 0.1) : kBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? kPrimary : Colors.transparent),
        ),
        child: HugeIcon(
          icon: icon,
          color: active ? kPrimary : kTextMid,
          size: 24,
        ),
      ),
    );
  }
}
