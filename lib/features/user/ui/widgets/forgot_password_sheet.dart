import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../app/theme.dart';
import '../../data/auth_api_service.dart';

/// Bottom sheet alur "Lupa Password".
///
/// Dua langkah:
///   1. Masukkan email → POST /password/forgot → backend mengirim link
///      reset ke email (selalu sukses generic, tidak membocorkan apakah
///      email terdaftar).
///   2. (Opsional) User menempel token dari email + password baru →
///      POST /password/reset → selesai tanpa harus buka web.
///
/// Mengembalikan email (String) lewat Navigator.pop bila reset berhasil,
/// supaya halaman login bisa pre-fill field email.
class ForgotPasswordSheet extends ConsumerStatefulWidget {
  final String initialEmail;
  const ForgotPasswordSheet({super.key, this.initialEmail = ''});

  @override
  ConsumerState<ForgotPasswordSheet> createState() =>
      _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends ConsumerState<ForgotPasswordSheet> {
  late final TextEditingController _emailCtrl;
  final _tokenCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _sent = false; // sudah kirim permintaan reset?
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail.trim());
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _tokenCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  bool get _emailValid {
    final e = _emailCtrl.text.trim();
    return e.contains('@') && e.contains('.');
  }

  Future<void> _requestReset() async {
    if (!_emailValid) {
      setState(() => _error = 'Masukkan email yang valid');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authApiServiceProvider)
          .requestPasswordReset(_emailCtrl.text.trim());
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final token = _tokenCtrl.text.trim();
    final pass = _passCtrl.text;
    if (token.isEmpty) {
      setState(() => _error = 'Token reset wajib diisi');
      return;
    }
    if (pass.length < 8) {
      setState(() => _error = 'Password minimal 8 karakter');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authApiServiceProvider).resetPassword(token, pass);
      if (mounted) Navigator.of(context).pop(_emailCtrl.text.trim());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Gap(18),
            Text(
              _sent ? 'Reset Password' : 'Lupa Password',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: kTextDark,
              ),
            ),
            const Gap(6),
            Text(
              _sent
                  ? 'Kami telah mengirim link reset ke email Anda. Buka link tersebut, '
                        'atau tempel token dari email di bawah untuk mengatur ulang password di sini.'
                  : 'Masukkan email akun Anda. Kami akan mengirim link untuk mengatur ulang password.',
              style: TextStyle(fontSize: 13, color: kTextMid, height: 1.4),
            ),
            const Gap(18),

            // ── Email ──
            _Field(
              controller: _emailCtrl,
              label: 'Email',
              hint: 'nama@email.com',
              keyboardType: TextInputType.emailAddress,
              enabled: !_sent && !_loading,
              icon: Icons.alternate_email_rounded,
            ),

            if (_sent) ...[
              const Gap(12),
              _Field(
                controller: _tokenCtrl,
                label: 'Token Reset (dari email)',
                hint: 'Tempel token di sini',
                enabled: !_loading,
                icon: Icons.vpn_key_rounded,
              ),
              const Gap(12),
              _Field(
                controller: _passCtrl,
                label: 'Password Baru',
                hint: 'Minimal 8 karakter',
                enabled: !_loading,
                obscure: _obscure,
                icon: Icons.lock_outline_rounded,
                suffix: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                    color: kTextMid,
                  ),
                ),
              ),
            ],

            if (_error != null) ...[
              const Gap(12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kDanger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: kDanger),
                ),
              ),
            ],

            const Gap(20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _loading
                    ? null
                    : (_sent ? _resetPassword : _requestReset),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _sent ? 'Reset Password' : 'Kirim Link Reset',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
            if (_sent) ...[
              const Gap(8),
              Center(
                child: TextButton(
                  onPressed: _loading ? null : _requestReset,
                  child: Text(
                    'Kirim ulang link',
                    style: TextStyle(
                      color: kPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool enabled;
  final bool obscure;
  final IconData icon;
  final Widget? suffix;
  final TextInputType? keyboardType;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.enabled = true,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: kTextMid,
          ),
        ),
        const Gap(6),
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscure,
          keyboardType: keyboardType,
          style: TextStyle(fontSize: 14, color: kTextDark),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: kTextLight),
            prefixIcon: Icon(icon, size: 20, color: kTextMid),
            suffixIcon: suffix,
            filled: true,
            fillColor: kBg,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
