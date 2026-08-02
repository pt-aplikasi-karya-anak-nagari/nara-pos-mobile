import 'package:flutter/material.dart';

/// Bottom sheet yang tingginya mengikuti isinya, dan tak pernah tertimpa
/// status bar maupun gesture bar.
///
/// # KENAPA TIDAK MEMANGGIL showModalBottomSheet LANGSUNG
///
/// Ada 38 pemanggilan sheet di aplikasi ini. Setiap satunya harus mengingat
/// tiga hal yang tak satu pun kelihatan salah bila dilupakan — sampai dilihat
/// di perangkat asli:
///
///   isScrollControlled   tanpa ini tinggi sheet dipatok 9/16 layar, jadi isi
///                        yang lebih tinggi terpotong diam-diam.
///   useSafeArea          tanpa ini Flutter justru MEMBUANG padding atas
///                        (MediaQuery.removePadding(removeTop: true)), jadi
///                        sheet yang tinggi menyelinap ke bawah status bar.
///   inset bawah          keyboard menutupi tombol simpan; gesture bar Android
///                        menimpa baris terakhir.
///
/// Sebelum berkas ini ada, ketiganya diurus sendiri-sendiri: 38 pemanggilan
/// memakai isScrollControlled, TAK SATU PUN memakai useSafeArea, dan hanya
/// sebagian yang menambah inset bawah. Menaruhnya di satu tempat membuat sheet
/// ke-39 benar tanpa penulisnya perlu tahu apa pun tentang ini.
///
/// # TINGGI MENGIKUTI ISI
///
/// Sheet-nya sendiri tidak mematok tinggi apa pun — yang menentukan adalah
/// widget isinya. Sebuah `Column(mainAxisSize: MainAxisSize.min)` akan pas
/// dengan isinya, dan itulah yang dipakai hampir semua sheet di sini.
///
/// Yang PERLU diwaspadai penulis sheet baru: widget scrollable (ListView,
/// GridView) TIDAK mengecil mengikuti isinya. Ia selalu memenuhi tinggi
/// maksimum yang ditawarkan induknya, walau isinya cuma dua baris — itulah
/// yang membuat sheet varian tampil setinggi layar dengan rongga kosong
/// menganga di tengah. Obatnya `shrinkWrap: true`, dibungkus `Flexible` supaya
/// daftar yang panjang tetap bisa digulir alih-alih meluber.
Future<T?> tampilkanSheetBawah<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool isDismissible = true,
  bool enableDrag = true,
  // Diterima demi kompatibilitas dengan pemanggilan lama; nilainya diabaikan
  // karena sheet di sini SELALU scroll-controlled. Dibiarkan ada supaya
  // migrasi dari showModalBottomSheet cukup mengganti namanya saja, tanpa
  // menyunting daftar argumen 38 pemanggilan satu per satu.
  bool isScrollControlled = true,
  BoxConstraints? constraints,
  RouteSettings? routeSettings,
  double? elevation,
  Clip? clipBehavior,
  bool? showDragHandle,
  Color? barrierColor,
  bool useRootNavigator = false,
  AnimationController? transitionAnimationController,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: backgroundColor,
    shape: shape,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    constraints: constraints,
    routeSettings: routeSettings,
    elevation: elevation,
    clipBehavior: clipBehavior,
    showDragHandle: showDragHandle,
    barrierColor: barrierColor,
    useRootNavigator: useRootNavigator,
    transitionAnimationController: transitionAnimationController,
    builder: (konteks) => WadahSheetBawah(child: builder(konteks)),
  );
}

/// Pembungkus isi sheet: memberi ruang untuk keyboard dan gesture bar, lalu
/// MENCABUT keduanya dari MediaQuery yang diteruskan ke bawah.
///
/// # KENAPA MENCABUT, BUKAN SEKADAR MENAMBAH
///
/// Sebelas widget isi sheet sudah lebih dulu menambah inset-nya sendiri —
/// `MediaQuery.of(context).padding.bottom`, `viewInsets.bottom`, atau
/// `SafeArea` di dalam badannya. Kalau pembungkus ini hanya menambah, keduanya
/// berlaku sekaligus: ruang kosong dua kali lipat di bawah tombol, dan tak ada
/// yang tampak salah di kode mana pun kalau dibaca sendiri-sendiri.
///
/// Karena itu setelah ruangnya diberi, nilainya dinolkan untuk keturunan.
/// SafeArea memang sudah melakukannya untuk padding (ia membungkus anaknya
/// dengan MediaQuery.removePadding), jadi di sini tinggal viewInsets yang
/// perlu diurus. Hasilnya: padding milik widget lama tetap dihitung, hanya
/// nilainya nol — jadi tak ada yang perlu disunting, dan widget itu tetap
/// benar bila suatu saat dipakai di luar sheet.
class WadahSheetBawah extends StatelessWidget {
  final Widget child;
  const WadahSheetBawah({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Ruang untuk keyboard. Tanpa ini, field paling bawah dan tombol
      // simpannya tertutup papan ketik yang baru saja dipakai mengisinya.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        // top: false — bagian atas sudah diurus useSafeArea di route sheet-nya.
        // Yang tersisa gesture bar / home indicator di bawah.
        child: SafeArea(top: false, child: child),
      ),
    );
  }
}
