import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service untuk menangani izin sistem (Bluetooth, Lokasi, Perangkat Sekitar, dll).
class SystemPermissionService {
  /// Cek apakah izin "Perangkat Sekitar" (Android 12+) atau Bluetooth sudah diberikan.
  Future<bool> get isNearbyDevicesGranted async {
    if (Platform.isAndroid) {
      // 1. Cek izin khusus Android 12+ (Nearby Devices)
      final scanStatus = await Permission.bluetoothScan.status;
      final connectStatus = await Permission.bluetoothConnect.status;

      // Jika salah satu granted, kita asumsikan ini Android 12+ dan cek keduanya
      if (scanStatus.isGranted || connectStatus.isGranted) {
        return scanStatus.isGranted && connectStatus.isGranted;
      }

      // 2. Jika tidak, cek izin Lokasi (untuk Android 11 ke bawah)
      final locationStatus = await Permission.location.status;
      return locationStatus.isGranted;
    } else if (Platform.isIOS) {
      return await Permission.bluetooth.isGranted;
    }
    return true;
  }

  /// Minta izin untuk akses perangkat sekitar.
  Future<bool> requestNearbyDevices() async {
    if (Platform.isAndroid) {
      // Pada Android 12+, kita prioritaskan Nearby Devices
      final nearbyStatuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();

      final nearbyOk =
          nearbyStatuses[Permission.bluetoothScan]?.isGranted == true &&
          nearbyStatuses[Permission.bluetoothConnect]?.isGranted == true;

      if (nearbyOk) return true;

      // Jika Nearby gagal atau tidak berlaku (Android < 12), minta Lokasi
      final locationStatus = await Permission.location.request();
      return locationStatus.isGranted;
    } else if (Platform.isIOS) {
      return await Permission.bluetooth.request().isGranted;
    }
    return true;
  }

  /// Membuka pengaturan aplikasi jika izin ditolak secara permanen.
  Future<void> openSettings() async {
    await openAppSettings();
  }
}

final systemPermissionServiceProvider = Provider<SystemPermissionService>((
  ref,
) {
  return SystemPermissionService();
});
