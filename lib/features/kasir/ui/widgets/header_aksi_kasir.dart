import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../core/app_icons.dart';
import '../../../../core/outlet_scope.dart';
import '../../../drafts/providers.dart';

/// Baris identitas outlet + aksi cepat di puncak layar Kasir.
///
/// # KENAPA DIPISAH DARI kasir_page.dart
///
/// Sebelumnya ini satu `Row` sepanjang 260 baris di tengah build() yang besar,
/// dengan lebar tiap chip TETAP. Di layar 390 dp ia meluber 155 piksel — pita
/// kuning-hitam menutupi tombol Meja dan Draft, dan keduanya tak bisa ditekan
/// sama sekali.
///
/// Yang membuatnya bertahan lama: meluber hanya terjadi di layar sempit, dan
/// pengembangan sehari-hari berlangsung di tablet. Dipisah begini, ia bisa
/// dipasang sendirian di tes pada belasan lebar layar sekaligus — lihat
/// test/widgets/header_aksi_kasir_test.dart.
///
/// # TIGA MODE, DIPILIH DARI PENGUKURAN
///
/// Modenya tidak ditebak dari titik henti (breakpoint) lebar layar, melainkan
/// dihitung dari lebar teks yang sebenarnya lewat TextPainter. Nama outlet
/// pelanggan bisa "Kopi" atau "Warung Kopi Bang Jamal Cabang Simpang Empat" —
/// titik henti yang cocok untuk satu akan meluber untuk yang lain.
///
///   satuBaris   Semuanya muat: identitas outlet dan empat aksi berlabel.
///   duaBaris    Identitas outlet naik ke barisnya sendiri, aksi tetap berlabel.
///   ikon        Aksi jadi ikon saja. Labelnya pindah ke tooltip dan ke
///               Semantics, jadi ia tetap terbaca pembaca layar dan tetap bisa
///               dimunculkan dengan menekan lama.
class HeaderAksiKasir extends ConsumerWidget {
  final VoidCallback onScan;
  final VoidCallback onCustomOrder;
  final VoidCallback onMeja;
  final VoidCallback onDraft;

  const HeaderAksiKasir({
    super.key,
    required this.onScan,
    required this.onCustomOrder,
    required this.onMeja,
    required this.onDraft,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labelOutlet = ref.watch(activeOutletLabelProvider);
    final jumlahDraft = ref.watch(draftsCountProvider);

    final aksi = <_Aksi>[
      _Aksi(icon: AppIcons.scan, label: 'Scan', onTap: onScan),
      _Aksi(
        icon: AppIcons.add,
        label: 'Custom Order',
        // Label pendek dipakai saat ruangnya sempit tapi masih cukup untuk
        // teks. Memangkas "Custom Order" jadi "Custom" menghemat ~45 dp — kerap
        // itulah beda antara empat label terbaca dan empat ikon tanpa nama.
        labelPendek: 'Custom',
        onTap: onCustomOrder,
      ),
      _Aksi(
        icon: HugeIcons.strokeRoundedTable02,
        label: 'Meja',
        onTap: onMeja,
      ),
      _Aksi(
        icon: AppIcons.task,
        label: 'Draft',
        lencana: jumlahDraft,
        onTap: onDraft,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final lebar = constraints.maxWidth;
          final lebarOutlet = _lebarChipOutlet(labelOutlet);
          final lebarAksiPanjang = _lebarBarisAksi(aksi, pendek: false);
          final lebarAksiPendek = _lebarBarisAksi(aksi, pendek: true);

          // Sisa untuk identitas outlet bila semuanya sebaris. 24 = jarak
          // minimum antara identitas dan aksi.
          if (lebarOutlet + 24 + lebarAksiPanjang <= lebar) {
            return _SatuBaris(
              labelOutlet: labelOutlet,
              aksi: aksi,
              pendek: false,
            );
          }
          if (lebarOutlet + 24 + lebarAksiPendek <= lebar) {
            return _SatuBaris(
              labelOutlet: labelOutlet,
              aksi: aksi,
              pendek: true,
            );
          }
          if (lebarAksiPanjang <= lebar) {
            return _DuaBaris(
              labelOutlet: labelOutlet,
              aksi: aksi,
              pendek: false,
              ikonSaja: false,
            );
          }
          if (lebarAksiPendek <= lebar) {
            return _DuaBaris(
              labelOutlet: labelOutlet,
              aksi: aksi,
              pendek: true,
              ikonSaja: false,
            );
          }
          // Ikon saja. Kalau selebar apa pun ia masih tak muat, Flexible di
          // _BarisAksi yang menahannya — chip-nya menyusut, tak pernah meluber.
          return _DuaBaris(
            labelOutlet: labelOutlet,
            aksi: aksi,
            pendek: true,
            ikonSaja: true,
          );
        },
      ),
    );
  }
}

