import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Brand colors ───────────────────────────────────────────────────────

const kPrimary = Color(0xFF1B4FD8);
const kAccent = Color(0xFFFF6B35);
const kSuccess = Color(0xFF22C55E);
const kDanger = Color(0xFFE53E3E);
const kWarning = Color(0xFFF59E0B);

// ─── Surface palette (tema terang saja) ────────────────────────────────
//
// Aplikasi kasir hanya punya tema terang — dark mode dihapus. Nama-nama
// ini tetap getter (bukan const) supaya ratusan pemakainya tak perlu
// diubah; nilainya kini selalu palet terang.

const _bgLight = Color(0xFFF4F6FB);
const _cardLight = Colors.white;
const _textDarkLight = Color(0xFF0F172A);
const _textMidLight = Color(0xFF64748B);
const _textLightLight = Color(0xFFCBD5E1);
const _dividerLight = Color(0xFFE8EDF5);

Color get kBg => _bgLight;
Color get kCard => _cardLight;
Color get kTextDark => _textDarkLight;
Color get kTextMid => _textMidLight;
Color get kTextLight => _textLightLight;
Color get kDivider => _dividerLight;

// ─── Theme builders ─────────────────────────────────────────────────────

ThemeData buildLightTheme() {
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

ThemeData _buildTheme(ColorScheme scheme) {
  // Font default app: Poppins via Google Fonts. Pakai `poppinsTextTheme`
  // supaya semua text style Material (titleLarge, bodyMedium, dll)
  // diturunkan dari Poppins — sekali set di sini, semua Text widget
  // pakai Poppins tanpa harus per-widget.
  final baseTextTheme = ThemeData(brightness: Brightness.light).textTheme;
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
      backgroundColor: const Color(0xFF1F2937),
      contentTextStyle: const TextStyle(color: Colors.white),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      hintStyle: const TextStyle(color: _textMidLight),
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
