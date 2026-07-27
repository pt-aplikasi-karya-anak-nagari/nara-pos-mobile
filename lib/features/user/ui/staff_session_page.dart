import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../data/auth_api_service.dart';
import '../data/auth_service.dart';

/// Mulai sesi kasir di perangkat bersama.
///
/// Satu tablet dipakai bergantian beberapa kasir. Alih-alih membagikan password
/// ke tiap orang (yang lalu beredar di perangkat bersama) atau membiarkan satu
/// sesi terbuka seharian (yang membuat semua transaksi tercatat atas nama orang
/// pertama), Pemilik/Manajer membuktikan kehadirannya, memilih siapa yang
/// bertugas, lalu menyetujui lewat kode email atau PIN.
///
/// Sesi yang terbit ATAS NAMA STAF — jadi jejak transaksi, shift, dan alert
/// anti-fraud menunjuk orang yang benar-benar bekerja.
class StaffSessionPage extends HookConsumerWidget {
  const StaffSessionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final langkah = useState(0); // 0=kredensial 1=pilih staf 2=verifikasi
    final emailCtrl = useTextEditingController();
    final passCtrl = useTextEditingController();
    final kodeCtrl = useTextEditingController();

    final sesi = useState<StaffSessionStart?>(null);
    final outletId = useState<String?>(null);
    final stafTerpilih = useState<StaffCandidate?>(null);
    final dikirimKe = useState<String?>(null);
    final loading = useState(false);
    final error = useState<String?>(null);

    Future<void> mulai({String? pilihOutlet}) async {
      final email = emailCtrl.text.trim();
      if (email.isEmpty || passCtrl.text.isEmpty) {
        error.value = 'Email dan password wajib diisi.';
        return;
      }
      loading.value = true;
      error.value = null;
      try {
        final res = await ref.read(authProvider.notifier).startStaffSession(
              email: email,
              password: passCtrl.text,
              outletId: pilihOutlet ?? outletId.value ?? '',
            );
        sesi.value = res;
        outletId.value = res.outletId.isEmpty ? null : res.outletId;
        // Outlet belum pasti (pengotorisasi punya lebih dari satu) → tetap di
        // langkah ini, tapi tampilkan pemilih outlet.
        langkah.value = res.outletId.isEmpty ? 0 : 1;
      } catch (e) {
        error.value = _pesan(e);
      } finally {
        loading.value = false;
      }
    }

    Future<void> mintaKode(StaffCandidate staf) async {
      loading.value = true;
      error.value = null;
      try {
        final ke = await ref.read(authProvider.notifier).requestStaffSessionOtp(
              challengeId: sesi.value!.challengeId,
              staffUserId: staf.id,
            );
        stafTerpilih.value = staf;
        dikirimKe.value = ke;
        langkah.value = 2;
      } catch (e) {
        // Kegagalan kirim email bukan jalan buntu: PIN tetap bisa dipakai,
        // jadi pengguna diantar ke layar verifikasi, bukan ditahan di sini.
        stafTerpilih.value = staf;
        dikirimKe.value = null;
        error.value = _pesan(e);
        langkah.value = 2;
      } finally {
        loading.value = false;
      }
    }