// ── Susunan ────────────────────────────────────────────────────────────────

class _SatuBaris extends StatelessWidget {
  final String labelOutlet;
  final List<_Aksi> aksi;
  final bool pendek;
  const _SatuBaris({
    required this.labelOutlet,
    required this.aksi,
    required this.pendek,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Flexible, bukan lebar tetap: nama outlet yang panjang memendek
        // dengan elipsis alih-alih mendorong aksinya keluar layar.
        Flexible(child: _ChipOutlet(label: labelOutlet)),
        const Gap(16),
        // Flexible, bukan lebar tetap: SingleChildScrollView di dalamnya butuh
        // lebar terbatas, dan sisa ruang setelah identitas outlet itulah
        // batasnya.
        Flexible(
          child: _BarisAksi(aksi: aksi, pendek: pendek, ikonSaja: false),
        ),
      ],
    );
  }
}

class _DuaBaris extends StatelessWidget {
  final String labelOutlet;
  final List<_Aksi> aksi;
  final bool pendek;
  final bool ikonSaja;
  const _DuaBaris({
    required this.labelOutlet,
    required this.aksi,
    required this.pendek,
    required this.ikonSaja,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Identitas outlet yang naik duluan, bukan aksinya: ia keterangan, dan
        // keterangan boleh menunggu. Aksi yang terdorong ke baris kedua justru
        // menjauh dari ibu jari.
        Align(
          alignment: Alignment.centerLeft,
          child: _ChipOutlet(label: labelOutlet),
        ),
        const Gap(8),
        SizedBox(
          width: double.infinity,
          child: _BarisAksi(aksi: aksi, pendek: pendek, ikonSaja: ikonSaja),
        ),
      ],
    );
  }
}

class _BarisAksi extends StatelessWidget {
  final List<_Aksi> aksi;
  final bool pendek;
  final bool ikonSaja;
  const _BarisAksi({
    required this.aksi,
    required this.pendek,
    required this.ikonSaja,
  });

  @override
  Widget build(BuildContext context) {
    final anak = <Widget>[];
    for (var i = 0; i < aksi.length; i++) {
      if (i > 0) anak.add(const Gap(8));
      // Ukuran alami, TANPA Flexible.
      //
      // Percobaan pertama membungkus tiap chip dengan Flexible sebagai
      // "penjaga terakhir". Itu justru yang merusaknya: di dalam Row
      // ber-mainAxisSize.min, Flexible menjatah lebar ke anak-anaknya, dan chip
      // Draft yang berlencana "99+" dapat jatah 8,8 piksel kurang dari yang ia
      // butuhkan — meluber di dalam chip-nya sendiri.
      anak.add(_ChipAksi(aksi: aksi[i], pendek: pendek, ikonSaja: ikonSaja));
    }

    // Gulir mendatar sebagai JAMINAN, bukan sebagai cara utama.
    //
    // Mode di atas sudah dipilih dari pengukuran, jadi dalam pemakaian normal
    // gulirnya tak pernah benar-benar bergulir. Ia ada untuk hal-hal yang tak
    // bisa diramalkan pengukuran itu: setelan ukuran huruf sistem yang sangat
    // besar, terjemahan yang lebih panjang, atau aksi kelima yang ditambahkan
    // nanti. Apa pun yang terjadi, tak ada lagi pita kuning-hitam yang menutupi
    // tombol.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      child: Row(mainAxisSize: MainAxisSize.min, children: anak),
    );
  }
}

// ── Chip ───────────────────────────────────────────────────────────────────

