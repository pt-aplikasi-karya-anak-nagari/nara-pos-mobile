import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/theme.dart';
import '../../core/connectivity_service.dart';
import '../../core/offline/offline_sync_service.dart';
import '../../core/offline/sesi_offline.dart';
import '../../core/staff_device_storage.dart';
import '../../features/user/data/auth_service.dart';
import '../../features/user/ui/staff_session_page.dart'
    show pemindaiKodeProvider;
import '../../features/user/ui/widgets/keypad_kode.dart';

/// Verifikasi ulang sesi kasir yang dibuka saat offline, ke server.
///
/// Mengembalikan null bila berhasil (token asli tersimpan, sesi offline
/// berakhir, antrian mulai terkirim), atau pesan galat.
Future<String?> verifikasiUlangSesiOffline(
  WidgetRef ref, {
  String pin = '',
  String kartu = '',
}) async {
  final auth = ref.read(authProvider.notifier);
  final staffId = ref.read(authProvider).user?.remoteId ?? '';
  final token = await ref.read(staffDeviceStorageProvider).bacaToken();
  if (token == null || token.isEmpty) {
    return 'Tablet ini belum disahkan Pemilik. Keluar, lalu minta Pemilik '
        'masuk untuk membuka sesi.';
  }
  try {
    final mulai = await auth.resumeStaffSession(deviceToken: token);
    final galat = await auth.verifyStaffSession(
      challengeId: mulai.challengeId,
      // Kartu menyebutkan sendiri siapa pemiliknya.
      staffUserId: kartu.isEmpty ? staffId : '',
      code: pin,
      cardToken: kartu,
    );
    if (galat != null) return galat;
    final simpanan = ref.read(sesiOfflineStoreProvider);
    unawaited(
      simpanan.simpanDaftar(mulai.outletId, mulai.staff).catchError((_) {}),
    );
    if (pin.isNotEmpty) {
      unawaited(
        simpanan.simpanPin(mulai.outletId, staffId, pin).catchError((_) {}),
      );
    }
    // Antrian yang ditahan selama sesi offline kini boleh terkirim.
    unawaited(ref.read(offlineSyncServiceProvider).sync().then((_) {}));
    return null;
  } catch (e) {
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }
}

/// Banner "verifikasi ulang" — tampil selama sesi kasir dibuka offline TAPI
/// internet sudah kembali. Sampai staf terverifikasi, tak ada yang terkirim
/// (lihat dio_client): transaksinya aman di antrian, tapi juga belum sampai.
class BannerSesiOffline extends ConsumerWidget {
  const BannerSesiOffline({super.key, required this.konteksDialog});

  /// Konteks di bawah Navigator untuk membuka dialog — banner ini sendiri
  /// dipasang di atas Navigator (MaterialApp.builder).
  final BuildContext? Function() konteksDialog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final online =
        ref.watch(connectivityProvider).value == ConnectionStatus.online;
    final sesiOffline =
        auth.isAuthenticated && ref.read(authProvider.notifier).sesiOffline;
    if (!sesiOffline || !online) return const SizedBox.shrink();

    return Material(
      color: kWarning.withValues(alpha: 0.15),
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: () {
            final ctx = konteksDialog();
            if (ctx == null) return;
            showDialog<void>(
              context: ctx,
              builder: (_) => const _DialogVerifikasiUlang(),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.verified_user_outlined, size: 18, color: kWarning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Internet sudah kembali. ${auth.user?.name ?? 'Kasir'}, '
                    'verifikasi ulang supaya transaksi terkirim.',
                    style: TextStyle(fontSize: 13, color: kTextDark),
                  ),
                ),
                Text(
                  'Verifikasi',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kPrimary,
                    fontSize: 13,
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

class _DialogVerifikasiUlang extends HookConsumerWidget {
  const _DialogVerifikasiUlang();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pin = useState('');
    final loading = useState(false);
    final galat = useState<String?>(null);

    Future<void> kirim({String pinIsi = '', String kartu = ''}) async {
      loading.value = true;
      galat.value = null;
      final msg = await verifikasiUlangSesiOffline(
        ref,
        pin: pinIsi,
        kartu: kartu,
      );
      if (!context.mounted) return;
      loading.value = false;
      if (msg == null) {
        Navigator.of(context).pop();
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Sesi terverifikasi — transaksi offline dikirim.'),
          ),
        );
      } else {
        pin.value = '';
        galat.value = msg;
      }
    }

    return AlertDialog(
      title: const Text('Verifikasi ulang sesi'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sesi ini dibuka saat offline. Masukkan PIN Anda (atau scan '
              'kartu) supaya server mengesahkannya.',
              style: TextStyle(color: kTextMid, fontSize: 13, height: 1.4),
            ),
            if (galat.value != null) ...[
              const SizedBox(height: 10),
              Text(
                galat.value!,
                style: TextStyle(color: kDanger, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            KeypadKode(
              nilai: pin.value,
              aktif: !loading.value,
              onBerubah: (v) => pin.value = v,
              onPenuh: loading.value ? null : () => kirim(pinIsi: pin.value),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: loading.value
                  ? null
                  : () async {
                      final hasil = await ref.read(pemindaiKodeProvider)(
                        context,
                      );
                      if (hasil != null && hasil.trim().isNotEmpty) {
                        await kirim(kartu: hasil);
                      }
                    },
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const Text('Scan kartu karyawan'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: loading.value ? null : () => Navigator.of(context).pop(),
          child: const Text('Nanti'),
        ),
        FilledButton(
          onPressed: loading.value || pin.value.length < 4
              ? null
              : () => kirim(pinIsi: pin.value),
          child: Text(loading.value ? 'Memeriksa…' : 'Verifikasi'),
        ),
      ],
    );
  }
}
