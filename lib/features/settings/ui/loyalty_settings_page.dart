import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/responsive.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../data/loyalty_settings.dart';

class LoyaltySettingsPage extends HookConsumerWidget {
  const LoyaltySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTablet = context.isTablet;
    final settings = ref.watch(loyaltySettingsProvider);
    final notifier = ref.read(loyaltySettingsProvider.notifier);
    final selectedTab = useState(0);

    final tabs = [
      {'title': 'Pengaturan Umum', 'icon': AppIcons.settings},
      {'title': 'Poin & Reward', 'icon': AppIcons.favorite},
      {'title': 'Level Membership', 'icon': AppIcons.stars},
    ];

    // ── Tablet Layout ───────────────────────────────────────────────────
    if (isTablet) {
      return Scaffold(
        backgroundColor: kBg,
        body: Row(
          children: [
            // Left: Master Menu
            Expanded(
              child: Container(
                color: kBg,
                child: Column(
                  children: [
                    const TabletPanelHeader(title: 'Loyalty Program'),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: tabs.length,
                        separatorBuilder: (_, _) => const Gap(4),
                        itemBuilder: (context, index) {
                          final isActive = selectedTab.value == index;
                          return _MasterMenuTile(
                            icon: tabs[index]['icon'] as IconAsset,
                            title: tabs[index]['title'] as String,
                            isActive: isActive,
                            onTap: () => selectedTab.value = index,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            VerticalDivider(width: 1, color: kDivider),
            // Right: Detail Content
            Expanded(
              flex: 2,
              child: Scaffold(
                backgroundColor: kBg,
                appBar: AppBar(
                  title: Text(
                    tabs[selectedTab.value]['title'] as String,
                    style: TextStyle(
                      color: kTextDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  elevation: 0,
                  backgroundColor: kBg,
                  automaticallyImplyLeading: false,
                ),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ContentConstrained(
                    maxWidth: 700,
                    child: _buildTabContent(
                      context,
                      selectedTab.value,
                      settings,
                      notifier,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── Mobile Layout ────────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: const Text('Pengaturan Loyalty')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader('Umum'),
          _buildGeneralSettings(settings, notifier),
          if (settings.enabled) ...[
            const Gap(24),
            _SectionHeader('Poin & Reward'),
            _buildPointSettings(context, settings, notifier),
            const Gap(24),
            _SectionHeader('Membership Tiers'),
            _buildMembershipInfo(),
          ],
        ],
      ),
    );
  }

  Widget _buildTabContent(
    BuildContext context,
    int index,
    LoyaltySettings settings,
    LoyaltySettingsNotifier notifier,
  ) {
    switch (index) {
      case 0:
        return _buildGeneralSettings(settings, notifier);
      case 1:
        return settings.enabled
            ? _buildPointSettings(context, settings, notifier)
            : const _SettingsDisabledHint();
      case 2:
        return _buildMembershipInfo();
      default:
        return const SizedBox();
    }
  }

  Widget _buildGeneralSettings(
    LoyaltySettings settings,
    LoyaltySettingsNotifier notifier,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kDivider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text(
                'Aktifkan Loyalty Program',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Pelanggan akan mendapatkan poin setiap kali melakukan transaksi',
              ),
              value: settings.enabled,
              onChanged: (v) => notifier.setEnabled(v),
              activeTrackColor: kPrimary.withValues(alpha: 0.5),
              activeThumbColor: kPrimary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPointSettings(
    BuildContext context,
    LoyaltySettings settings,
    LoyaltySettingsNotifier notifier,
  ) {
    return Column(
      children: [
        _SettingCard(
          title: 'Konversi Belanja ke Poin',
          subtitle: 'Rp ${settings.amountPerPoint.toInt()} = 1 Poin',
          icon: AppIcons.money,
          onEdit: () => _editDialog(
            context,
            'Belanja per 1 Poin',
            settings.amountPerPoint,
            (v) => notifier.setAmountPerPoint(v),
          ),
        ),
        const Gap(12),
        _SettingCard(
          title: 'Nilai Poin (Tukar ke Diskon)',
          subtitle: '1 Poin = Rp ${settings.pointValue.toInt()}',
          icon: AppIcons.payment,
          onEdit: () => _editDialog(
            context,
            'Nilai Tukar 1 Poin',
            settings.pointValue,
            (v) => notifier.setPointValue(v),
          ),
        ),
      ],
    );
  }

  Widget _buildMembershipInfo() {
    return Column(
      children: [
        _TierInfoRow(
          name: 'Regular',
          minPoints: '0',
          color: kTextMid,
          icon: AppIcons.person,
        ),
        const Gap(12),
        _TierInfoRow(
          name: 'Silver',
          minPoints: '200',
          color: const Color(0xFF9E9E9E),
          icon: AppIcons.stars,
        ),
        const Gap(12),
        _TierInfoRow(
          name: 'Gold',
          minPoints: '500',
          color: const Color(0xFFFFB300),
          icon: AppIcons.stars,
        ),
        const Gap(12),
        _TierInfoRow(
          name: 'Platinum',
          minPoints: '1000',
          color: kPrimary,
          icon: AppIcons.stars,
        ),
      ],
    );
  }

  Future<void> _editDialog(
    BuildContext context,
    String title,
    double current,
    Function(double) onSave,
  ) async {
    final ctrl = TextEditingController(text: current.toInt().toString());
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            prefixText: 'Rp ',
            filled: true,
            fillColor: kBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: TextStyle(color: kTextMid)),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text) ?? current;
              onSave(val);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _MasterMenuTile extends StatelessWidget {
  final IconAsset icon;
  final String title;
  final bool isActive;
  final VoidCallback onTap;

  const _MasterMenuTile({
    required this.icon,
    required this.title,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? kPrimary.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? kPrimary.withValues(alpha: 0.3)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive
                      ? kPrimary.withValues(alpha: 0.15)
                      : kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: HugeIcon(icon: icon, color: kPrimary, size: 18),
              ),
              const Gap(12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? kPrimary : kTextDark,
                  ),
                ),
              ),
              if (isActive)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: kPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: kTextMid,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconAsset icon;
  final VoidCallback onEdit;

  const _SettingCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kDivider),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: HugeIcon(icon: icon, color: kPrimary, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Text(subtitle, style: TextStyle(color: kTextMid)),
        trailing: IconButton(
          icon: const HugeIcon(icon: AppIcons.edit, color: kPrimary, size: 18),
          onPressed: onEdit,
        ),
      ),
    );
  }
}

class _TierInfoRow extends StatelessWidget {
  final String name;
  final String minPoints;
  final Color color;
  final IconAsset icon;

  const _TierInfoRow({
    required this.name,
    required this.minPoints,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: HugeIcon(icon: icon, color: color, size: 24),
          ),
          const Gap(16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: color,
                  ),
                ),
                Text(
                  'Minimum: $minPoints Poin',
                  style: TextStyle(color: kTextMid, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsDisabledHint extends StatelessWidget {
  const _SettingsDisabledHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(icon: AppIcons.settings, color: kTextLight, size: 48),
          const Gap(12),
          Text(
            'Aktifkan Loyalty Program terlebih dahulu\ndi menu Pengaturan Umum.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kTextMid),
          ),
        ],
      ),
    );
  }
}