class _ChipOutlet extends StatelessWidget {
  final String label;
  const _ChipOutlet({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      constraints: const BoxConstraints(minHeight: _tinggiSentuh),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HugeIcon(
            icon: AppIcons.storefront,
            color: Colors.white,
            size: 13,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label.isNotEmpty ? label : 'Outlet',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipAksi extends StatelessWidget {
  final _Aksi aksi;
  final bool pendek;
  final bool ikonSaja;
  const _ChipAksi({
    required this.aksi,
    required this.pendek,
    required this.ikonSaja,
  });

  @override
  Widget build(BuildContext context) {
    final isi = Container(
      padding: EdgeInsets.symmetric(
        horizontal: ikonSaja ? 10 : 12,
        vertical: 7,
      ),
      constraints: const BoxConstraints(minHeight: _tinggiSentuh),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(icon: aksi.icon, color: Colors.white, size: 14),
          if (!ikonSaja) ...[
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                pendek ? aksi.teksPendek : aksi.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (aksi.lencana > 0) _Lencana(jumlah: aksi.lencana),
        ],
      ),
    );

    return Semantics(
      button: true,
      // Label HANYA disetel di mode ikon. Di mode berlabel, teksnya sudah
      // diumumkan pembaca layar — menambahkan label di sini membuat node-nya
      // punya dua nama sekaligus, dan pembaca layar membacakannya dua kali.
      label: ikonSaja ? aksi.label : null,
      child: Tooltip(
        message: aksi.label,
        // Di mode berlabel tooltipnya mubazir dan justru mengganggu saat
        // menekan lama.
        excludeFromSemantics: true,
        triggerMode: ikonSaja
            ? TooltipTriggerMode.longPress
            : TooltipTriggerMode.manual,
        child: GestureDetector(
          // Key stabil terlepas dari mode: teks yang tampil berubah
          // (label penuh / pendek / tak ada), jadi mencari tombol lewat
          // teksnya tak bisa diandalkan di seluruh lebar layar.
          key: ValueKey('aksi-${aksi.label}'),
          onTap: aksi.onTap,
          behavior: HitTestBehavior.opaque,
          child: isi,
        ),
      ),
    );
  }
}

class _Lencana extends StatelessWidget {
  final int jumlah;
  const _Lencana({required this.jumlah});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          jumlah > 99 ? '99+' : '$jumlah',
          style: const TextStyle(
            color: Color(0xFF1D4ED8),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Model & pengukuran ─────────────────────────────────────────────────────

/// Tinggi sentuh minimum. Chip aslinya ~28 dp — di bawah ambang yang nyaman
/// untuk ibu jari di layar sempit, tempat justru chip-nya paling berdesakan.
const double _tinggiSentuh = 36;

class _Aksi {
  final IconAsset icon;
  final String label;
  final String? labelPendek;
  final int lencana;
  final VoidCallback onTap;

  const _Aksi({
    required this.icon,
    required this.label,
    required this.onTap,
    this.labelPendek,
    this.lencana = 0,
  });

  String get teksPendek => labelPendek ?? label;
}

const TextStyle _gayaLabel = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
);

/// Lebar teks sesungguhnya, bukan perkiraan dari jumlah karakter.
///
/// Perkiraan berbasis jumlah karakter meleset paling jauh justru untuk nama
/// yang paling bermasalah — huruf lebar ("W", "M") dan nama outlet panjang.
double _lebarTeks(String teks, TextStyle gaya) {
  final tp = TextPainter(
    text: TextSpan(text: teks, style: gaya),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return tp.width;
}

double _lebarChipOutlet(String label) {
  const paddingDanIkon = 12 * 2 + 13 + 6;
  return paddingDanIkon +
      _lebarTeks(label.isNotEmpty ? label : 'Outlet', _gayaLabel);
}

double _lebarChipAksi(_Aksi a, {required bool pendek}) {
  const paddingDanIkon = 12 * 2 + 14 + 4;
  final lencana = a.lencana > 0
      ? 6 + 12 + _lebarTeks(a.lencana > 99 ? '99+' : '${a.lencana}', _gayaLabel)
      : 0.0;
  return paddingDanIkon +
      _lebarTeks(pendek ? a.teksPendek : a.label, _gayaLabel) +
      lencana;
}

double _lebarBarisAksi(List<_Aksi> aksi, {required bool pendek}) {
  var total = 8.0 * (aksi.length - 1);
  for (final a in aksi) {
    total += _lebarChipAksi(a, pendek: pendek);
  }
  return total;
}
