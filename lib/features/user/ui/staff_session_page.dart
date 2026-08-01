import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/staff_device_storage.dart';
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
class StaffSessionPage extends StatelessWidget {
  const StaffSessionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mulai Sesi Kasir')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: StaffSessionFlow(
            onSelesai: () => Navigator.of(context).pop(true),
          ),
        ),
      ),
    );
  }
}

/// Alur tiga langkah tanpa Scaffold, supaya bisa disematkan langsung di
/// halaman login (perangkat kasir tak punya jalan masuk lain) maupun dibuka
/// sebagai halaman tersendiri.
class StaffSessionFlow extends HookConsumerWidget {
  const StaffSessionFlow({super.key, required this.onSelesai});

  /// Dipanggil setelah sesi staf berhasil dibuat & tersimpan.
  final VoidCallback onSelesai;

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
    /// Kabar baik yang berumur pendek ("kode baru dikirim"), dipisah dari
    /// [error] supaya keduanya tak pernah tampil sebagai satu kotak yang sama.
    final catatan = useState<String?>(null);
    /// Sisa detik sebelum kode boleh diminta lagi.
    ///
    /// Server TIDAK membatasi endpoint ini — beda dari OTP login biasa yang
    /// punya cooldown bertingkat. Tanpa jeda di sini, satu ketukan berulang
    /// mengirim email sungguhan sebanyak ketukannya.
    final jeda = useState(0);

    // Nama outlet perangkat yang tersimpan. Non-null berarti perangkat ini
    // sudah disahkan, sehingga langkah password dilewati.
    final outletPerangkat = useState<String?>(null);
    // Menahan layar saat pengesahan tersimpan sedang dicoba, supaya form
    // password tidak berkedip muncul sepersekian detik sebelum tergantikan.
    final memeriksaPerangkat = useState(true);

    final penyimpananPerangkat = ref.read(staffDeviceStorageProvider);

    Future<void> mulai({String? pilihOutlet}) async {
      final email = emailCtrl.text.trim();
      if (email.isEmpty || passCtrl.text.isEmpty) {
        error.value = 'Email dan password wajib diisi.';
        return;
      }
      loading.value = true;
      error.value = null;
      try {
        final res = await ref
            .read(authProvider.notifier)
            .startStaffSession(
              email: email,
              password: passCtrl.text,
              outletId: pilihOutlet ?? outletId.value ?? '',
            );
        sesi.value = res;
        outletId.value = res.outletId.isEmpty ? null : res.outletId;

        // Sahkan perangkat begitu outlet pasti — inilah momen pengelola
        // terbukti DAN outletnya tertentu. Password tak akan diminta lagi
        // sampai token dicabut. Kalau outlet masih harus dipilih, server belum
        // menerbitkan token dan simpan() memang tak melakukan apa-apa.
        if (res.deviceToken.isNotEmpty && res.outletId.isNotEmpty) {
          final nama = res.outlets
              .where((o) => o.id == res.outletId)
              .map((o) => o.name)
              .firstOrNull;
          await penyimpananPerangkat.simpan(
            token: res.deviceToken,
            outletId: res.outletId,
            outletName: nama ?? '',
          );
          outletPerangkat.value = nama ?? '';
        }

        // Outlet belum pasti (pengotorisasi punya lebih dari satu) → tetap di
        // langkah ini, tapi tampilkan pemilih outlet.
        langkah.value = res.outletId.isEmpty ? 0 : 1;
      } catch (e) {
        error.value = _pesan(e);
      } finally {
        loading.value = false;
      }
    }

    /// Lepas pengesahan perangkat lalu kembali ke layar password.
    ///
    /// Dipakai dua arah: saat server menolak token (dicabut / pengelola tak
    /// lagi berwenang), dan saat pengguna sengaja ingin masuk sebagai pengelola
    /// lain. Tanpa jalan keluar ini, perangkat yang sudah disahkan jadi pintu
    /// satu arah yang hanya bisa dibatalkan dengan menghapus data aplikasi.
    Future<void> lepasPerangkat({String? pesan}) async {
      await penyimpananPerangkat.hapus();
      outletPerangkat.value = null;
      sesi.value = null;
      outletId.value = null;
      stafTerpilih.value = null;
      kodeCtrl.clear();
      langkah.value = 0;
      error.value = pesan;
    }

