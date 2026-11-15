import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../pantau.dart';

/// Integritas perangkat & aplikasi: anti-root/jailbreak, anti-debug,
/// anti-hooking (Frida/Xposed), anti-emulator, dan anti-repackaging.
///
/// Temuan dikumpulkan di native (Android: KeamananPerangkatChannel.kt) atau di
/// sini (iOS: jejak jailbreak di sistem file). Keputusan memblokir ada di
/// [keputusanIntegritas] — fungsi murni supaya kebijakannya bisa dites.
///
/// BATASAN: pemeriksaan di sisi klien bisa diakali penyerang yang cukup niat.
/// Gunanya menaikkan biaya serangan & menghentikan alat umum; penjaga yang
/// sebenarnya tetap otorisasi di server.
class KonfigurasiIntegritas {
  KonfigurasiIntegritas._();

  /// SHA-256 sertifikat tanda tangan APK rilis resmi (heks, boleh dengan titik
  /// dua). Kosong → pemeriksaan APK dirakit ulang dilewati. Diisi otomatis
  /// oleh scripts/build_prod.sh dari android/key.properties.
  static const sertifikatRilisSha256 = String.fromEnvironment(
    'NARA_SERTIFIKAT_SHA256',
  );

  /// Izinkan perangkat ber-root/jailbreak (mis. tablet POS khusus dari vendor
  /// yang sudah ter-root dari pabrik). Bawaan: TIDAK diizinkan.
  static const izinkanRoot = bool.fromEnvironment('NARA_IZINKAN_ROOT');
}

@immutable
class HasilIntegritas {
  final List<String> root;
  final List<String> hook;
  final List<String> emulator;
  final List<String> lemah;
  final bool debugger;

  /// APK rilis yang ditandai dapat di-debug → sudah dibongkar & dirakit ulang.
  final bool dapatDidebug;
  final String? sertifikatSha256;

  const HasilIntegritas({
    this.root = const [],
    this.hook = const [],
    this.emulator = const [],
    this.lemah = const [],
    this.debugger = false,
    this.dapatDidebug = false,
    this.sertifikatSha256,
  });

  static const aman = HasilIntegritas();

  factory HasilIntegritas.dariMap(Map<Object?, Object?> m) {
    List<String> daftar(String k) =>
        (m[k] as List?)?.map((e) => '$e').toList() ?? const [];
    return HasilIntegritas(
      root: daftar('root'),
      hook: daftar('hook'),
      emulator: daftar('emulator'),
      lemah: daftar('lemah'),
      debugger: m['debugger'] == true,
      dapatDidebug: m['dapat_didebug'] == true,
      sertifikatSha256: m['sertifikat_sha256'] as String?,
    );
  }
}

/// Alasan perangkat ditolak, untuk ditampilkan & dilaporkan.
enum AlasanTolak { root, hook, debugger, apkDiubah }

/// Kebijakan: apa yang memblokir aplikasi.
///
///  - Build debug/profile tidak pernah diblokir (pengembang butuh debugger &
///    emulator).
///  - Rilis: hooking, debugger, dan APK yang dirakit ulang SELALU diblokir —
///    tak ada alasan sah untuk itu di kasir.
///  - Root/jailbreak diblokir kecuali [izinkanRoot].
///  - Emulator & sinyal lemah (test-keys, ro.debuggable) hanya dicatat: banyak
///    tablet POS murah memakai build pabrik seperti itu.
List<AlasanTolak> keputusanIntegritas(
  HasilIntegritas h, {
  required bool rilis,
  bool izinkanRoot = false,
  String sertifikatResmi = '',
}) {
  if (!rilis) return const [];
  final alasan = <AlasanTolak>[];
  if (h.root.isNotEmpty && !izinkanRoot) alasan.add(AlasanTolak.root);
  if (h.hook.isNotEmpty) alasan.add(AlasanTolak.hook);
  if (h.debugger) alasan.add(AlasanTolak.debugger);
  final resmi = normalSha(sertifikatResmi);
  final nyata = normalSha(h.sertifikatSha256 ?? '');
  if (h.dapatDidebug || (resmi.isNotEmpty && nyata.isNotEmpty && resmi != nyata)) {
    alasan.add(AlasanTolak.apkDiubah);
  }
  return alasan;
}