    Future<void> verifikasi() async {
      if (kodeCtrl.text.trim().isEmpty) {
        error.value = 'Masukkan kode dari email atau PIN otorisasi.';
        return;
      }
      loading.value = true;
      error.value = null;
      final msg = await ref.read(authProvider.notifier).verifyStaffSession(
            challengeId: sesi.value!.challengeId,
            staffUserId: stafTerpilih.value!.id,
            code: kodeCtrl.text,
          );
      loading.value = false;
      if (msg != null) {
        HapticFeedback.vibrate();
        error.value = msg;
        return;
      }
      HapticFeedback.mediumImpact();
      if (context.mounted) Navigator.of(context).pop(true);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mulai Sesi Kasir'),
        leading: IconButton(
          icon: HugeIcon(icon: AppIcons.chevronLeft, color: kTextDark),
          onPressed: () {
            if (langkah.value == 0) {
              Navigator.of(context).pop();
            } else {
              // Mundur satu langkah, bukan keluar — supaya salah pilih staf
              // tidak memaksa mengetik ulang password.
              error.value = null;
              kodeCtrl.clear();
              langkah.value = langkah.value - 1;
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Langkah(aktif: langkah.value),
              const Gap(20),
              if (error.value != null) ...[
                _Peringatan(pesan: error.value!),
                const Gap(14),
              ],
              if (langkah.value == 0)
                ..._kredensial(
                  context: context,
                  emailCtrl: emailCtrl,
                  passCtrl: passCtrl,
                  loading: loading.value,
                  outlets: sesi.value?.outlets ?? const [],
                  onLanjut: () => mulai(),
                  onPilihOutlet: (id) => mulai(pilihOutlet: id),
                )
              else if (langkah.value == 1)
                ..._daftarStaf(
                  sesi: sesi.value!,
                  loading: loading.value,
                  onPilih: mintaKode,
                )
              else
                ..._verifikasi(
                  staf: stafTerpilih.value!,
                  dikirimKe: dikirimKe.value,
                  kodeCtrl: kodeCtrl,
                  loading: loading.value,
                  onVerifikasi: verifikasi,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _pesan(Object e) {
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}

List<Widget> _kredensial({
  required BuildContext context,
  required TextEditingController emailCtrl,
  required TextEditingController passCtrl,
  required bool loading,
  required List<StaffOutletOption> outlets,
  required VoidCallback onLanjut,
  required void Function(String) onPilihOutlet,
}) {
  // Outlet muncul hanya kalau pengotorisasi memegang lebih dari satu; kalau
  // cuma satu, server sudah memilihkannya dan langkah ini tak perlu ada.
  final perluPilihOutlet = outlets.length > 1;
  return [
    Text(
      perluPilihOutlet ? 'Pilih outlet' : 'Masuk sebagai Pemilik / Manajer',
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
    const Gap(6),
    Text(
      perluPilihOutlet
          ? 'Akun Anda terhubung ke beberapa outlet. Pilih tempat perangkat ini dipakai.'
          : 'Masukkan email & password Anda untuk membuka sesi kasir di perangkat ini. '
              'Anda tidak akan masuk sebagai diri sendiri — Anda hanya menyetujui.',
      style: TextStyle(fontSize: 13, color: kTextMid, height: 1.5),
    ),
    const Gap(18),
    if (perluPilihOutlet)
      ...outlets.map(
        (o) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton(
            onPressed: loading ? null : () => onPilihOutlet(o.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(o.name),
            ),
          ),
        ),
      )
    else ...[
      TextField(
        controller: emailCtrl,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        enabled: !loading,
        decoration: const InputDecoration(
          labelText: 'Email',
          hintText: 'nama@email.com',
        ),
      ),
      const Gap(12),
      TextField(
        controller: passCtrl,
        obscureText: true,
        enabled: !loading,
        decoration: const InputDecoration(labelText: 'Password'),
      ),
      const Gap(20),
      FilledButton(
        onPressed: loading ? null : onLanjut,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(loading ? 'Memeriksa…' : 'Lanjut'),
        ),
      ),
    ],
  ];
}

List<Widget> _daftarStaf({
  required StaffSessionStart sesi,
  required bool loading,
  required void Function(StaffCandidate) onPilih,
}) {
  return [
    const Text(
      'Siapa yang bertugas?',
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
    const Gap(6),
    Text(
      'Disetujui oleh ${sesi.authorizerName}. Kode verifikasi akan dikirim ke '
      '${sesi.authorizerEmail}.',
      style: TextStyle(fontSize: 13, color: kTextMid, height: 1.5),
    ),
    const Gap(18),
    ...sesi.staff.map(
      (s) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          onTap: loading ? null : () => onPilih(s),
          leading: CircleAvatar(
            backgroundColor: kPrimary.withValues(alpha: 0.12),
            child: Text(
              s.fullName.isNotEmpty ? s.fullName[0].toUpperCase() : '?',
              style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700),
            ),
          ),
          title: Text(
            s.fullName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(s.role),
          trailing: HugeIcon(icon: AppIcons.chevronRight, color: kTextMid),
        ),
      ),
    ),
  ];
}

List<Widget> _verifikasi({
  required StaffCandidate staf,
  required String? dikirimKe,
  required TextEditingController kodeCtrl,
  required bool loading,
  required VoidCallback onVerifikasi,
}) {
  return [
    Text(
      'Setujui sesi ${staf.fullName}',
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    ),
    const Gap(6),
    Text(
      dikirimKe != null
          ? 'Kode 6 digit dikirim ke $dikirimKe. Masukkan kode itu, atau PIN '
              'otorisasi Anda kalau email belum bisa dibuka.'
          : 'Kode tidak terkirim. Masukkan PIN otorisasi Anda untuk melanjutkan.',
      style: TextStyle(fontSize: 13, color: kTextMid, height: 1.5),
    ),
    const Gap(18),
    TextField(
      controller: kodeCtrl,
      keyboardType: TextInputType.number,
      obscureText: true,
      enabled: !loading,
      decoration: const InputDecoration(
        labelText: 'Kode email atau PIN',
        hintText: '••••••',
      ),
    ),
    const Gap(20),
    FilledButton(
      onPressed: loading ? null : onVerifikasi,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(loading ? 'Memverifikasi…' : 'Mulai sesi'),
      ),
    ),
  ];
}

class _Langkah extends StatelessWidget {
  const _Langkah({required this.aktif});
  final int aktif;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (i) {
        final selesai = i < aktif;
        final kini = i == aktif;
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
            decoration: BoxDecoration(
              color: selesai || kini ? kPrimary : kPrimary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

class _Peringatan extends StatelessWidget {
  const _Peringatan({required this.pesan});
  final String pesan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kDanger.withValues(alpha: 0.08),
        border: Border.all(color: kDanger.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        pesan,
        style: const TextStyle(fontSize: 13, color: kDanger, height: 1.45),
      ),
    );
  }
}
