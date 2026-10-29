import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/offline/sale_outbox.dart' show isOfflineError;
import '../../../core/offline/sesi_offline.dart';
import '../../../core/staff_device_storage.dart';
import '../../settings/data/app_settings.dart';
import '../data/auth_api_service.dart';
import '../../products/ui/barcode_scanner_page.dart';
import '../data/auth_service.dart';
import 'widgets/keypad_kode.dart';

/// Pembuka pemindai kode.
///
/// Provider, bukan panggilan Navigator langsung, supaya tes bisa
/// menggantinya. Tanpa ini jalur kartu hanya bisa diuji dengan kamera
/// sungguhan — artinya tak pernah diuji, dan token yang diam-diam tak
/// diteruskan tak akan tertangkap apa pun.
final pemindaiKodeProvider = Provider<Future<String?> Function(BuildContext)>(
  (ref) =>
      (context) => Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
      ),
);

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
    final loading = useState(false);
    final error = useState<String?>(null);

    // Nama outlet perangkat yang tersimpan. Non-null berarti perangkat ini
    // sudah disahkan, sehingga langkah password dilewati.
    final outletPerangkat = useState<String?>(null);
    // Menahan layar saat pengesahan tersimpan sedang dicoba, supaya form
    // password tidak berkedip muncul sepersekian detik sebelum tergantikan.
    final memeriksaPerangkat = useState(true);

    final penyimpananPerangkat = ref.read(staffDeviceStorageProvider);
    final simpananOffline = ref.read(sesiOfflineStoreProvider);

    // Tablet offline: pilih staf & cocokkan kartu/PIN di perangkat (lihat
    // core/offline/sesi_offline.dart). Sesinya diverifikasi ulang server
    // begitu internet kembali.
    final modeOffline = useState(false);

    /// Masuk mode offline dari pengesahan perangkat yang tersimpan. Pesan
    /// galat bila tak bisa (dimatikan Pemilik / belum ada data staf).
    Future<String?> masukModeOffline() async {
      final idOutlet = await penyimpananPerangkat.bacaOutletId() ?? '';
      if (idOutlet.isEmpty) return null;
      final pengaturan = await bacaAppSettingsTersimpan(idOutlet);
      if (!pengaturan.allowOfflineCashierSwitch) {
        return 'Tablet sedang offline. Ganti kasir saat offline dimatikan '
            'Pemilik untuk outlet ini — sambungkan ke internet.';
      }
      final daftar = await simpananOffline.daftar(idOutlet);
      if (daftar.isEmpty) {
        return 'Tablet sedang offline dan belum ada data staf tersimpan. '
            'Sambungkan ke internet sekali untuk menyimpannya.';
      }
      sesi.value = StaffSessionStart(
        challengeId: '',
        authorizerName: '',
        authorizerEmail: '',
        outletId: idOutlet,
        outlets: const [],
        staff: [
          for (final k in daftar)
            StaffCandidate(
              id: k.id,
              fullName: k.nama,
              role: k.role,
              hasPin: k.pin != null,
              kartuOffline: k.kartu,
            ),
        ],
      );
      outletId.value = idOutlet;
      outletPerangkat.value = await penyimpananPerangkat.bacaOutletName() ?? '';
      modeOffline.value = true;
      langkah.value = 1;
      return null;
    }

    Future<void> masukSebagai(KasirTersimpan k) async {
      await ref
          .read(authProvider.notifier)
          .masukOffline(
            staffId: k.id,
            nama: k.nama,
            role: k.role,
            outletId: outletId.value ?? '',
          );
      HapticFeedback.mediumImpact();
      onSelesai();
    }

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
        if (res.outletId.isNotEmpty) {
          unawaited(
            simpananOffline
                .simpanDaftar(res.outletId, res.staff)
                .catchError((_) {}),
          );
        }

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
          modeOffline.value = false;
          unawaited(
            simpananOffline
                .simpanDaftar(res.outletId, res.staff)
                .catchError((_) {}),
          );
          outletPerangkat.value =
              await penyimpananPerangkat.bacaOutletName() ?? '';
          langkah.value = 1; // langsung ke pemilihan staf
        } catch (e) {
          if (dibatalkan) return;
          // OFFLINE ≠ DITOLAK. Dulu galat koneksi ikut membuang pengesahan
          // perangkat — membuka layar ini tanpa internet memaksa Pemilik
          // datang mengetik password lagi. Kini: masuk mode offline.
          if (isOfflineError(e)) {
            final pesan = await masukModeOffline();
            if (pesan != null) error.value = pesan;
            return;
          }
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

    /// Masuk LANGSUNG, tanpa bukti kedua.
    ///
    /// Dipakai saat Pemilik baru saja mengetik email + passwordnya di perangkat
    /// ini: ia ada di sini, dan sudah membuktikan dirinya. Meminta kode ke
    /// emailnya sendiri sesudah itu berarti menyuruh orang yang sama
    /// membuktikan hal yang sama dua kali — untuk membuka sesi yang
    /// wewenangnya jauh di bawah apa yang sudah dipegang passwordnya.
    ///
    /// Sekarang jalur ini juga dipakai pada perangkat yang hanya MENGINGAT
    /// pengesahan lama: device_token-nya sendiri sudah merupakan bukti bahwa
    /// Pemilik pernah mengesahkan mesin ini, dan token itu bisa dicabut kapan
    /// saja dari dashboard.
    ///
    /// Kode kosong yang dikirim ke server BUKAN jalan pintas klien: server
    /// Pilih nama → minta PIN. TIDAK ada panggilan jaringan di sini.
    ///
    /// Sempat ada jalur "pilih nama langsung masuk", lalu dicabut bersamaan
    /// dengan PIN kini dibuat otomatis. Alasannya bukan berbalik pikiran:
    /// masuk-langsung dipilih ketika PIN pada praktiknya TAK BISA DIBAGIKAN —
    /// Pemilik harus menyetelnya satu per satu, dan cabang server yang
    /// membacanya bahkan tak pernah terjangkau. Begitu PIN lahir bersama
    /// karyawannya dan bisa disalin dari dashboard, hambatan itu hilang.
    ///
    /// Jalur kode email sudah DICABUT seluruhnya. Ia dulu jalan cadangan untuk
    /// staf yang belum punya PIN; sejak PIN dibuat otomatis saat karyawan
    /// ditambahkan, cadangan itu tak pernah dipakai — dan jalan masuk yang tak
    /// pernah dipakai tetap jalan masuk yang harus dijaga.
    void mintaPin(StaffCandidate staf) {
      error.value = null;
      stafTerpilih.value = staf;
      langkah.value = 2;
    }

    /// Scan kartu karyawan → sesi terbit tanpa memilih nama & tanpa PIN.
    ///
    /// Kartunya sendiri yang menyebutkan SIAPA, jadi staff_user_id dikirim
    /// kosong. Server yang menerjemahkan tokennya, dan penjaga outlet yang
    /// sama dengan jalur PIN tetap berlaku di sana.
    ///
    /// Isi QR-nya TIDAK pernah ditampilkan atau dicatat — ia rahasia yang
    /// setara kunci masuk, dan layar kasir menghadap pelanggan.
    Future<void> scanKartu() async {
      final hasil = await ref.read(pemindaiKodeProvider)(context);
      if (hasil == null || hasil.trim().isEmpty) return;

      if (modeOffline.value) {
        final k = await simpananOffline.masukKartu(outletId.value ?? '', hasil);
        if (k == null) {
          HapticFeedback.vibrate();
          error.value =
              'Kartu tidak dikenali di tablet ini. Kartu yang baru dibuat '
              'baru bisa dipakai offline setelah tablet sempat online.';
          return;
        }
        await masukSebagai(k);
        return;
      }

      loading.value = true;
      error.value = null;
      final msg = await ref
          .read(authProvider.notifier)
          .verifyStaffSession(
            challengeId: sesi.value!.challengeId,
            staffUserId: '',
            code: '',
            cardToken: hasil,
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

    Future<void> verifikasi() async {
      if (kodeCtrl.text.trim().isEmpty) {
        error.value = 'Masukkan PIN Anda.';
        return;
      }
      loading.value = true;
      error.value = null;
      final staf = stafTerpilih.value!;
      final pin = kodeCtrl.text;

      if (modeOffline.value) {
        final hasil = await simpananOffline.masukPin(
          outletId.value ?? '',
          staf.id,
          pin,
        );
        loading.value = false;
        switch (hasil) {
          case PinBenar(:final kasir):
            await masukSebagai(kasir);
          case PinSalah(:final sisa):
            HapticFeedback.vibrate();
            kodeCtrl.clear();
            error.value = 'PIN salah. Sisa $sisa percobaan sebelum dikunci.';
          case PinTerkunci(:final sampai):
            HapticFeedback.vibrate();
            kodeCtrl.clear();
            final j = sampai.toLocal();
            error.value =
                'Terlalu banyak PIN salah. Coba lagi pukul '
                '${j.hour.toString().padLeft(2, '0')}:'
                '${j.minute.toString().padLeft(2, '0')}, atau scan kartu.';
          case PinBelumTersimpan():
            error.value =
                'PIN ${staf.fullName} belum pernah dipakai online di tablet '
                'ini, jadi belum bisa diperiksa offline. Scan kartu karyawan, '
                'atau sambungkan ke internet.';
        }
        return;
      }

      final msg = await ref
          .read(authProvider.notifier)
          .verifyStaffSession(
            challengeId: sesi.value!.challengeId,
            staffUserId: staf.id,
            code: pin,
          );
      loading.value = false;
      if (msg != null) {
        HapticFeedback.vibrate();
        error.value = msg;
        return;
      }
      // PIN baru saja diterima server: simpan sidiknya supaya staf ini bisa
      // masuk saat tablet offline nanti.
      final idOutlet = outletId.value ?? sesi.value!.outletId;
      unawaited(
        simpananOffline.simpanPin(idOutlet, staf.id, pin).catchError((_) {}),
      );
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
            offline: modeOffline.value,
            loading: loading.value,
            // Pilih nama → langsung bertugas, di KEDUA jalur masuk.
            //
            // Bukti pengelola sudah lewat sebelum layar ini: entah Pemilik
            // baru mengetik passwordnya (start), atau perangkat memegang
            // device_token yang hanya terbit setelah ia pernah lolos password
            // di mesin ini (resume). Menahan kasir untuk bukti ketiga berarti
            // menunggu email di depan mesin yang sedang melayani orang.
            //
            // mintaKode tetap hidup sebagai cadangan: dipakai tombol "Kirim
            // ulang kode" di layar verifikasi, tempat masukLangsung mengantar
            // bila server menolak.
            onPilih: mintaPin,
            onScanKartu: scanKartu,
          )
        else
          ..._verifikasi(
            staf: stafTerpilih.value!,
            offline: modeOffline.value,
            kodeCtrl: kodeCtrl,
            loading: loading.value,
            onVerifikasi: verifikasi,
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
                    kodeCtrl.clear();
                    langkah.value = langkah.value - 1;
                  },
            child: const Text('Kembali'),
          ),
        ],
        if (perangkatDisahkan) ...[
          const Gap(20),
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
      style: _gayaJudul,
    ),
    const Gap(6),
    Text(
      perluPilihOutlet
          ? 'Akun Anda terhubung ke beberapa outlet. Pilih tempat perangkat ini dipakai.'
          : 'Masukkan email & password Anda untuk membuka sesi kasir di perangkat ini. '
                'Anda tidak akan masuk sebagai diri sendiri — Anda hanya menyetujui.',
      style: _gayaKeterangan,
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
        style: _gayaTombolUtama,
        child: Text(loading ? 'Memeriksa…' : 'Lanjut'),
      ),
    ],
  ];
}

