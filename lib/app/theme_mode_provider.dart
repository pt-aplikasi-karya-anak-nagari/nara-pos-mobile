import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/shared_prefs.dart';

/// Notifier untuk mode tema aplikasi (light/dark/sistem).
///
/// State di-persist ke SharedPreferences supaya pilihan user tidak hilang
/// saat app di-restart. Saat berubah, root `MaterialApp` akan rebuild &
/// memicu `setAppBrightness` di `theme.dart` — semua widget yang pakai
/// getter palette dinamis (`kBg`, `kCard`, dll) otomatis ikut adapt.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _kKey = 'app.theme_mode';

  @override
  ThemeMode build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final stored = prefs.getString(_kKey);
    return _parse(stored);
  }

  /// Ubah mode tema. Persist ke SharedPreferences supaya bertahan.
  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_kKey, _serialize(mode));
  }

  static ThemeMode _parse(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static String _serialize(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
