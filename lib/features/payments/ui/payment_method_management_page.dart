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
import '../../user/data/auth_service.dart';
import '../data/payment_method_repository.dart';
import '../domain/payment_method.dart';
import 'widgets/payment_method_list_tile.dart';

class PaymentMethodManagementPage extends ConsumerWidget {
  const PaymentMethodManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methodsAsync = ref.watch(paymentMethodsFutureProvider);

    return MasterDetailScaffold<PaymentMethod>(
      title: 'Tipe Pembayaran',
      asyncItems: methodsAsync,
      identity: (pm) => pm.id,
      onRefresh: () async {
        ref.invalidate(paymentMethodsFutureProvider);
        await Future.delayed(const Duration(milliseconds: 500));
      },
      // Tombol "Tambah" sengaja dihilangkan — backend menyediakan 4 metode
      // sistem (Cash/QRIS/Card/Transfer) yang otomatis di-seed per outlet,
      // dan user hanya perlu mengisi detail (mis. data QRIS, rekening
      // transfer) lewat tombol edit.
      onAddPressed: null,
      phoneTileBuilder: (ctx, pm) => PaymentMethodListTile(
        method: pm,
        onTap: () => _showEditSheet(ctx, ref, pm),
      ),
      tabletMasterTileBuilder: (ctx, pm, isSelected, onSelect) =>
          PaymentMethodListTile(
            method: pm,
            isSelected: isSelected,
            onTap: onSelect,
          ),
      detailBuilder: (ctx, pm, isAdding, onSaved, onDeleted) =>
          _PaymentMethodDetailPanel(
            method: pm,
            isAdding: isAdding,
            onSaved: onSaved,
            onDeleted: onDeleted,
          ),
      emptyMessage: 'Belum ada tipe pembayaran',
      emptyIcon: AppIcons.money,
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, PaymentMethod pm) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: _PaymentMethodDetailPanel(
              method: pm,
              isAdding: false,
              onSaved: () => Navigator.pop(ctx),
              onDeleted: () => Navigator.pop(ctx),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentMethodDetailPanel extends HookConsumerWidget {
  final PaymentMethod? method;
  final bool isAdding;
  final VoidCallback onSaved;
  final VoidCallback onDeleted;

  const _PaymentMethodDetailPanel({
    required this.method,
    required this.isAdding,
    required this.onSaved,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (method == null && !isAdding) {
      return const TabletDetailEmptyState(
        icon: AppIcons.money,
        title: 'Manajemen Pembayaran',
        subtitle:
            'Pilih tipe pembayaran dari daftar di sebelah kiri\natau tambahkan tipe pembayaran baru.',
      );
    }

    final repo = ref.read(paymentMethodRepositoryProvider);
    final existing = method;
    final isEdit = existing != null;
    final isSystem = existing?.isSystem ?? false;

    final nameCtrl = useTextEditingController(text: existing?.name ?? '');
    final typeState = useState(existing?.type ?? 'cash');
    final activeState = useState(existing?.isActive ?? true);

    final providerCtrl = useTextEditingController(
      text: existing?.providerName ?? '',
    );
    final accNumCtrl = useTextEditingController(
      text: existing?.accountNumber ?? '',
    );
    final accNameCtrl = useTextEditingController(
      text: existing?.accountName ?? '',
    );
    final qrDataCtrl = useTextEditingController(text: existing?.qrData ?? '');

    Future<void> save() async {
      final name = nameCtrl.text.trim();
      if (name.isEmpty) return;

      final user = ref.read(authProvider).user;
      final activeOutlet = ref.read(activeOutletProvider);
      final outletRemoteId =
          activeOutlet?.remoteId ?? user?.outletRemoteIds.firstOrNull;
      if (outletRemoteId == null) return;

      final pm = existing ?? PaymentMethod(name: name, type: typeState.value);
      pm.name = name;
      pm.type = typeState.value;
      pm.isActive = activeState.value;
      pm.outletRemoteId = outletRemoteId;

      pm.providerName = providerCtrl.text.trim();
      pm.accountNumber = accNumCtrl.text.trim();
      pm.accountName = accNameCtrl.text.trim();
      pm.qrData = qrDataCtrl.text.trim();

      try {
        await repo.save(pm);
        // Refresh list di kasir & manajemen sehingga perubahan langsung
        // terlihat tanpa restart.
        ref.invalidate(paymentMethodsFutureProvider);
        onSaved();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${pm.name} berhasil diperbarui'),
              backgroundColor: kSuccess,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menyimpan: $e'),
              backgroundColor: kDanger,
            ),
          );
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
              icon: AppIcons.payment,
              color: detailColor,
            ),
            title: isEdit ? 'Edit Pembayaran' : 'Tambah Pembayaran',
            // Tombol delete hanya muncul untuk metode non-system & bukan
            // default. Metode sistem (Cash/QRIS/Card/Transfer bawaan)
            // dikunci di backend & disembunyikan dari UI.
            trailing: isEdit && !existing.isDefault && !isSystem
                ? TabletDeleteButton(
                    onTap: () async {
                      try {
                        await repo.remove(existing.id);
                        ref.invalidate(paymentMethodsFutureProvider);
                        onDeleted();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Gagal menghapus: $e'),
                              backgroundColor: kDanger,
                            ),
                          );
                        }
                      }
                    },
                  )
                : null,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TabletFormIllustration(
                        icon: AppIcons.payment,
                        color: detailColor,
                        title: isEdit ? 'Edit Pembayaran' : 'Tambah Pembayaran',
                      ),
                      // Badge SISTEM dengan keterangan field-field yang
                      // dikunci. Visual cue agar user tahu kenapa beberapa
                      // input read-only.
                      if (isSystem) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kPrimary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: kPrimary.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              const HugeIcon(
                                icon: AppIcons.alertCircle,
                                color: kPrimary,
                                size: 18,
                              ),
                              const Gap(10),
                              Expanded(
                                child: Text(
                                  'Metode sistem — nama & tipe terkunci. '
                                  'Anda tetap bisa mengisi detail di bawah.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: kTextDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Gap(20),
                      ],
                      const TabletFieldLabel(label: 'Nama Metode Pembayaran'),
                      TabletStyledTextField(
                        controller: nameCtrl,
                        hint: 'Contoh: GoPay, Bank Mandiri',
                        icon: AppIcons.payment,
                        enabled: !isSystem,
                      ),
                      const Gap(24),
                      const TabletFieldLabel(label: 'Tipe Transaksi'),
                      Row(
                        children: [
                          _TypeChoice(
                            label: 'Cash',
                            type: 'cash',
                            selected: typeState.value == 'cash',
                            onSelect: isSystem
                                ? (_) {}
                                : (t) => typeState.value = t,
                          ),
                          const Gap(12),
                          _TypeChoice(
                            label: 'QRIS',
                            type: 'qris',
                            selected: typeState.value == 'qris',
                            onSelect: isSystem
                                ? (_) {}
                                : (t) => typeState.value = t,
                          ),
                        ],
                      ),
                      const Gap(12),
                      Row(
                        children: [
                          _TypeChoice(
                            label: 'Card',
                            type: 'card',
                            selected: typeState.value == 'card',
                            onSelect: isSystem
                                ? (_) {}
                                : (t) => typeState.value = t,
                          ),
                          const Gap(12),
                          _TypeChoice(
                            label: 'Transfer',
                            type: 'transfer',
                            selected: typeState.value == 'transfer',
                            onSelect: isSystem
                                ? (_) {}
                                : (t) => typeState.value = t,
                          ),
                        ],
                      ),
                      const Gap(24),
                      // Form dinamis per type — Cash & Card sengaja minimal
                      // (tidak butuh detail). QRIS butuh string QR.
                      // Transfer butuh nomor + nama rekening (+ optional
                      // nama bank).
                      if (typeState.value == 'qris') ...[
                        const TabletFieldLabel(label: 'Data Statis QRIS'),
                        TabletStyledTextField(
                          controller: qrDataCtrl,
                          hint: 'Paste data QRIS di sini...',
                          icon: AppIcons.qrCode,
                          maxLines: 3,
                        ),
                        const Gap(8),
                        Text(
                          'Data ini akan diubah menjadi QR Code di layar kasir.',
                          style: TextStyle(
                            fontSize: 11,
                            color: kTextMid,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ] else if (typeState.value == 'transfer') ...[
                        const TabletFieldLabel(label: 'Nama Bank / Penyedia'),
                        TabletStyledTextField(
                          controller: providerCtrl,
                          hint: 'Contoh: Bank BCA, Mandiri',
                          icon: AppIcons.payment,
                        ),
                        const Gap(16),
                        const TabletFieldLabel(label: 'Nomor Rekening'),
                        TabletStyledTextField(
                          controller: accNumCtrl,
                          hint: 'Masukkan nomor rekening...',
                          icon: AppIcons.creditCard,
                        ),
                        const Gap(16),
                        const TabletFieldLabel(label: 'Atas Nama'),
                        TabletStyledTextField(
                          controller: accNameCtrl,
                          hint: 'Masukkan nama pemilik rekening...',
                          icon: AppIcons.person,
                        ),
                      ] else ...[
                        // Cash & Card: tidak ada detail tambahan.
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            typeState.value == 'cash'
                                ? 'Pembayaran tunai — tidak butuh detail tambahan.'
                                : 'Pembayaran kartu — diproses lewat mesin EDC, '
                                      'tidak butuh detail tambahan.',
                            style: TextStyle(
                              fontSize: 12,
                              color: kTextMid,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                      const Gap(32),
                      SwitchListTile(
                        title: const Text(
                          'Status Aktif',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'Nonaktifkan jika tidak ingin ditampilkan di kasir',
                        ),
                        value: activeState.value,
                        onChanged: (v) => activeState.value = v,
                        contentPadding: EdgeInsets.zero,
                      ),
                      // "Set sebagai default" — hanya tampil untuk metode
                      // existing yang aktif & belum default. Sekali tap,
                      // backend auto-unset default lain di outlet yang
                      // sama (single-default constraint).
                      if (isEdit &&
                          existing.isActive &&
                          !existing.isDefault) ...[
                        const Gap(16),
                        InkWell(
                          onTap: () async {
                            try {
                              await repo.setDefault(existing.id);
                              ref.invalidate(paymentMethodsFutureProvider);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${existing.name} jadi default kasir',
                                    ),
                                    backgroundColor: kSuccess,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                              onSaved();
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Gagal set default: $e'),
                                    backgroundColor: kDanger,
                                  ),
                                );
                              }
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 14,
                            ),
                            decoration: BoxDecoration(
                              color: kPrimary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: kPrimary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const HugeIcon(
                                  icon: AppIcons.stars,
                                  color: kPrimary,
                                  size: 18,
                                ),
                                const Gap(10),
                                Expanded(
                                  child: Text(
                                    'Jadikan metode default kasir',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: kPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (isEdit && existing.isDefault) ...[
                        const Gap(16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 14,
                          ),
                          decoration: BoxDecoration(
                            color: kSuccess.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: kSuccess.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const HugeIcon(
                                icon: AppIcons.stars,
                                color: kSuccess,
                                size: 18,
                              ),
                              const Gap(10),
                              Expanded(
                                child: Text(
                                  'Metode default kasir saat ini',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: kSuccess,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Gap(40),
                      TabletPrimaryButton(
                        label: isEdit ? 'Simpan Perubahan' : 'Tambah Metode',
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

class _TypeChoice extends StatelessWidget {
  final String label;
  final String type;
  final bool selected;
  final ValueChanged<String> onSelect;

  const _TypeChoice({
    required this.label,
    required this.type,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: () => onSelect(type),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: selected ? kPrimary.withValues(alpha: 0.1) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? kPrimary : kDivider,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              _TypeIcon(
                type: type,
                isActive: true,
                color: selected ? kPrimary : kTextMid,
              ),
              const Gap(8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? kPrimary : kTextDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeIcon extends StatelessWidget {
  final String type;
  final bool isActive;
  final Color? color;

  const _TypeIcon({required this.type, required this.isActive, this.color});

  @override
  Widget build(BuildContext context) {
    IconAsset icon = switch (type) {
      'qris' => AppIcons.qrCode,
      'card' => AppIcons.creditCard,
      'transfer' => AppIcons.payment,
      _ => AppIcons.money,
    };

    return HugeIcon(
      icon: icon,
      color: color ?? (isActive ? kPrimary : kTextMid),
      size: 20,
    );
  }
}