    // Coba lanjutkan dengan pengesahan tersimpan, sekali saat layar dibuka.
    useEffect(() {
      var dibatalkan = false;
      Future<void> coba() async {
        final token = await penyimpananPerangkat.bacaToken();
        if (dibatalkan) return;
        if (token == null) {
          memeriksaPerangkat.value = false;
          return;
        }
        try {
          final res = await ref
              .read(authProvider.notifier)
              .resumeStaffSession(deviceToken: token);
          if (dibatalkan) return;
          sesi.value = res;
          outletId.value = res.outletId;
          outletPerangkat.value =
              await penyimpananPerangkat.bacaOutletName() ?? '';
          langkah.value = 1; // langsung ke pemilihan staf
        } catch (e) {
          if (dibatalkan) return;
          // Token ditolak: dicabut, pengelola dinonaktifkan, atau aksesnya ke
          // outlet dicabut. Buang pengesahannya dan minta login pengelola —
          // menyimpan token yang sudah pasti ditolak hanya akan mengulang
          // kegagalan yang sama tiap perangkat dibuka.
          await lepasPerangkat(pesan: _pesan(e));
        } finally {
          if (!dibatalkan) memeriksaPerangkat.value = false;
        }
      }

      coba();
      return () => dibatalkan = true;
    }, const []);

    // Hitung mundur jeda kirim ulang. Dependensinya sengaja "sedang berjalan
    // atau tidak", bukan angkanya: timer dibuat sekali saat jeda menyala dan
    // dibatalkan sekali saat ia habis, bukan dibongkar-pasang tiap detik.
    useEffect(() {
      if (jeda.value <= 0) return null;
      final t = Timer.periodic(const Duration(seconds: 1), (_) {
        if (jeda.value > 0) jeda.value = jeda.value - 1;
      });
      return t.cancel;
    }, [jeda.value > 0]);

    Future<void> mintaKode(StaffCandidate staf) async {
      loading.value = true;
      error.value = null;
      try {
        final ke = await ref
            .read(authProvider.notifier)
            .requestStaffSessionOtp(
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

    /// Minta kode baru tanpa meninggalkan layar ini.
    ///
    /// Sebelumnya satu-satunya cara adalah menekan "Kembali", memilih ulang
    /// stafnya, lalu mengetik ulang — dan pada perangkat yang belum disahkan
    /// itu berarti mengetik ulang password Pemilik. Kode yang telat sampai
    /// atau terlanjur terhapus jadi jalan buntu.
    ///
    /// Server MEMPERTAHANKAN sisa waktu tantangan, tidak memperpanjangnya.
    /// Jadi tombol ini menolong kasus "kodenya tak sampai", bukan
    /// "waktunya habis" — untuk yang kedua server menjawab "ulangi dari awal",
    /// dan pesan itu diteruskan apa adanya.
    Future<void> kirimUlang() async {
      final staf = stafTerpilih.value;
      final s = sesi.value;
      if (staf == null || s == null || jeda.value > 0 || loading.value) return;

      loading.value = true;
      error.value = null;
      catatan.value = null;
      try {
        final ke = await ref
            .read(authProvider.notifier)
            .requestStaffSessionOtp(challengeId: s.challengeId, staffUserId: staf.id);
        dikirimKe.value = ke;
        // Kode lama sudah tak berlaku begitu yang baru terbit — membiarkannya
        // terketik akan membuat percobaan pertama pasti gagal.
        kodeCtrl.clear();
        catatan.value = 'Kode baru dikirim ke $ke.';
        jeda.value = 30;
      } catch (e) {
        error.value = _pesan(e);
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
      final msg = await ref
          .read(authProvider.notifier)
          .verifyStaffSession(
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
      onSelesai();
    }

    // Pengesahan tersimpan masih diperiksa — jangan tampilkan form password
    // dulu, karena sebentar lagi bisa tergantikan layar pemilihan staf.
    if (memeriksaPerangkat.value) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final perangkatDisahkan = outletPerangkat.value != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Langkah password disembunyikan pada perangkat yang sudah disahkan:
        // menampilkan tahap yang tak akan pernah dilalui hanya membingungkan.
        _Langkah(
          aktif: langkah.value,
          sembunyikanKredensial: perangkatDisahkan,
        ),
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
            catatan: catatan.value,
            jeda: jeda.value,
            onKirimUlang: kirimUlang,
          ),
        // "Kembali" hanya bermakna kalau ada langkah sebelumnya yang bisa
        // dituju. Pada perangkat yang sudah disahkan, langkah 1 adalah yang
        // paling awal — mundur ke form password akan menuntut sesuatu yang
        // justru sudah tidak diperlukan.
        if (langkah.value > (perangkatDisahkan ? 1 : 0)) ...[
          const Gap(10),
          TextButton(
            // Mundur satu langkah, bukan keluar — salah pilih staf tak boleh
            // memaksa mengetik ulang password.
            onPressed: loading.value
                ? null
                : () {
                    error.value = null;
                    catatan.value = null;
                    kodeCtrl.clear();
                    langkah.value = langkah.value - 1;
                  },
            child: const Text('Kembali'),
          ),
        ],
        if (perangkatDisahkan) ...[
          const Gap(4),
          _PerangkatTerdaftar(
            namaOutlet: outletPerangkat.value!,
            loading: loading.value,
            onLepas: () => lepasPerangkat(),
          ),
        ],
      ],
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
      perluPilihOutlet ? 'Pilih outlet' : 'Masuk sebagai Pemilik',
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
              style: const TextStyle(
                color: kPrimary,
                fontWeight: FontWeight.w700,
              ),
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
  required String? catatan,
  required int jeda,
  required VoidCallback onKirimUlang,
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
    // Kabar "kode baru dikirim" berdiri sendiri, tidak menumpang kotak error.
    // Menampilkan keberhasilan dengan warna kegagalan membuat orang mengira
    // permintaannya gagal padahal emailnya sudah di jalan.
    if (catatan != null) ...[
      const Gap(10),
      Row(
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: kSuccess),
          const Gap(6),
          Expanded(
            child: Text(
              catatan,
              style: TextStyle(fontSize: 12, color: kSuccess),
            ),
          ),
        ],
      ),
    ],
    const Gap(20),
    FilledButton(
      onPressed: loading ? null : onVerifikasi,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(loading ? 'Memverifikasi…' : 'Mulai sesi'),
      ),
    ),
    const Gap(4),
    // Jeda 30 detik supaya satu ketukan berulang tidak mengirim email
    // sungguhan sebanyak ketukannya — endpoint ini tak dibatasi server.
    // Hitungannya ditulis di label, bukan disembunyikan: tombol mati tanpa
    // alasan terbaca sebagai aplikasi yang macet.
    TextButton(
      onPressed: (loading || jeda > 0) ? null : onKirimUlang,
      child: Text(
        jeda > 0 ? 'Kirim ulang kode dalam $jeda dtk' : 'Kirim ulang kode',
      ),
    ),
  ];
}

