import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/outlet_scope.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../data/display_settings.dart';

/// Halaman pengaturan tampilan per-outlet. Saat ini berisi satu toggle:
/// `show_sold_count` — apakah card produk menampilkan badge "Terjual: N".
/// Owner / admin outlet bisa atur ON/OFF di sini.
///
/// Switch optimistic-update: state lokal langsung berubah, lalu commit
/// ke backend. Kalau gagal, revert + tampilkan snackbar error.
class DisplaySettingsPage extends HookConsumerWidget {
  const DisplaySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outlet = ref.watch(activeOutletProvider);
    final isTablet = MediaQuery.of(context).size.width >= 600;

    if (outlet == null) {
      return Scaffold(
        backgroundColor: kBg,
        body: const Center(child: Text('Pilih outlet terlebih dahulu')),
      );
    }

    final showSold = useState(outlet.showSoldCount);
    final saving = useState(false);

    Future<void> toggle(bool value) async {
      if (saving.value) return;
      final prev = showSold.value;
      showSold.value = value; // optimistic
      saving.value = true;
      try {
        await ref
            .read(displaySettingsServiceProvider)
            .save(outletId: outlet.remoteId!, showSoldCount: value);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                value
                    ? 'Badge "Terjual" diaktifkan'
                    : 'Badge "Terjual" dinonaktifkan',
              ),
              backgroundColor: kSuccess,
            ),
          );
        }
      } catch (e) {
        // Rollback ke nilai sebelum tap kalau request gagal.
        showSold.value = prev;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menyimpan: $e'),
              backgroundColor: kDanger,
            ),
          );
        }
      } finally {
        saving.value = false;
      }
    }

    final body = SingleChildScrollView(
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
                icon: AppIcons.fire,
                color: const Color(0xFFFF8A1F),
                title: 'Pengaturan Tampilan',
                subtitle:
                    'Atur preferensi visual card produk untuk outlet ${outlet.name}',
              ),
              _SectionHeader('Card Produk'),
              _SwitchCard(
                title: 'Tampilkan Jumlah Terjual',
                subtitle:
                    'Munculkan badge "🔥 Terjual: N" di card produk — '
                    'baik di app kasir maupun QR menu customer.',
                value: showSold.value,
                onChanged: toggle,
                loading: saving.value,
              ),
              const Gap(16),
              // Info: chip "Terlaris" tetap muncul terpisah dari toggle ini.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HugeIcon(
                      icon: AppIcons.alertCircle,
                      color: kPrimary,
                      size: 18,
                    ),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        'Toggle ini hanya memengaruhi badge angka di card. '
                        'Chip kategori "Terlaris" tetap tersedia.',
                        style: TextStyle(
                          fontSize: 12,
                          color: kTextMid,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Tampilan Card'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: body,
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
  final bool loading;
  final ValueChanged<bool> onChanged;
  const _SwitchCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.loading = false,
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
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: kTextMid, height: 1.35),
          ),
        ),
        value: value,
        // Disable interaction selama request in-flight supaya tidak double-tap.
        onChanged: loading ? null : onChanged,
        activeTrackColor: kPrimary.withValues(alpha: 0.2),
        activeThumbColor: kPrimary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 8,
        ),
      ),
    );
  }
}