/// "AB:cd:12" → "ABCD12".
String normalSha(String s) =>
    s.replaceAll(RegExp('[^0-9a-fA-F]'), '').toUpperCase();

/// Jejak jailbreak iOS yang bisa dilihat dari dalam sandbox.
const _jejakJailbreak = [
  '/Applications/Cydia.app',
  '/Applications/Sileo.app',
  '/Applications/Zebra.app',
  '/Library/MobileSubstrate/MobileSubstrate.dylib',
  '/usr/sbin/sshd',
  '/usr/bin/ssh',
  '/bin/bash',
  '/etc/apt',
  '/private/var/lib/apt/',
  '/var/jb',
  '/usr/lib/libjailbreak.dylib',
  '/usr/lib/frida/frida-agent.dylib',
];

const _kanal = MethodChannel('nara/keamanan_perangkat');

/// Kumpulkan temuan dari platform. Tak pernah melempar: galat → [HasilIntegritas.aman]
/// (fail-open), supaya kasir tak terkunci karena pemeriksaan yang rusak.
Future<HasilIntegritas> periksaIntegritas() async {
  try {
    if (Platform.isAndroid) {
      final m = await _kanal.invokeMethod<Map<Object?, Object?>>('periksa');
      return m == null ? HasilIntegritas.aman : HasilIntegritas.dariMap(m);
    }
    if (Platform.isIOS) {
      final root = <String>[];
      for (final p in _jejakJailbreak) {
        if (File(p).existsSync() || Directory(p).existsSync()) root.add(p);
      }
      // Aplikasi dalam sandbox tak boleh menulis di luar wadahnya.
      try {
        final f = File('/private/nara_uji_jailbreak.txt');
        f.writeAsStringSync('x');
        f.deleteSync();
        root.add('tulis:/private');
      } catch (_) {}
      return HasilIntegritas(root: root);
    }
  } catch (e) {
    debugPrint('[NARA] pemeriksaan integritas gagal: $e');
  }
  return HasilIntegritas.aman;
}

/// FLAG_SECURE (Android): layar tak bisa di-screenshot/direkam. Dipakai di
/// halaman yang menampilkan password & PIN. iOS: tidak didukung, diam saja.
Future<void> aturLayarAman(bool aktif) async {
  if (!Platform.isAndroid) return;
  try {
    await _kanal.invokeMethod('aturLayarAman', {'aktif': aktif});
  } catch (_) {}
}

/// Status integritas untuk seluruh aplikasi. Diperiksa saat mulai & setiap
/// aplikasi kembali ke depan (Frida/debugger bisa ditempel belakangan).
class IntegritasNotifier extends Notifier<List<AlasanTolak>>
    with WidgetsBindingObserver {
  bool _sudahLapor = false;

  @override
  List<AlasanTolak> build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));
    unawaited(periksa());
    return const [];
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(periksa());
  }

  Future<void> periksa() async {
    final hasil = await periksaIntegritas();
    final alasan = keputusanIntegritas(
      hasil,
      rilis: kReleaseMode,
      izinkanRoot: KonfigurasiIntegritas.izinkanRoot,
      sertifikatResmi: KonfigurasiIntegritas.sertifikatRilisSha256,
    );
    if (alasan.isNotEmpty && !_sudahLapor) {
      _sudahLapor = true;
      unawaited(
        Pantau.lapor(
          PerangkatTidakAman(alasan, hasil),
          StackTrace.current,
        ),
      );
    }
    state = alasan;
  }
}

final integritasProvider =
    NotifierProvider<IntegritasNotifier, List<AlasanTolak>>(
      IntegritasNotifier.new,
    );

/// Dilaporkan ke Sentry supaya tim tahu perangkat mana yang ditolak & kenapa.
class PerangkatTidakAman implements Exception {
  final List<AlasanTolak> alasan;
  final HasilIntegritas hasil;
  PerangkatTidakAman(this.alasan, this.hasil);

  @override
  String toString() =>
      'PerangkatTidakAman(${alasan.map((a) => a.name).join(",")}; '
      'root=${hasil.root}; hook=${hasil.hook}; emulator=${hasil.emulator}; '
      'lemah=${hasil.lemah})';
}
