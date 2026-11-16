import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../app/theme.dart';
import '../../data/auth_api_service.dart';

/// Bottom sheet "Lupa password" Pemilik — HANYA mengirim tautan ke email.
///
/// Password baru dibuat di halaman web yang dibuka dari tautan itu, bukan di
/// aplikasi kasir. Alasannya keamanan: perangkat kasir dipakai bersama dan
/// layarnya menghadap pelanggan, jadi password yang juga membuka dashboard
/// web tak semestinya diketik di sini. Token reset pun tak pernah ditempel
/// ke aplikasi — ia hanya hidup di tautan email (sekali pakai, 30 menit).
///
/// Jawaban server selalu sama, terdaftar atau tidak, supaya sheet ini tak
/// bisa dipakai menebak email Pemilik.
class ForgotPasswordSheet extends ConsumerStatefulWidget {
  final String initialEmail;
  const ForgotPasswordSheet({super.key, this.initialEmail = ''});

  @override
  ConsumerState<ForgotPasswordSheet> createState() =>
      _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends ConsumerState<ForgotPasswordSheet> {
  late final TextEditingController _emailCtrl;

  /// Email tujuan tautan terakhir; non-null = layar konfirmasi.
  String? _terkirimKe;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail.trim());
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  bool get _emailValid =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_emailCtrl.text.trim());

  Future<void> _kirimTautan() async {
    if (!_emailValid) {
      setState(() => _error = 'Masukkan email yang valid, mis. nama@email.com');
      return;
    }
    final email = _emailCtrl.text.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authApiServiceProvider).requestPasswordReset(email);
      if (mounted) setState(() => _terkirimKe = email);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final terkirim = _terkirimKe != null;
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
              terkirim ? 'Cek email Anda' : 'Lupa password',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: kTextDark,
              ),
            ),
            const Gap(6),
            if (!terkirim) ...[
              Text(
                'Masukkan email akun Pemilik. Kami kirim tautan untuk membuat '
                'password baru di website.',
                style: TextStyle(fontSize: 13, color: kTextMid, height: 1.4),
              ),
              const Gap(18),
              _Field(
                key: const ValueKey('lupa-email'),
                controller: _emailCtrl,
                label: 'Email',
                hint: 'nama@email.com',
                keyboardType: TextInputType.emailAddress,
                enabled: !_loading,
                icon: Icons.alternate_email_rounded,
                onSubmitted: (_) => _loading ? null : _kirimTautan(),
              ),
            ] else
              _Konfirmasi(email: _terkirimKe!),
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
                key: const ValueKey('lupa-kirim'),
                onPressed: _loading
                    ? null
                    : (terkirim
                          ? () => Navigator.of(context).pop(_terkirimKe)
                          : _kirimTautan),
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
                        terkirim ? 'Selesai' : 'Kirim tautan ubah password',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
            if (terkirim) ...[
              const Gap(8),
              Center(
                child: TextButton(
                  // Server menahan permintaan beruntun (jeda 1 menit per
                  // email) — tombol ini aman ditekan, tapi email baru hanya
                  // datang setelah jedanya lewat.
                  onPressed: _loading
                      ? null
                      : () => setState(() {
                          _terkirimKe = null;
                          _error = null;
                        }),
                  child: Text(
                    'Belum menerima? Kirim ulang',
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

/// Isi layar konfirmasi: apa yang terjadi & langkah berikutnya.
class _Konfirmasi extends StatelessWidget {
  const _Konfirmasi({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    final gaya = TextStyle(fontSize: 13, color: kTextMid, height: 1.45);
    Widget langkah(String nomor, String teks) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              nomor,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: kPrimary,
              ),
            ),
          ),
          const Gap(10),
          Expanded(child: Text(teks, style: gaya)),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: gaya,
            children: [
              const TextSpan(text: 'Jika '),
              TextSpan(
                text: email,
                style: TextStyle(fontWeight: FontWeight.w700, color: kTextDark),
              ),
              const TextSpan(
                text:
                    ' terdaftar sebagai akun Pemilik, tautan ubah password '
                    'sudah kami kirim.',
              ),
            ],
          ),
        ),
        const Gap(6),
        langkah('1', 'Buka email dari NARA (cek juga folder Spam/Promosi).'),
        langkah(
          '2',
          'Ketuk "Buat Password Baru" — tautan berlaku 30 menit dan hanya '
              'bisa dipakai sekali.',
        ),
        langkah(
          '3',
          'Buat password baru di website. Semua perangkat yang sedang login '
              'otomatis dikeluarkan.',
        ),
        const Gap(10),
        Text(
          'Untuk masuk di aplikasi kasir, Anda tetap memakai PIN Otorisasi — '
          'bukan password.',
          style: TextStyle(fontSize: 12, color: kTextLight, height: 1.4),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool enabled;
  final IconData icon;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  const _Field({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.enabled = true,
    this.keyboardType,
    this.onSubmitted,
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
          keyboardType: keyboardType,
          autocorrect: false,
          onSubmitted: onSubmitted,
          style: TextStyle(fontSize: 14, color: kTextDark),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: kTextLight),
            prefixIcon: Icon(icon, size: 20, color: kTextMid),
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
