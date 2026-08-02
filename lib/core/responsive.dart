import 'package:flutter/widgets.dart';

/// Breakpoints berdasarkan lebar layar (dp).
/// - compact  : < 600  → phone portrait
/// - medium   : 600–839 → phone landscape / tablet kecil portrait
/// - expanded : 840–1199 → tablet
/// - large    : ≥ 1200 → tablet besar / desktop
enum ScreenSize { compact, medium, expanded, large }

class Breakpoints {
  static const double medium = 600;
  static const double expanded = 840;
  static const double large = 1200;
}

extension ResponsiveContext on BuildContext {
  Size get _size => MediaQuery.sizeOf(this);

  ScreenSize get screen {
    final w = _size.width;
    if (w >= Breakpoints.large) return ScreenSize.large;
    if (w >= Breakpoints.expanded) return ScreenSize.expanded;
    if (w >= Breakpoints.medium) return ScreenSize.medium;
    return ScreenSize.compact;
  }

  bool get isPhone => screen == ScreenSize.compact;
  bool get isTablet =>
      screen == ScreenSize.expanded || screen == ScreenSize.large;
  bool get isWide =>
      screen == ScreenSize.expanded || screen == ScreenSize.large;

  /// Pilih nilai berdasarkan ukuran layar dengan fallback.
  T responsive<T>({
    required T compact,
    T? medium,
    T? expanded,
    T? large,
  }) {
    switch (screen) {
      case ScreenSize.large:
        return large ?? expanded ?? medium ?? compact;
      case ScreenSize.expanded:
        return expanded ?? medium ?? compact;
      case ScreenSize.medium:
        return medium ?? compact;
      case ScreenSize.compact:
        return compact;
    }
  }

  /// Navigasi utama ditaruh sebagai rail di tepi KANAN, bukan bilah bawah.
  ///
  /// # KENAPA SATU TEMPAT
  ///
  /// Dua tempat memutuskannya: MainShell (menggambar rail atau bilah) dan
  /// KasirPage (menyembunyikan baris aksi di header karena aksinya sudah pindah
  /// ke rail). Kalau keduanya menghitung sendiri-sendiri, satu titik henti yang
  /// diubah akan membuat aksinya tampil DUA KALI, atau — lebih buruk — hilang
  /// sama sekali dari kedua tempat.
  ///
  /// # KENAPA 600 dp
  ///
  /// Di ponsel 360 dp, rail selebar 88 dp memakan seperempat lebar layar, dan
  /// lebar itulah yang menentukan berapa kartu produk muat sebaris. 600 dp juga
  /// titik saat ponsel dimiringkan jadi melintang — di sana tingginya tinggal
  /// ~360 dp dan rail justru menguntungkan.
  bool get pakaiRailNavigasi => screen != ScreenSize.compact;

  /// Hitung jumlah kolom grid produk berdasarkan lebar layar.
  int get productGridColumns => responsive<int>(
        compact: 2,
        medium: 3,
        expanded: 4,
        large: 5,
      );

  /// Padding horizontal konten utama, lebih lega di tablet.
  double get contentHorizontalPadding => responsive<double>(
        compact: 16,
        medium: 20,
        expanded: 24,
        large: 32,
      );

  /// Maksimum lebar konten agar tidak terlalu "melebar" di tablet.
  double get maxContentWidth => responsive<double>(
        compact: double.infinity,
        medium: double.infinity,
        expanded: 1100,
        large: 1280,
      );
}

/// Helper untuk membungkus konten dengan batas lebar maksimum di tablet,
/// sehingga teks & tile tetap nyaman dibaca.
class ContentConstrained extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  const ContentConstrained({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveMax = maxWidth ?? context.maxContentWidth;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMax),
        child: padding == null ? child : Padding(padding: padding!, child: child),
      ),
    );
  }
}
