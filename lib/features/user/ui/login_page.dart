import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/services.dart';
import 'package:sizer/sizer.dart';
import 'widgets/register_sheet.dart';
import 'widgets/forgot_password_sheet.dart';

import '../../../app/theme.dart';
import '../../../app/theme_mode_provider.dart';
import '../../../core/app_icons.dart';
import '../../../core/config/app_config.dart';
import '../data/auth_service.dart';
import '../../../core/i18n.dart';

class LoginPage extends HookConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pre-fill kredensial hanya di debug build (nilai dari
    // AppConfig.devLoginEmail / AppConfig.devLoginPassword). Release build
    // selalu mulai dengan field kosong.
    final prefillEmail = kDebugMode ? AppConfig.devLoginEmail : '';
    final prefillPass = kDebugMode ? AppConfig.devLoginPassword : '';
    final userCtrl = useTextEditingController(text: prefillEmail);
    final passCtrl = useTextEditingController(text: prefillPass);
    final otpCtrl = useTextEditingController();
    final loading = useState(false);
    final error = useState<String?>(null);
    final info = useState<String?>(null);
    final showPass = useState(false);
    final rememberMe = useState(true);
    final otpMode = useState(false);
    final otpSent = useState(false);
    final otpResendSeconds = useState(0);
    final forceOtpRequest = useRef(false);
    final otpTimer = useRef<Timer?>(null);

    void startOtpResendCooldown([int seconds = 60]) {
      otpTimer.value?.cancel();
      otpResendSeconds.value = seconds <= 0 ? 60 : seconds;
      otpTimer.value = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (otpResendSeconds.value <= 1) {
          timer.cancel();
          otpTimer.value = null;
          otpResendSeconds.value = 0;
          return;
        }
        otpResendSeconds.value -= 1;
      });
    }

    useEffect(() {
      return () {
        otpTimer.value?.cancel();
      };
    }, const []);

    Future<void> submit() async {
      if (loading.value) return;
      FocusScope.of(context).unfocus();
      error.value = null;
      info.value = null;

      final email = userCtrl.text.trim();
      if (email.isEmpty) {
        error.value = otpMode.value
            ? ref.t('login.otp_email_empty')
            : ref.t('login.error_empty');
        return;
      }
      if (passCtrl.text.isEmpty) {
        error.value = ref.t('login.error_empty');
        return;
      }
      final shouldRequestOtp =
          otpMode.value && (!otpSent.value || forceOtpRequest.value);
      if (otpMode.value &&
          !shouldRequestOtp &&
          otpCtrl.text.trim().length != 6) {
        error.value = ref.t('login.otp_code_empty');
        return;
      }

      loading.value = true;
      HapticFeedback.mediumImpact();
      final notifier = ref.read(authProvider.notifier);
      forceOtpRequest.value = false;
      String? msg;
      var retryAfterSeconds = 60;
      if (otpMode.value) {
        if (shouldRequestOtp) {
          final result = await notifier.requestLoginOtp(email, passCtrl.text);
          msg = result.message;
          retryAfterSeconds = result.retryAfterSeconds;
        } else {
          msg = await notifier.loginWithOtp(email, passCtrl.text, otpCtrl.text);
        }
      } else {
        msg = await notifier.login(email, passCtrl.text);
      }
      loading.value = false;
      if (msg != null) {
        if (shouldRequestOtp && retryAfterSeconds > 0) {
          otpSent.value = true;
          startOtpResendCooldown(retryAfterSeconds);
        }
        HapticFeedback.vibrate();
        error.value = msg;
      } else if (shouldRequestOtp) {
        otpSent.value = true;
        startOtpResendCooldown(retryAfterSeconds);
        info.value = ref.t('login.otp_sent');
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    }

    return Scaffold(
      backgroundColor: kBg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isTablet = constraints.maxWidth >= 900;
          final isPhone = constraints.maxWidth < 600;

          final Widget body = isTablet
              ? _TabletLayout(
                  userCtrl: userCtrl,
                  passCtrl: passCtrl,
                  otpCtrl: otpCtrl,
                  loading: loading,
                  error: error,
                  info: info,
                  showPass: showPass,
                  rememberMe: rememberMe,
                  otpMode: otpMode,
                  otpSent: otpSent,
                  otpResendSeconds: otpResendSeconds,
                  forceOtpRequest: forceOtpRequest,
                  onSubmit: submit,
                )
              : _MobileLayout(
                  userCtrl: userCtrl,
                  passCtrl: passCtrl,
                  otpCtrl: otpCtrl,
                  loading: loading,
                  error: error,
                  info: info,
                  showPass: showPass,
                  rememberMe: rememberMe,
                  otpMode: otpMode,
                  otpSent: otpSent,
                  otpResendSeconds: otpResendSeconds,
                  forceOtpRequest: forceOtpRequest,
                  onSubmit: submit,
                  isPhone: isPhone,
                );

          // Tombol toggle tema di pojok kanan atas — selalu accessible
          // sebelum user login. SafeArea supaya tidak nubruk notch /
          // status bar di phone fullscreen.
          return Stack(
            children: [
              body,
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _LoginThemeToggle(
                      // Untuk tablet, kontras dengan panel gradient kiri
                      // → pakai versi terang. Mobile pakai versi adaptif.
                      onDarkPanel: isTablet,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Tombol kompak untuk cycle tema (Sistem → Terang → Gelap → Sistem).
/// Disisipkan di pojok kanan atas login page supaya user bisa atur tema
/// bahkan sebelum login.
class _LoginThemeToggle extends ConsumerWidget {
  /// Set true kalau tombol berada di atas panel gelap (mis. branding
  /// gradient di tablet) — supaya kontras icon tetap terbaca.
  final bool onDarkPanel;
  const _LoginThemeToggle({this.onDarkPanel = false});

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

    final fg = onDarkPanel ? Colors.white : kTextDark;
    final bg = onDarkPanel ? Colors.white.withValues(alpha: 0.12) : kCard;

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
            border: Border.all(
              color: onDarkPanel
                  ? Colors.white.withValues(alpha: 0.2)
                  : kDivider,
            ),
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

class _TabletLayout extends ConsumerWidget {
  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final TextEditingController otpCtrl;
  final ValueNotifier<bool> loading;
  final ValueNotifier<String?> error;
  final ValueNotifier<String?> info;
  final ValueNotifier<bool> showPass;
  final ValueNotifier<bool> rememberMe;
  final ValueNotifier<bool> otpMode;
  final ValueNotifier<bool> otpSent;
  final ValueNotifier<int> otpResendSeconds;
  final ObjectRef<bool> forceOtpRequest;
  final VoidCallback onSubmit;

  const _TabletLayout({
    required this.userCtrl,
    required this.passCtrl,
    required this.otpCtrl,
    required this.loading,
    required this.error,
    required this.info,
    required this.showPass,
    required this.rememberMe,
    required this.otpMode,
    required this.otpSent,
    required this.otpResendSeconds,
    required this.forceOtpRequest,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        // Left Panel: Branding & Visuals
        Expanded(
          flex: 6,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kPrimary, Color(0xFF0F172A)],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: -150,
                  left: -150,
                  child: _BlurCircle(
                    size: 500,
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
                Positioned(
                  bottom: -200,
                  right: -100,
                  child: _BlurCircle(
                    size: 600,
                    color: kPrimary.withValues(alpha: 0.15),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(80),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LogoIcon(size: 8, fontSize: 18),
                      const Spacer(),
                      Text(
                        ref.t('login.branding_title'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 56,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          letterSpacing: -2,
                        ),
                      ),
                      const Gap(24),
                      Text(
                        ref.t('login.branding_sub'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 18,
                          height: 1.6,
                        ),
                      ),
                      const Spacer(),
                      _BrandingFooter(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Right Panel: Form
        Expanded(
          flex: 5,
          child: Container(
            color: Colors.white,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 80),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _LoginForm(
                    userCtrl: userCtrl,
                    passCtrl: passCtrl,
                    otpCtrl: otpCtrl,
                    loading: loading,
                    error: error,
                    info: info,
                    showPass: showPass,
                    rememberMe: rememberMe,
                    otpMode: otpMode,
                    otpSent: otpSent,
                    otpResendSeconds: otpResendSeconds,
                    forceOtpRequest: forceOtpRequest,
                    onSubmit: onSubmit,
                    isTablet: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileLayout extends ConsumerWidget {
  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final TextEditingController otpCtrl;
  final ValueNotifier<bool> loading;
  final ValueNotifier<String?> error;
  final ValueNotifier<String?> info;
  final ValueNotifier<bool> showPass;
  final ValueNotifier<bool> rememberMe;
  final ValueNotifier<bool> otpMode;
  final ValueNotifier<bool> otpSent;
  final ValueNotifier<int> otpResendSeconds;
  final ObjectRef<bool> forceOtpRequest;
  final VoidCallback onSubmit;
  final bool isPhone;

  const _MobileLayout({
    required this.userCtrl,
    required this.passCtrl,
    required this.otpCtrl,
    required this.loading,
    required this.error,
    required this.info,
    required this.showPass,
    required this.rememberMe,
    required this.otpMode,
    required this.otpSent,
    required this.otpResendSeconds,
    required this.forceOtpRequest,
    required this.onSubmit,
    required this.isPhone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        // Background Design
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF8FAFC), Colors.white],
              ),
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -80,
          child: _BlurCircle(
            size: 80.w,
            color: kPrimary.withValues(alpha: 0.05),
          ),
        ),
        Positioned(
          bottom: -150,
          left: -100,
          child: _BlurCircle(
            size: 90.w,
            color: kPrimary.withValues(alpha: 0.03),
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isPhone ? 24 : 60,
                vertical: 40,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _LogoIcon(size: 18, fontSize: 24),
                  const Gap(32),
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: _LoginForm(
                      userCtrl: userCtrl,
                      passCtrl: passCtrl,
                      otpCtrl: otpCtrl,
                      loading: loading,
                      error: error,
                      info: info,
                      showPass: showPass,
                      rememberMe: rememberMe,
                      otpMode: otpMode,
                      otpSent: otpSent,
                      otpResendSeconds: otpResendSeconds,
                      forceOtpRequest: forceOtpRequest,
                      onSubmit: onSubmit,
                      isTablet: false,
                    ),
                  ),
                  const Gap(40),
                  const _LanguageSwitcher(isDark: false),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginForm extends ConsumerWidget {
  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final TextEditingController otpCtrl;
  final ValueNotifier<bool> loading;
  final ValueNotifier<String?> error;
  final ValueNotifier<String?> info;
  final ValueNotifier<bool> showPass;
  final ValueNotifier<bool> rememberMe;
  final ValueNotifier<bool> otpMode;
  final ValueNotifier<bool> otpSent;
  final ValueNotifier<int> otpResendSeconds;
  final ObjectRef<bool> forceOtpRequest;
  final VoidCallback onSubmit;
  final bool isTablet;

  const _LoginForm({
    required this.userCtrl,
    required this.passCtrl,
    required this.otpCtrl,
    required this.loading,
    required this.error,
    required this.info,
    required this.showPass,
    required this.rememberMe,
    required this.otpMode,
    required this.otpSent,
    required this.otpResendSeconds,
    required this.forceOtpRequest,
    required this.onSubmit,
    required this.isTablet,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          ref.t('login.welcome'),
          textAlign: isTablet ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: isTablet ? 24.sp : 22.sp,
            fontWeight: FontWeight.w900,
            color: kTextDark,
            letterSpacing: -1,
          ),
        ),
        const Gap(8),
        Text(
          ref.t('login.subtitle'),
          textAlign: isTablet ? TextAlign.left : TextAlign.center,
          style: TextStyle(fontSize: isTablet ? 12.sp : 11.sp, color: kTextMid),
        ),
        Gap(2.h),
        ValueListenableBuilder<bool>(
          valueListenable: otpMode,
          builder: (_, useOtp, _) => _LoginModeSwitch(
            useOtp: useOtp,
            onChanged: (next) {
              otpMode.value = next;
              error.value = null;
              info.value = null;
              if (!next) {
                otpSent.value = false;
                otpResendSeconds.value = 0;
                otpCtrl.clear();
              }
            },
          ),
        ),
        Gap(2.h),
        _InputLabel(ref.t('login.email')),
        _CustomTextField(
          controller: userCtrl,
          hint: 'email atau username',
          icon: Icons.person_outline_rounded,
          keyboardType: TextInputType.text,
        ),
        Gap(2.5.h),
        ValueListenableBuilder<bool>(
          valueListenable: otpMode,
          builder: (_, useOtp, _) {
            if (useOtp) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _InputLabel(ref.t('login.password')),
                  ValueListenableBuilder<bool>(
                    valueListenable: showPass,
                    builder: (_, show, _) => _CustomTextField(
                      controller: passCtrl,
                      hint: '••••••••',
                      icon: Icons.lock_rounded,
                      obscure: !show,
                      suffix: IconButton(
                        onPressed: () => showPass.value = !show,
                        icon: Icon(
                          show
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: kTextMid,
                          size: 20,
                        ),
                      ),
                      onSubmitted: (_) => onSubmit(),
                    ),
                  ),
                  const Gap(14),
                  ValueListenableBuilder<bool>(
                    valueListenable: otpSent,
                    builder: (_, sent, _) {
                      if (!sent) {
                        return Text(
                          ref.t('login.otp_hint'),
                          style: TextStyle(color: kTextMid, fontSize: 13),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _InputLabel(ref.t('login.otp_code')),
                          _CustomTextField(
                            controller: otpCtrl,
                            hint: '123456',
                            icon: Icons.password_rounded,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            onSubmitted: (_) => onSubmit(),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InputLabel(ref.t('login.password')),
                ValueListenableBuilder<bool>(
                  valueListenable: showPass,
                  builder: (_, show, _) => _CustomTextField(
                    controller: passCtrl,
                    hint: '••••••••',
                    icon: Icons.lock_rounded,
                    obscure: !show,
                    suffix: IconButton(
                      onPressed: () => showPass.value = !show,
                      icon: Icon(
                        show
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: kTextMid,
                        size: 20,
                      ),
                    ),
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
              ],
            );
          },
        ),
        Gap(2.h),
        ValueListenableBuilder<bool>(
          valueListenable: otpMode,
          builder: (_, useOtp, _) {
            if (useOtp) {
              return ValueListenableBuilder<bool>(
                valueListenable: otpSent,
                builder: (_, sent, _) => ValueListenableBuilder<int>(
                  valueListenable: otpResendSeconds,
                  builder: (_, remainingSeconds, _) {
                    final canResend = sent && remainingSeconds == 0;
                    return Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: canResend
                            ? () {
                                forceOtpRequest.value = true;
                                otpCtrl.clear();
                                info.value = null;
                                onSubmit();
                              }
                            : null,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          remainingSeconds > 0
                              ? '${ref.t('login.otp_resend')} (${_formatOtpCountdown(remainingSeconds)})'
                              : ref.t('login.otp_resend'),
                          style: TextStyle(
                            color: canResend ? kPrimary : kTextLight,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            }
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Flexible supaya pada layar sempit (HP) baris ini tidak
                // overflow — checkbox + label boleh menyusut/ellipsis.
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: rememberMe,
                          builder: (_, active, _) => Checkbox(
                            value: active,
                            onChanged: (v) => rememberMe.value = v ?? false,
                            activeColor: kPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const Gap(8),
                      Flexible(
                        child: Text(
                          'Ingat saya',
                          style: TextStyle(color: kTextMid, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(8),
                Flexible(
                  child: TextButton(
                    onPressed: () async {
                      final email = await showModalBottomSheet<String>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) =>
                            ForgotPasswordSheet(initialEmail: userCtrl.text),
                      );
                      if (email != null &&
                          email.isNotEmpty &&
                          context.mounted) {
                        userCtrl.text = email;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Password berhasil direset. Silakan login dengan password baru.',
                            ),
                          ),
                        );
                      }
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      ref.t('login.forgot'),
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const Gap(32),
        ValueListenableBuilder<String?>(
          valueListenable: info,
          builder: (_, message, _) {
            if (message == null) return const SizedBox.shrink();
            return _InfoBanner(message: message);
          },
        ),
        ValueListenableBuilder<String?>(
          valueListenable: error,
          builder: (_, err, _) {
            if (err == null) return const SizedBox.shrink();
            return _ErrorBanner(message: err);
          },
        ),
        const Gap(8),
        ValueListenableBuilder<bool>(
          valueListenable: loading,
          builder: (_, isLoading, _) => ValueListenableBuilder<bool>(
            valueListenable: otpMode,
            builder: (_, useOtp, _) => ValueListenableBuilder<bool>(
              valueListenable: otpSent,
              builder: (_, sent, _) => SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: isLoading ? null : onSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : Text(
                          useOtp
                              ? (sent
                                    ? ref.t('login.otp_verify')
                                    : ref.t('login.otp_send'))
                              : ref.t('login.submit'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
        const Gap(24),
        _SecondaryActions(isTablet: isTablet),
      ],
    );
  }
}

String _formatOtpCountdown(int totalSeconds) {
  final seconds = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  final twoDigitMinutes = minutes.toString().padLeft(2, '0');
  final twoDigitSeconds = remainder.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$twoDigitMinutes:$twoDigitSeconds';
  }
  if (minutes > 0) {
    return '$minutes:$twoDigitSeconds';
  }
  return '${remainder}s';
}

class _SecondaryActions extends ConsumerWidget {
  final bool isTablet;
  const _SecondaryActions({required this.isTablet});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Atau masuk dengan',
                style: TextStyle(color: kTextLight, fontSize: 12),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const Gap(24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SocialBtn(Icons.g_mobiledata_rounded, 'Google', onTap: () {}),
          ],
        ),
        const Gap(32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              ref.t('login.no_account'),
              style: TextStyle(color: kTextMid, fontSize: 14),
            ),
            GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const RegisterSheet(),
                );
              },
              child: Text(
                ref.t('login.register'),
                style: const TextStyle(
                  color: kPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LoginModeSwitch extends ConsumerWidget {
  final bool useOtp;
  final ValueChanged<bool> onChanged;

  const _LoginModeSwitch({required this.useOtp, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kDivider),
      ),
      child: Row(
        children: [
          _LoginModeItem(
            active: !useOtp,
            label: ref.t('login.mode_password'),
            icon: Icons.lock_rounded,
            onTap: () => onChanged(false),
          ),
          _LoginModeItem(
            active: useOtp,
            label: ref.t('login.mode_otp'),
            icon: Icons.mail_lock_rounded,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _LoginModeItem extends StatelessWidget {
  final bool active;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _LoginModeItem({
    required this.active,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: active ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: active ? kPrimary : kTextMid),
                const Gap(6),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? kTextDark : kTextMid,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SocialBtn(this.icon, this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 28, color: kTextDark),
      label: Text(
        label,
        style: TextStyle(
          color: kTextDark,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: kDivider),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kDanger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kDanger.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: kDanger, size: 20),
          const Gap(10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: kDanger,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String message;
  const _InfoBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kSuccess.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kSuccess.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: kSuccess,
            size: 20,
          ),
          const Gap(10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: kSuccess,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomTextField extends ConsumerWidget {
  final TextEditingController controller;
  final String hint;
  final dynamic icon; // Can be IconAsset or IconData
  final bool obscure;
  final Widget? suffix;
  final Function(String)? onSubmitted;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _CustomTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.onSubmitted,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onSubmitted: onSubmitted,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: kTextLight,
            fontWeight: FontWeight.normal,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: icon is IconData
                ? Icon(icon as IconData, color: kPrimary, size: 22)
                : HugeIcon(icon: icon as IconAsset, color: kPrimary, size: 22),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0),
          suffixIcon: suffix,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }
}

class _InputLabel extends ConsumerWidget {
  final String label;
  const _InputLabel(this.label);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: kTextDark,
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

class _BrandingFooter extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        _FooterItem(Icons.security_rounded, ref.t('login.secure')),
        const Gap(24),
        _FooterItem(Icons.speed_rounded, ref.t('login.fast')),
        const Gap(24),
        _FooterItem(Icons.cloud_done_rounded, ref.t('login.cloud')),
        const Spacer(),
        const _LanguageSwitcher(),
      ],
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

class _FooterItem extends ConsumerWidget {
  final IconData icon;
  final String label;
  const _FooterItem(this.icon, this.label);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.5), size: 16),
        const Gap(6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
