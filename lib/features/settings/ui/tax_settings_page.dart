import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/outlet_scope.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../data/tax_settings.dart';

class TaxSettingsPage extends HookConsumerWidget {
  const TaxSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outlet = ref.watch(activeOutletProvider);
    final isTablet = MediaQuery.of(context).size.width >= 600;

    if (outlet == null) {
      return Scaffold(
        backgroundColor: kBg,
        body: Center(child: Text('Pilih outlet terlebih dahulu')),
      );
    }

    final enabled = useState(outlet.taxEnabled);
    final percent = useState(outlet.taxPercent);
    final servicePercent = useState(outlet.serviceChargePercent);
    final saving = useState(false);

    Future<void> save() async {
      if (saving.value) return;
      saving.value = true;
      try {
        await ref.read(taxSettingsServiceProvider).save(
              outletId: outlet.remoteId!,
              enabled: enabled.value,
              percent: percent.value,
              serviceChargePercent: servicePercent.value,
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pengaturan pajak tersimpan')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyimpan: $e'), backgroundColor: kDanger),
          );
        }
      } finally {
        saving.value = false;
      }
    }

    final bodyContent = SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 40.0 : 16.0,
        vertical: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabletFormIllustration(
                icon: AppIcons.percent,
                color: kPrimary,
                title: 'Pengaturan Pajak & Layanan',
                subtitle: 'Kelola persentase PPN dan biaya layanan untuk outlet ${outlet.name}',
              ),
              _SectionHeader('Status Operasional'),
              _SwitchCard(
                title: 'Aktifkan Pajak (PPN)',
                subtitle: 'Terapkan pajak secara otomatis pada setiap transaksi',
                value: enabled.value,
                onChanged: (v) => enabled.value = v,
              ),
              const Gap(32),
              _SectionHeader('Konfigurasi Biaya'),
              if (isTablet)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _PercentCard(
                        title: 'Pajak (PPN)',
                        value: percent.value,
                        icon: AppIcons.percent,
                        enabled: enabled.value,
                        onEdit: () => _editDialog(
                          context,
                          'Persentase Pajak',
                          percent.value,
                          [0, 5, 10, 11, 12],
                          (v) => percent.value = v,
                        ),
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: _PercentCard(
                        title: 'Biaya Layanan',
                        value: servicePercent.value,
                        icon: AppIcons.delivery, // Use delivery or similar for service
                        enabled: true,
                        onEdit: () => _editDialog(
                          context,
                          'Biaya Layanan',
                          servicePercent.value,
                          [0, 5, 10],
                          (v) => servicePercent.value = v,
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                _PercentCard(
                  title: 'Persentase Pajak (PPN)',
                  value: percent.value,
                  icon: AppIcons.percent,
                  enabled: enabled.value,
                  onEdit: () => _editDialog(
                    context,
                    'Persentase Pajak',
                    percent.value,
                    [0, 5, 10, 11, 12],
                    (v) => percent.value = v,
                  ),
                ),
                const Gap(12),
                _PercentCard(
                  title: 'Biaya Layanan (Service Charge)',
                  value: servicePercent.value,
                  icon: AppIcons.delivery,
                  enabled: true,
                  onEdit: () => _editDialog(
                    context,
                    'Biaya Layanan',
                    servicePercent.value,
                    [0, 5, 10],
                    (v) => servicePercent.value = v,
                  ),
                ),
              ],
              const Gap(40),
              TabletPrimaryButton(
                label: 'Simpan Pengaturan',
                isLoading: saving.value,
                onPressed: save,
              ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Manajemen Pajak'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: bodyContent,
    );
  }

  Future<void> _editDialog(
    BuildContext context,
    String title,
    double current,
    List<num> presets,
    ValueChanged<double> onSave,
  ) async {
    final ctrl = TextEditingController(text: _fmt(current));
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: kCard,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TabletFieldLabel(label: 'Masukkan Persentase (%)'),
            TabletStyledTextField(
              controller: ctrl,
              hint: '0.0',
              icon: AppIcons.percent,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              suffixIcon: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('%', style: TextStyle(fontWeight: FontWeight.bold, color: kPrimary)),
              ),
            ),
            const Gap(16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: presets.map((v) {
                return ActionChip(
                  label: Text('${_fmt(v.toDouble())}%'),
                  onPressed: () => ctrl.text = _fmt(v.toDouble()),
                  backgroundColor: kBg,
                  labelStyle: TextStyle(fontWeight: FontWeight.w600, color: kTextDark),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: kDivider),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: TextStyle(color: kTextMid, fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 100,
            child: TabletPrimaryButton(
              label: 'OK',
              onPressed: () {
                final raw = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? current;
                final clamped = raw.clamp(0.0, 100.0);
                onSave(clamped);
                Navigator.pop(ctx);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: kTextMid,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _SwitchCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kDivider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 13, color: kTextMid)),
        value: value,
        onChanged: onChanged,
        activeTrackColor: kPrimary.withValues(alpha: 0.2),
        activeThumbColor: kPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      ),
    );
  }
}

class _PercentCard extends StatelessWidget {
  final String title;
  final double value;
  final IconAsset icon;
  final bool enabled;
  final VoidCallback onEdit;
  const _PercentCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.enabled,
    required this.onEdit,
  });
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? onEdit : null,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: enabled ? kDivider : kDivider.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: HugeIcon(icon: icon, color: kPrimary, size: 20),
                  ),
                  const Spacer(),
                  HugeIcon(icon: AppIcons.edit, color: kTextMid, size: 16),
                ],
              ),
              const Gap(16),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kTextMid),
              ),
              const Gap(4),
              Text(
                '${_fmt(value)}%',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  color: kTextDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}