List<Widget> _daftarStaf({
  required StaffSessionStart sesi,
  bool offline = false,
  required bool loading,
  required void Function(StaffCandidate) onPilih,
  required VoidCallback onScanKartu,
}) {
  return [
    const Text('Siapa yang bertugas?', style: _gayaJudul),
    const Gap(6),
    Text(
      offline
          ? 'Tablet sedang offline. Scan kartu, atau pilih nama lalu masukkan '
                'PIN. Sesi diverifikasi ulang begitu internet kembali.'
          : 'Disetujui oleh ${sesi.authorizerName}. Scan kartu, atau pilih '
                'nama lalu masukkan PIN.',
      style: _gayaKeterangan,
    ),
    const Gap(16),
    // Scan DI ATAS daftar, bukan di bawahnya.
    //
    // Ia jalan tercepat dan yang paling sering dipakai begitu kartu dibagikan;
    // menaruhnya sesudah daftar nama berarti kasir menggulir melewati jalan
    // lambat untuk sampai ke jalan cepat, tiap pergantian giliran.
    FilledButton.tonalIcon(
      key: const ValueKey('sesi-scan-kartu'),
      onPressed: loading ? null : onScanKartu,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
      label: const Text('Scan kartu karyawan'),
    ),
    const Gap(14),
    Row(
      children: [
        Expanded(child: Divider(color: kDivider)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'atau pilih nama',
            style: TextStyle(fontSize: 11, color: kTextLight),
          ),
        ),
        Expanded(child: Divider(color: kDivider)),
      ],
    ),
    const Gap(14),
    // Satu daftar bergaris, bukan tumpukan kartu: lebih tenang dibaca dan
    // lebih banyak nama muat tanpa menggulir.
    _DaftarStaf(staf: sesi.staff, loading: loading, onPilih: onPilih),
  ];
}

