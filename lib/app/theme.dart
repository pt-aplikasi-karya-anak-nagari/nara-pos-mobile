import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Brand colors (const, identik di light & dark) ──────────────────────

const kPrimary = Color(0xFF1B4FD8);
const kAccent = Color(0xFFFF6B35);
const kSuccess = Color(0xFF22C55E);
const kDanger = Color(0xFFE53E3E);
const kWarning = Color(0xFFF59E0B);
const kFav = Color(0xFFEF4444);

// ─── Surface palette — dinamis berdasarkan brightness ───────────────────
//
// Konstanta ini di-resolve dari `_brightness` notifier global. Saat user
// ganti tema (lewat profil), `NaraApp` set notifier dengan brightness
// efektif, lalu `MaterialApp` rebuild seluruh widget tree dengan
// `themeMode` baru — getter di bawah dievaluasi fresh dengan nilai dark
// / light yang sesuai.
//
// Trade-off: konstanta ini BUKAN `const` lagi. Callsite yang dipakai
// dalam `const` constructor harus drop `const` keyword (sudah dilakukan
// massal di codebase).

final _brightness = ValueNotifier<Brightness>(Brightness.light);

/// Set brightness aktif. Dipanggil dari root app (`NaraApp.build`) sebelum
/// `MaterialApp` di-render dengan theme baru.
void setAppBrightness(Brightness b) {
  if (_brightness.value != b) _brightness.value = b;
}

/// Brightness aktif saat ini.
Brightness get appBrightness => _brightness.value;

bool get _isDark => _brightness.value == Brightness.dark;

// Light palette
const _bgLight = Color(0xFFF4F6FB);
const _cardLight = Colors.white;
const _textDarkLight = Color(0xFF0F172A);
const _textMidLight = Color(0xFF64748B);
const _textLightLight = Color(0xFFCBD5E1);
const _dividerLight = Color(0xFFE8EDF5);

// Dark palette
const _bgDark = Color(0xFF0B1220);
const _cardDark = Color(0xFF1A2235);
const _textDarkDark = Color(0xFFE2E8F0);
const _textMidDark = Color(0xFF94A3B8);
const _textLightDark = Color(0xFF475569);
const _dividerDark = Color(0xFF273245);

Color get kBg => _isDark ? _bgDark : _bgLight;
Color get kCard => _isDark ? _cardDark : _cardLight;
Color get kTextDark => _isDark ? _textDarkDark : _textDarkLight;
Color get kTextMid => _isDark ? _textMidDark : _textMidLight;
Color get kTextLight => _isDark ? _textLightDark : _textLightLight;
Color get kDivider => _isDark ? _dividerDark : _dividerLight;

// ─── Theme builders ─────────────────────────────────────────────────────

ThemeData buildLightTheme() {
  // PENTING: jangan panggil setAppBrightness di sini. MaterialApp
  // mengevaluasi BAIK `theme` MAUPUN `darkTheme` setiap rebuild, jadi
  // siapa pun yang dipanggil terakhir akan menang dan brightness
  // notifier salah. Brightness aktif di-set di NaraApp.build berdasarkan
  // `themeMode` & `platformBrightness` — itu satu sumber kebenaran.
  final scheme =
      ColorScheme.fromSeed(
        seedColor: kPrimary,
        brightness: Brightness.light,
      ).copyWith(
        surface: _cardLight,
        surfaceContainer: _bgLight,
        surfaceContainerLowest: _cardLight,
        surfaceContainerLow: _bgLight,
        surfaceContainerHigh: _cardLight,
        surfaceContainerHighest: _cardLight,
        onSurface: _textDarkLight,
        outline: _dividerLight,
      );
  return _buildTheme(scheme);
}

ThemeData buildDarkTheme() {
  // Sama seperti buildLightTheme: jangan set brightness di sini.
  final scheme =
      ColorScheme.fromSeed(
        seedColor: kPrimary,
        brightness: Brightness.dark,
      ).copyWith(
        surface: _cardDark,
        surfaceContainer: _bgDark,
        surfaceContainerLowest: _bgDark,
        surfaceContainerLow: _bgDark,
        surfaceContainerHigh: _cardDark,
        surfaceContainerHighest: _cardDark,
        onSurface: _textDarkDark,
        outline: _dividerDark,
      );
  return _buildTheme(scheme);
}

ThemeData _buildTheme(ColorScheme scheme) {
  final isDark = scheme.brightness == Brightness.dark;
  // Font default app: Poppins via Google Fonts. Pakai `poppinsTextTheme`
  // supaya semua text style Material (titleLarge, bodyMedium, dll)
  // diturunkan dari Poppins — sekali set di sini, semua Text widget
  // pakai Poppins tanpa harus per-widget. Base text theme di-derive
  // dari brightness supaya warna teks default ikut light/dark.
  final baseTextTheme = isDark
      ? ThemeData(brightness: Brightness.dark).textTheme
      : ThemeData(brightness: Brightness.light).textTheme;
  final poppinsTextTheme = GoogleFonts.poppinsTextTheme(baseTextTheme);
  return ThemeData(
    useMaterial3: true,

    brightness: scheme.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surfaceContainer,
    canvasColor: scheme.surface,
    dividerColor: scheme.outline,
    // Font global. `fontFamily` di-set ke Poppins juga supaya Text widget
    // yang TIDAK pakai textTheme (mis. style hardcoded inline) tetap
    // dapat font Poppins, bukan default platform.
    fontFamily: GoogleFonts.poppins().fontFamily,
    textTheme: poppinsTextTheme,
    primaryTextTheme: poppinsTextTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.poppins(
        fontWeight: FontWeight.w700,
        fontSize: 18,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark
          ? const Color(0xFF1E293B)
          : const Color(0xFF1F2937),
      contentTextStyle: const TextStyle(color: Colors.white),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      hintStyle: TextStyle(color: isDark ? _textMidDark : _textMidLight),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.transparent),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPrimary, width: 1.5),
      ),
    ),
  );
}

ThemeData buildAppTheme() => buildLightTheme();