class _Langkah extends StatelessWidget {
  const _Langkah({required this.aktif, this.sembunyikanKredensial = false});
  final int aktif;

  /// Pada perangkat yang sudah disahkan, langkah password tidak pernah dilalui.
  /// Menampilkannya sebagai tahap yang harus dilewati justru menyesatkan.
  final bool sembunyikanKredensial;

  @override
  Widget build(BuildContext context) {
    final mulaiDari = sembunyikanKredensial ? 1 : 0;
    final jumlah = 3 - mulaiDari;
    return Row(
      children: List.generate(jumlah, (idx) {
        final i = idx + mulaiDari;
        final selesai = i < aktif;
        final kini = i == aktif;
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: idx < jumlah - 1 ? 6 : 0),
            decoration: BoxDecoration(
              color: selesai || kini
                  ? kPrimary
                  : kPrimary.withValues(alpha: 0.15),
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

/// Keterangan perangkat yang sudah disahkan + jalan keluarnya.
///
/// Ada dua alasan ini harus terlihat, bukan sekadar bekerja diam-diam:
///
///   - Kasir perlu tahu perangkat ini terikat outlet mana. Salah outlet berarti
///     transaksi masuk ke pembukuan cabang lain, dan itu baru ketahuan saat
///     tutup buku.
///   - Pengesahan perangkat harus bisa dilepas dari layar ini. Tanpa itu,
///     satu-satunya cara berpindah pengelola/outlet adalah menghapus data
///     aplikasi — yang juga membuang antrean transaksi offline.
class _PerangkatTerdaftar extends StatelessWidget {
  const _PerangkatTerdaftar({
    required this.namaOutlet,
    required this.loading,
    required this.onLepas,
  });

  final String namaOutlet;
  final bool loading;
  final VoidCallback onLepas;

  @override
  Widget build(BuildContext context) {
    final label = namaOutlet.isEmpty
        ? 'Perangkat ini sudah terdaftar'
        : 'Perangkat ini terdaftar di $namaOutlet';
    return Column(
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
          ),
        ),
        TextButton(
          onPressed: loading ? null : () => _konfirmasi(context),
          child: const Text('Masuk sebagai pengelola lain'),
        ),
      ],
    );
  }

  /// Dikonfirmasi dulu: melepas perangkat berarti pengelola harus hadir lagi
  /// dengan passwordnya, dan di tengah jam sibuk itu bukan hal yang boleh
  /// terjadi karena salah sentuh.
  Future<void> _konfirmasi(BuildContext context) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lepas perangkat ini?'),
        content: const Text(
          'Pemilik harus memasukkan email dan password lagi untuk '
          'membuka sesi kasir berikutnya di perangkat ini.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lepas'),
          ),
        ],
      ),
    );
    if (ya == true) onLepas();
  }
}