List<Widget> _verifikasi({
  required StaffCandidate staf,
  bool offline = false,
  required TextEditingController kodeCtrl,
  required bool loading,
  required VoidCallback onVerifikasi,
}) {
  return [
    Text(
      'Setujui sesi ${staf.fullName}',
      style: _gayaJudul,
    ),
    const Gap(6),
    // SATU cara, bukan dua.
    //
    // Jalur kode email dicabut atas keputusan pemilik produk. Alasannya sudah
    // tak berlaku: kode itu dulu jalan cadangan untuk staf yang belum punya
    // PIN, sedangkan PIN kini dibuat OTOMATIS oleh server saat karyawan
    // ditambahkan dan ditampilkan sekali ke Pemilik untuk disalin.
    //
    // Menyisakan dua jalan masuk yang salah satunya tak pernah dipakai bukan
    // kelonggaran — itu satu permukaan serangan tambahan yang tak seorang pun
    // memperhatikan, dan satu kalimat tambahan yang harus dibaca kasir yang
    // sedang buru-buru.
    //
    // PIN staf hanya berlaku di perangkat yang sudah disahkan Pemilik, dan
    // layar ini memang cuma tercapai dari perangkat seperti itu.
    Text(
      staf.hasPin
          ? 'Masukkan PIN ${staf.fullName} untuk mulai bertugas.'
          : offline
          ? 'PIN ${staf.fullName} belum pernah dipakai online di tablet ini, '
                'jadi belum bisa diperiksa saat offline. Scan kartu karyawan, '
                'atau sambungkan ke internet.'
          // Hanya mungkin untuk karyawan lama yang dibuat sebelum PIN
          // otomatis. Yang perlu diketahui orangnya adalah jalan keluarnya,
          // bukan bahwa ada yang salah.
          : '${staf.fullName} belum punya PIN. Minta Pemilik membuatkan dari '
                'dashboard, lalu coba lagi.',
      style: _gayaKeterangan,
    ),
    const Gap(18),
    // Papan angka, bukan papan ketik OS. Nilainya tetap disimpan di kodeCtrl
    // supaya jalur verifikasi di bawah tak berubah sama sekali;
    // ValueListenableBuilder yang membuat titik-titiknya ikut bergerak.
    ValueListenableBuilder<TextEditingValue>(
      valueListenable: kodeCtrl,
      builder: (_, nilai, _) => KeypadKode(
        nilai: nilai.text,
        aktif: !loading,
        onBerubah: (v) => kodeCtrl.text = v,
        // Hanya di digit ke-6 — di sana tak ada lagi digit yang mungkin
        // diketik. PIN 4-5 digit dikirim lewat tombol di bawah, yang karena
        // itu tidak boleh dihilangkan.
        onPenuh: loading ? null : onVerifikasi,
      ),
    ),
    const Gap(20),
    FilledButton(
      onPressed: loading ? null : onVerifikasi,
      style: _gayaTombolUtama,
      child: Text(loading ? 'Memverifikasi…' : 'Mulai sesi'),
    ),
  ];
}

