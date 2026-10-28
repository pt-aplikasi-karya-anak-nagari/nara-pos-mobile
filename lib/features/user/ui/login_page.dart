import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/theme_mode_provider.dart';
import '../../../core/i18n.dart';
import '../../../shared/widgets/sheet_bawah.dart';
import 'staff_session_page.dart';
import 'widgets/forgot_password_sheet.dart';
import 'widgets/register_sheet.dart';

/// Lebar maksimum kolom login. Cukup lega untuk keypad PIN, cukup sempit
/// supaya di tablet mendatar mata tak perlu menyapu seluruh layar.
const double kLebarKolomLogin = 420;

/// Layar masuk aplikasi kasir — satu kolom di tengah, di semua ukuran layar.
///
/// # KENAPA SATU KOLOM
///
/// Tampilan lama membelah tablet mendatar jadi panel merek biru besar + kolom
/// login. Panel itu menghabiskan lebih dari separuh layar untuk tiga kata, dan
/// menjadikan ponsel & tablet dua tampilan yang berbeda. Sekarang identitas
/// merek tinggal di bilah atas (logo + nama), dan seluruh perhatian jatuh ke
/// satu hal yang memang harus dilakukan di layar ini: memilih siapa yang
/// bertugas.
///
/// Perangkat kasir TIDAK punya jalan masuk lain: satu-satunya cara membuka
/// aplikasi adalah lewat persetujuan Pemilik. Kalau kasir bisa login sendiri
/// dengan password, kontrol "siapa yang bertugas & siapa yang menyetujui" bisa
/// dilewati hanya dengan memilih form yang lain.
class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lebar = MediaQuery.sizeOf(context).width;
    final padatSamping = lebar >= 720 ? 32.0 : 20.0;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(padatSamping, 12, padatSamping, 0),
              child: const _BilahAtas(),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: padatSamping,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: kLebarKolomLogin,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Sesi tersimpan oleh alurnya; router yang mengamati
                        // auth state yang memindahkan layar.
                        StaffSessionFlow(onSelesai: () {}),
                        const Gap(28),
                        const _TautanBawah(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo + nama produk di kiri, tema & bahasa di kanan.
class _BilahAtas extends StatelessWidget {
  const _BilahAtas();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            'assets/images/logo.png',
            key: const ValueKey('login-logo-merek'),
            width: 34,
            height: 34,
            fit: BoxFit.contain,
          ),
        ),
        const Gap(10),
        Text(
          'NARA POS',
          style: TextStyle(
            color: kTextDark,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        const Spacer(),
        const _PilihBahasa(),
        const Gap(8),
        const _TombolTema(),
      ],
    );
  }
}

/// "Lupa password?" dan "Daftar" dalam satu baris tenang di bawah alur.
///
/// Keduanya tetap wajib ada. Pemilik memasukkan password di langkah pertama
/// alur sesi kasir — tanpa jalan memulihkannya, satu akun yang lupa berarti
/// perangkat kasir terkunci total. Pendaftaran Pemilik baru adalah jalur
/// akuisisi; menghapusnya menjadikan aplikasi jalan buntu bagi calon pengguna.
class _TautanBawah extends ConsumerWidget {
  const _TautanBawah();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gayaRedup = TextStyle(color: kTextMid, fontSize: 13);
    const gayaAksi = TextStyle(
      color: kPrimary,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );

    // Dua baris pendek, masing-masing Wrap (bukan Row): panjang teksnya ikut
    // bahasa DAN skala font sistem, dan Row akan meluber di ponsel sempit —
    // persis di layar yang jadi satu-satunya pintu masuk aplikasi.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Tautan(
          label: ref.t('login.forgot'),
          gaya: gayaAksi,
          onTap: () async {
            final email = await tampilkanSheetBawah<String>(
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
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(ref.t('login.no_account'), style: gayaRedup),
            _Tautan(
              label: ref.t('login.register'),
              gaya: gayaAksi,
              onTap: () => tampilkanSheetBawah(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const RegisterSheet(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Tautan extends StatelessWidget {
  const _Tautan({required this.label, required this.gaya, required this.onTap});
  final String label;
  final TextStyle gaya;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        // Area sentuh tetap cukup besar walau teksnya kecil.
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(label, style: gaya),
      ),
    );
  }
}

/// Tombol tema: ikon saja, labelnya di tooltip & Semantics.
class _TombolTema extends ConsumerWidget {
  const _TombolTema();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final (ikon, label) = switch (mode) {
      ThemeMode.system => (Icons.brightness_auto_outlined, 'Tema: Sistem'),
      ThemeMode.light => (Icons.light_mode_outlined, 'Tema: Terang'),
      ThemeMode.dark => (Icons.dark_mode_outlined, 'Tema: Gelap'),
    };
    final berikut = switch (mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: () => ref.read(themeModeProvider.notifier).setMode(berikut),
          customBorder: const CircleBorder(),
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: kDivider),
            ),
            child: Icon(ikon, size: 18, color: kTextMid),
          ),
        ),
      ),
    );
  }
}

/// Pilihan bahasa ringkas: dua label teks, yang aktif ditebalkan.
class _PilihBahasa extends ConsumerWidget {
  const _PilihBahasa();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    Widget item(AppLocale target, String label) {
      final aktif = locale == target;
      return Semantics(
        button: true,
        selected: aktif,
        label: target == AppLocale.id ? 'Bahasa Indonesia' : 'English',
        child: InkWell(
          onTap: aktif
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  ref.read(localeProvider.notifier).set(target);
                },
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: aktif ? kPrimary.withValues(alpha: 0.10) : null,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: aktif ? FontWeight.w700 : FontWeight.w500,
                color: aktif ? kPrimary : kTextMid,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: kDivider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [item(AppLocale.id, 'ID'), item(AppLocale.en, 'EN')],
      ),
    );
  }
}
