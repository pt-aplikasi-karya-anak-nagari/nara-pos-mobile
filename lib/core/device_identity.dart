import 'dart:io' show Platform;
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Identitas tetap perangkat ini, dikirim ke server sebagai header
/// `X-Device-ID` dan `X-Device-Label`.
///
/// # UNTUK APA
///
/// Server menegakkan "satu akun staf = satu perangkat": staf yang masih login
/// di tablet A ditolak saat mencoba login di tablet B. Tapi tablet A yang
/// sama, setelah aplikasinya ditutup paksa atau mati baterai, harus tetap bisa
/// masuk lagi. ID inilah yang membuat server bisa membedakan kedua kasus itu.
///
/// # KENAPA DISIMPAN DI DUA TEMPAT
///
/// ID yang hilang membuat tablet ini dianggap "perangkat lain", dan stafnya
/// tertolak sampai Pemilik melepas sesinya dari dashboard. Jadi ID disimpan di
/// SharedPreferences sekaligus di keystore: AuthStorage bisa mengosongkan
/// keystore saat datanya korup, dan di iOS keystore (Keychain) bertahan walau
/// aplikasi di-install ulang.
class DeviceIdentity {
  DeviceIdentity._(this.id, this.label);

  static const _key = 'device.id';

  /// Identitas yang sudah dimuat saat startup. Sebelum [load] selesai (atau
  /// bila gagal), ID kosong — server lalu memperlakukannya sebagai perangkat
  /// lain, yang aman: tak ada sesi siapa pun yang tergusur.
  static DeviceIdentity current = DeviceIdentity._('', '');

  final String id;
  final String label;

  static Future<DeviceIdentity> load(
    SharedPreferences prefs, {
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
  }) async {
    var id = prefs.getString(_key) ?? '';
    if (id.isEmpty) {
      try {
        id = await secureStorage.read(key: _key) ?? '';
      } catch (_) {
        id = '';
      }
    }
    if (id.isEmpty) id = _buatId();

    // Tulis ke kedua tempat — termasuk memulihkan salah satu yang hilang.
    await prefs.setString(_key, id);
    try {
      await secureStorage.write(key: _key, value: id);
    } catch (_) {
      // Keystore gagal: SharedPreferences saja sudah cukup untuk sesi ini.
    }

    current = DeviceIdentity._(id, _asciiHeader(await _labelPerangkat()));
    return current;
  }

  /// Nilai header HTTP harus ASCII; nama iPhone sering memuat tanda kutip
  /// melengkung atau emoji yang membuat permintaan gagal dikirim.
  static String _asciiHeader(String v) {
    final bersih = v.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    return bersih.length > 80 ? bersih.substring(0, 80) : bersih;
  }

  static String _buatId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Nama yang dikenali manusia, mis. "Samsung SM-T295", ditampilkan di pesan
  /// penolakan dan di dashboard Pemilik.
  static Future<String> _labelPerangkat() async {
    try {
      final info = DeviceInfoPlugin();
      if (kIsWeb) return 'Browser';
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final merek = a.manufacturer.isEmpty
            ? ''
            : a.manufacturer[0].toUpperCase() + a.manufacturer.substring(1);
        return '$merek ${a.model}'.trim();
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        return i.name.isNotEmpty ? i.name : i.model;
      }
    } catch (_) {
      // Label hanya pelengkap pesan; ID-lah yang menegakkan aturannya.
    }
    return '';
  }
}