const _gayaJudul = TextStyle(
  fontSize: 22,
  fontWeight: FontWeight.w700,
  letterSpacing: -0.3,
);

final _gayaTombolUtama = FilledButton.styleFrom(
  minimumSize: const Size.fromHeight(52),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
);

TextStyle get _gayaKeterangan =>
    TextStyle(fontSize: 14, color: kTextMid, height: 1.5);

class _DaftarStaf extends StatelessWidget {
  const _DaftarStaf({
    required this.staf,
    required this.loading,
    required this.onPilih,
  });

  final List<StaffCandidate> staf;
  final bool loading;
  final void Function(StaffCandidate) onPilih;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < staf.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: kDivider),
            _BarisStaf(
              staf: staf[i],
              onTap: loading ? null : () => onPilih(staf[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _BarisStaf extends StatelessWidget {
  const _BarisStaf({required this.staf, required this.onTap});
  final StaffCandidate staf;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final inisial =
        staf.fullName.isNotEmpty ? staf.fullName[0].toUpperCase() : '?';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  inisial,
                  style: const TextStyle(
                    color: kPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staf.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: kTextDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Gap(2),
                    Text(
                      staf.role,
                      style: TextStyle(color: kTextMid, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              HugeIcon(icon: AppIcons.chevronRight, color: kTextLight, size: 18),
            ],
          ),
        ),
      ),
    );
  }
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
            height: 3,
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
