import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../app/theme.dart';
import '../../data/auth_service.dart';
import '../../../../features/outlet/domain/outlet_type.dart';

class RegisterSheet extends HookConsumerWidget {
  const RegisterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userCtrl = useTextEditingController();
    final nameCtrl = useTextEditingController();
    final emailCtrl = useTextEditingController();
    final phoneCtrl = useTextEditingController();
    final passCtrl = useTextEditingController();
    final outletNameCtrl = useTextEditingController();
    final outletAddressCtrl = useTextEditingController();
    final outletPhoneCtrl = useTextEditingController();

    final outletTypes = useState<List<OutletType>>([]);
    final selectedType = useState<int?>(null);
    final loading = useState(false);
    final error = useState<String?>(null);
    final showPass = useState(false);

    useEffect(() {
      ref.read(authProvider.notifier).getOutletTypes().then((types) {
        outletTypes.value = types;
        if (types.isNotEmpty) selectedType.value = types.first.id;
      });
      return null;
    }, []);

    Future<void> submit() async {
      if (loading.value) return;
      error.value = null;

      if (userCtrl.text.trim().isEmpty ||
          nameCtrl.text.trim().isEmpty ||
          emailCtrl.text.trim().isEmpty ||
          phoneCtrl.text.trim().isEmpty ||
          passCtrl.text.isEmpty ||
          outletNameCtrl.text.trim().isEmpty ||
          outletAddressCtrl.text.trim().isEmpty ||
          outletPhoneCtrl.text.trim().isEmpty ||
          selectedType.value == null) {
        error.value = 'Semua data wajib diisi';
        return;
      }

      loading.value = true;
      final msg = await ref
          .read(authProvider.notifier)
          .register(
            username: userCtrl.text.trim(),
            fullName: nameCtrl.text.trim(),
            email: emailCtrl.text.trim(),
            phone: phoneCtrl.text.trim(),
            password: passCtrl.text,
            outletTypeId: selectedType.value!,
            outletName: outletNameCtrl.text.trim(),
            outletAddress: outletAddressCtrl.text.trim(),
            outletPhone: outletPhoneCtrl.text.trim(),
          );
      loading.value = false;

      if (msg != null) {
        error.value = msg;
      } else {
        if (context.mounted) Navigator.pop(context);
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        top: 12,
        left: 24,
        right: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: kPrimary,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimary.withValues(alpha: 0.2),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text(
                  'M',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const Gap(24),
            Text(
              'Daftar Akun Baru',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: kTextDark,
                letterSpacing: -0.5,
              ),
            ),
            const Gap(8),
            Text(
              'Mulai kelola bisnis Anda dengan mudah',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: kTextMid),
            ),
            const Gap(32),
            _SectionHeader(Icons.person_outline_rounded, 'Informasi Akun'),
            const Gap(16),
            _InputLabel('Username'),
            _CustomField(
              controller: userCtrl,
              hint: 'Contoh: udinx',
              icon: Icons.alternate_email_rounded,
            ),
            const Gap(20),
            _InputLabel('Nama Lengkap'),
            _CustomField(
              controller: nameCtrl,
              hint: 'Contoh: Udin Sedunia',
              icon: Icons.badge_outlined,
            ),
            const Gap(20),
            _InputLabel('Email'),
            _CustomField(
              controller: emailCtrl,
              hint: 'udinx@gmail.com',
              icon: Icons.email_outlined,
            ),
            const Gap(20),
            _InputLabel('No. Telepon'),
            _CustomField(
              controller: phoneCtrl,
              hint: '0852567373',
              icon: Icons.phone_android_outlined,
            ),
            const Gap(32),
            _SectionHeader(Icons.storefront_rounded, 'Informasi Outlet'),
            const Gap(16),
            _InputLabel('Tipe Bisnis'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kDivider),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: selectedType.value,
                  isExpanded: true,
                  hint: const Text('Pilih Tipe Bisnis'),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: kPrimary,
                  ),
                  items: outletTypes.value.map<DropdownMenuItem<int>>((
                    OutletType t,
                  ) {
                    return DropdownMenuItem<int>(
                      value: t.id,
                      child: Text(
                        '${t.name} - ${t.description}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: kTextDark,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) => selectedType.value = val,
                ),
              ),
            ),
            const Gap(20),
            _InputLabel('Nama Outlet'),
            _CustomField(
              controller: outletNameCtrl,
              hint: 'Contoh: NARA Coffee Lab',
              icon: Icons.store_outlined,
            ),
            const Gap(20),
            _InputLabel('Alamat Outlet'),
            _CustomField(
              controller: outletAddressCtrl,
              hint: 'Jl. Sudirman No. 123, Jakarta',
              icon: Icons.location_on_outlined,
            ),
            const Gap(20),
            _InputLabel('No. Telepon Outlet'),
            _CustomField(
              controller: outletPhoneCtrl,
              hint: '021-555666',
              icon: Icons.phone_outlined,
            ),
            const Gap(32),
            _SectionHeader(Icons.lock_outline_rounded, 'Keamanan Akun'),
            const Gap(16),
            _InputLabel('Password'),
            ValueListenableBuilder<bool>(
              valueListenable: showPass,
              builder: (_, show, _) => _CustomField(
                controller: passCtrl,
                hint: '••••••••',
                icon: Icons.lock_outline,
                obscure: !show,
                suffix: IconButton(
                  onPressed: () => showPass.value = !show,
                  icon: Icon(
                    show ? Icons.visibility_off : Icons.visibility,
                    color: kTextMid,
                    size: 20,
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: error,
              builder: (_, err, _) {
                if (err == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: kDanger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kDanger.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: kDanger,
                          size: 20,
                        ),
                        const Gap(10),
                        Expanded(
                          child: Text(
                            err,
                            style: const TextStyle(
                              color: kDanger,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const Gap(32),
            ValueListenableBuilder<bool>(
              valueListenable: loading,
              builder: (_, isLoading, _) => SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: isLoading ? null : submit,
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
                      : const Text(
                          'Daftar Sekarang',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ),
            const Gap(24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Sudah punya akun? ',
                  style: TextStyle(color: kTextMid, fontSize: 13),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text(
                    'Masuk',
                    style: TextStyle(
                      color: kPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader(this.icon, this.title);
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: kPrimary),
        const Gap(10),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: kTextDark,
          ),
        ),
      ],
    );
  }
}

class _InputLabel extends StatelessWidget {
  final String label;
  const _InputLabel(this.label);
  @override
  Widget build(BuildContext context) {
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

class _CustomField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;

  const _CustomField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: kTextLight,
            fontWeight: FontWeight.normal,
          ),
          prefixIcon: Icon(icon, color: kPrimary, size: 22),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }
}
