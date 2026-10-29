import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../auth_storage.dart';
import '../device_identity.dart';
import '../shared_prefs.dart';
import 'offline_sync_service.dart';

/// Sinkron antrian offline di LATAR BELAKANG (Android WorkManager).
///
/// # MASALAHNYA
///
/// Antrian hanya terkirim selagi aplikasi terbuka. Tablet yang ditutup
/// semalaman menahan transaksi — dan laporan perangkat — sampai dibuka lagi,
/// padahal internet mungkin sudah kembali sejak lama. Pemilik melihat omzet
/// yang belum lengkap, dan data hanya aman di satu tablet lebih lama dari
/// perlu.
///
/// # CARANYA
///
/// Tugas berkala (~15 menit, batas minimum Android) yang hanya jalan saat ada
/// jaringan. Ia membangun ProviderContainer sendiri lalu memanggil penyinkron
/// yang sama dengan aplikasi — jadi aturan urutan, idempotensi, dan
/// dead-letter-nya persis sama.
///
/// Dilewati bila:
///  - aplikasi sedang terbuka — ia menyinkron sendiri (lihat [tandaiLatarDepan]);
///  - belum ada yang masuk, atau sesi kasir dibuka offline dan belum
///    diverifikasi ulang (tak ada token yang sah untuk mengirim).
///
/// Dua penyinkron yang tetap sempat berjalan bersamaan aman: setiap kiriman
/// membawa client_ref, dan server mengembalikan catatan yang sama.

const tugasSinkronLatar = 'nara.sinkron-offline';

/// Kunci penanda aplikasi sedang di layar.
const kunciLatarDepan = 'app.latar_depan_pada';

/// Penanda layar dianggap basi setelah ini (aplikasi dimatikan paksa tanpa
/// sempat mencabut penandanya).
const basiLatarDepan = Duration(hours: 6);

/// Catat aplikasi masuk/keluar layar.
Future<void> tandaiLatarDepan(SharedPreferences prefs, bool tampil) async {
  if (tampil) {
    await prefs.setInt(kunciLatarDepan, DateTime.now().millisecondsSinceEpoch);
  } else {
    await prefs.remove(kunciLatarDepan);
  }
}

/// Apakah tugas latar perlu jalan sekarang. MURNI.
bool perluSinkronLatar({
  required int? latarDepanPadaMs,
  required bool adaToken,
  required bool sesiOffline,
  required DateTime kini,
}) {
  if (!adaToken || sesiOffline) return false;
  if (latarDepanPadaMs == null) return true;
  final sejak = kini.difference(
    DateTime.fromMillisecondsSinceEpoch(latarDepanPadaMs),
  );
  return sejak > basiLatarDepan;
}

@pragma('vm:entry-point')
void panggilTugasLatar() {
  Workmanager().executeTask((tugas, _) async {
    if (tugas != tugasSinkronLatar) return true;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // isolate ini punya salinan sendiri
      final auth = AuthStorage(prefs);
      await auth.init();
      if (!perluSinkronLatar(
        latarDepanPadaMs: prefs.getInt(kunciLatarDepan),
        adaToken: (auth.accessToken ?? '').isNotEmpty,
        sesiOffline: auth.sesiOffline,
        kini: DateTime.now(),
      )) {
        return true;
      }
      try {
        await DeviceIdentity.load(prefs);
      } catch (_) {}
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authStorageProvider.overrideWithValue(auth),
        ],
      );
      try {
        await c.read(offlineSyncServiceProvider).sync();
      } finally {
        c.dispose();
      }
    } catch (e) {
      debugPrint('[NARA] sinkron latar gagal: $e');
    }
    // Selalu "berhasil": kegagalan dicatat di antrian (attempts/dead-letter),
    // dan jadwal berkala tetap jalan. Gagal di sini hanya memicu backoff.
    return true;
  });
}

/// Daftarkan tugas berkala. Android saja — iOS butuh pengaturan BGTask di
/// AppDelegate dan aplikasi kasir ini berjalan di tablet Android.
Future<void> daftarkanSinkronLatar() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(panggilTugasLatar);
  await Workmanager().registerPeriodicTask(
    tugasSinkronLatar,
    tugasSinkronLatar,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
