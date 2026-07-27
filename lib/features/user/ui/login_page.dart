
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:sizer/sizer.dart';
import 'widgets/register_sheet.dart';
import 'widgets/forgot_password_sheet.dart';
import 'staff_session_page.dart';

import '../../../app/theme.dart';
import '../../../app/theme_mode_provider.dart';
import '../../../core/i18n.dart';

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Perangkat kasir TIDAK punya jalan masuk lain: satu-satunya cara membuka
    // aplikasi adalah lewat persetujuan Pemilik/Manajer.
    //
    // Itu disengaja. Kalau kasir masih bisa login sendiri dengan password,
    // seluruh kontrol "siapa yang bertugas & siapa yang menyetujui" bisa
    // dilewati hanya dengan memilih form yang lain — dan jejak transaksi
    // kembali menunjuk orang yang salah.
    final isTablet = MediaQuery.sizeOf(context).width >= 720;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _LoginBackdrop()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 40 : 20,
                  vertical: 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _LogoIcon(size: 18, fontSize: 24),
                      const Gap(24),
                      Container(
                        padding: EdgeInsets.all(isTablet ? 32 : 22),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: StaffSessionFlow(
                          // Sesi sudah tersimpan oleh alurnya; router yang
                          // mengamati auth state yang memindahkan layar.
                          onSelesai: () {},
                        ),
                      ),
                      const Gap(14),
                      _LupaPasswordLink(),
                      const Gap(10),
                      _DaftarLink(),
                      const Gap(24),
                      const _LanguageSwitcher(isDark: false),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Positioned(top: 12, right: 12, child: _LoginThemeToggle()),
        ],
      ),
    );
  }
}

/// Latar bergradien + lingkaran blur, dipertahankan dari tampilan lama supaya
/// perangkat kasir tetap terasa bagian dari produk yang sama.
class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kPrimary.withValues(alpha: 0.10),
            kPrimary.withValues(alpha: 0.02),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: _BlurCircle(size: 200, color: kPrimary),
          ),
          Positioned(
            bottom: -70,
            left: -50,
            child: _BlurCircle(size: 240, color: kAccent),
          ),
        ],
      ),
    );
  }
}

/// Pemilik/Manajer memasukkan password di langkah pertama alur sesi kasir,
/// jadi tautan ini bukan pelengkap: tanpa jalan memulihkan password, satu
/// akun yang lupa berarti perangkat kasir terkunci total.
class _LupaPasswordLink extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton(
      onPressed: () async {
        final email = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const ForgotPasswordSheet(),
        );
        if (email != null && email.isNotEmpty && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password direset. Coba mulai sesi lagi.'),
            ),
          );
        }
      },
      child: Text(
        ref.t('login.forgot'),
        style: const TextStyle(
          color: kPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Pendaftaran Pemilik baru tetap disediakan — itu jalur akuisisi, dan
/// menghapusnya akan membuat aplikasi jadi jalan buntu bagi calon pengguna.
class _DaftarLink extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          ref.t('login.no_account'),
          style: TextStyle(color: kTextMid, fontSize: 13),
        ),
        GestureDetector(
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const RegisterSheet(),
          ),
          child: Text(
            ref.t('login.register'),
            style: const TextStyle(
              color: kPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginThemeToggle extends ConsumerWidget {
  /// Set true kalau tombol berada di atas panel gelap (mis. branding
  /// gradient di tablet) — supaya kontras icon tetap terbaca.
  const _LoginThemeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final (icon, label) = switch (mode) {
      ThemeMode.system => (Icons.brightness_auto_outlined, 'Sistem'),
      ThemeMode.light => (Icons.light_mode_outlined, 'Terang'),
      ThemeMode.dark => (Icons.dark_mode_outlined, 'Gelap'),
    };

    final next = switch (mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };

    final fg = kTextDark;
    final bg = kCard;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref.read(themeModeProvider.notifier).setMode(next),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kDivider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}













class _LogoIcon extends ConsumerWidget {
  final double size;
  final double fontSize;
  const _LogoIcon({required this.size, required this.fontSize});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: size.w,
      height: size.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: kPrimary,
        borderRadius: BorderRadius.circular(size.w * 0.28),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Text(
        'M',
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize.sp,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BlurCircle extends ConsumerWidget {
  final double size;
  final Color color;
  const _BlurCircle({required this.size, required this.color});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}


class _LanguageSwitcher extends ConsumerWidget {
  final bool isDark;
  const _LanguageSwitcher({this.isDark = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final isIndo = locale == AppLocale.id;

    return Container(
      height: 38,
      width: 116,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : kPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : kPrimary.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Animated Slider Background
          AnimatedAlign(
            duration: const Duration(milliseconds: 400),
            curve: Curves.fastEaseInToSlowEaseOut,
            alignment: isIndo ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(
              width: 53,
              decoration: BoxDecoration(
                color: isDark ? Colors.white : kPrimary,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
          // Labels
          Row(
            children: [
              Expanded(child: _langItem(ref, 'id', '🇮🇩 ID', isIndo)),
              Expanded(child: _langItem(ref, 'en', '🇺🇸 EN', !isIndo)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _langItem(WidgetRef ref, String code, String label, bool isActive) {
    return GestureDetector(
      onTap: () {
        if (!isActive) {
          HapticFeedback.selectionClick();
          ref
              .read(localeProvider.notifier)
              .set(code == 'id' ? AppLocale.id : AppLocale.en);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          style: TextStyle(
            color: isActive
                ? (isDark ? kPrimary : Colors.white)
                : (isDark ? Colors.white.withValues(alpha: 0.5) : kTextMid),
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: isActive ? 0.2 : 0,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

