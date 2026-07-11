import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../../user/data/auth_api_service.dart';

/// Status PIN otorisasi milik user yang sedang login (GET /me/pin).
/// True bila user sudah pernah menyetel PIN. Auto-refetch saat di-invalidate
/// setelah simpan/hapus PIN.
final myPinStatusProvider = FutureProvider<bool>((ref) async {
  return ref.watch(authApiServiceProvider).getMyPinStatus();
});

/// Halaman "PIN Otorisasi" — self-service agar user menyetel / mengubah /
/// menghapus PIN miliknya sendiri. PIN dipakai untuk mengesahkan aksi sensitif
/// (void / refund) saat outlet mewajibkan otorisasi manajer.
///
/// Endpoint backend: `POST /me/pin` (set/ubah/hapus) & `GET /me/pin` (status).
/// PIN 4-6 digit angka; menghapus = mengirim string kosong.
class PinSettingsPage extends HookConsumerWidget {
  const PinSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final statusAsync = ref.watch(myPinStatusProvider);

    final pinController = useTextEditingController();
    final confirmController = useTextEditingController();
    final saving = useState(false);
    // Force rebuild saat isi field berubah supaya tombol Simpan aktif/nonaktif.
    final pin = useState('');
    final confirm = useState('');

    final pinValid = pin.value.length >= 4 && pin.value.length <= 6;
    final matches = pin.value == confirm.value;
    final canSave = pinValid && matches && !saving.value;

    Future<void> savePin() async {
      if (!canSave) return;
      saving.value = true;
      try {
        await ref.read(authApiServiceProvider).setMyPin(pin.value);
        ref.invalidate(myPinStatusProvider);
        pinController.clear();
        confirmController.clear();
        pin.value = '';
        confirm.value = '';
        if (context.mounted) {
          FocusScope.of(context).unfocus();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PIN otorisasi disimpan'),
              backgroundColor: kSuccess,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menyimpan PIN: $e'),
              backgroundColor: kDanger,
            ),
          );
        }
      } finally {
        saving.value = false;
      }
    }

    Future<void> deletePin() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Hapus PIN otorisasi?',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Setelah dihapus, Anda tidak bisa lagi mengesahkan void/refund '
            'yang mensyaratkan PIN sampai menyetel PIN baru.',
            style: TextStyle(color: kTextMid, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: kDanger),
              child: const Text('Ya, Hapus'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      saving.value = true;
      try {
        // String kosong = perintah hapus PIN di backend.
        await ref.read(authApiServiceProvider).setMyPin('');
        ref.invalidate(myPinStatusProvider);
        pinController.clear();
        confirmController.clear();
        pin.value = '';
        confirm.value = '';
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PIN otorisasi dihapus'),
              backgroundColor: kSuccess,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal menghapus PIN: $e'),
              backgroundColor: kDanger,
            ),
          );
        }
      } finally {
        saving.value = false;
      }
    }

    final hasPin = statusAsync.value ?? false;

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
                icon: AppIcons.accessRights,
                color: kPrimary,
                title: 'PIN Otorisasi',
                subtitle:
                    'PIN 4-6 digit untuk mengesahkan void/refund saat outlet '
                    'mensyaratkan otorisasi manajer.',
              ),
              // Kartu status PIN saat ini.
              statusAsync.when(
                loading: () => const _StatusCard(
                  loading: true,
                  hasPin: false,
                ),
                error: (e, _) => _StatusCard(
                  loading: false,
                  hasPin: false,
                  errorText: 'Gagal memuat status PIN: $e',
                ),
                data: (has) => _StatusCard(loading: false, hasPin: has),
              ),
              const Gap(20),
              _SectionHeader(hasPin ? 'Ubah PIN' : 'Buat PIN'),
              _PinField(
                controller: pinController,
                label: 'PIN Baru',
                hint: '4-6 digit angka',
                onChanged: (v) => pin.value = v,
              ),
              const Gap(12),
              _PinField(
                controller: confirmController,
                label: 'Ulangi PIN',
                hint: 'Ketik ulang PIN',
                onChanged: (v) => confirm.value = v,
              ),
              if (confirm.value.isNotEmpty && !matches) ...[
                const Gap(8),
                Text(
                  'PIN tidak sama',
                  style: TextStyle(
                    color: kDanger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Gap(20),
              FilledButton(
                onPressed: canSave ? savePin : null,
                style: FilledButton.styleFrom(
                  backgroundColor: kPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: saving.value
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(hasPin ? 'Simpan PIN Baru' : 'Simpan PIN'),
              ),
              if (hasPin) ...[
                const Gap(10),
                TextButton(
                  onPressed: saving.value ? null : deletePin,
                  style: TextButton.styleFrom(foregroundColor: kDanger),
                  child: const Text('Hapus PIN'),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('PIN Otorisasi'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: body,
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool loading;
  final bool hasPin;
  final String? errorText;
  const _StatusCard({
    required this.loading,
    required this.hasPin,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    final IconData icon;
    if (loading) {
      color = kTextMid;
      label = 'Memeriksa status PIN...';
      icon = Icons.hourglass_empty_rounded;
    } else if (errorText != null) {
      color = kDanger;
      label = errorText!;
      icon = Icons.error_outline_rounded;
    } else if (hasPin) {
      color = kSuccess;
      label = 'PIN sudah diatur';
      icon = Icons.check_circle_rounded;
    } else {
      color = kTextMid;
      label = 'PIN belum diatur';
      icon = Icons.lock_open_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const Gap(10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
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

class _PinField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;
  const _PinField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        filled: true,
        fillColor: kCard,
        prefixIcon: Icon(Icons.lock_outline_rounded, color: kTextMid),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
