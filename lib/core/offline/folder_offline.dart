import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Operasi file di penyimpanan cadangan (lihat `FolderOfflineChannel.kt`):
/// tersembunyi, terenkripsi, dan tetap ada setelah uninstall. Dipisah sebagai
/// antarmuka supaya penggunanya bisa diuji tanpa perangkat Android.
///
/// Parameter `uri` hanya penanda penyimpanan (lihat
/// [ProductFolderStore.lokasiCadangan]) — lokasi sebenarnya ditentukan native
/// dan tidak pernah dikirim ke sisi Dart.
abstract class FolderBackend {
  /// Perangkat ini mendukung penyimpanan cadangan. Saat ini Android saja: di
  /// iOS seluruh file aplikasi ikut terhapus saat di-uninstall.
  bool get didukung;

  /// Izin penyimpanan cadangan sudah diberikan (diminta di gerbang izin).
  Future<bool> punyaAkses(String uri);

  Future<void> tulis(String uri, List<String> dir, String nama, String isi);

  /// Seluruh file di [dir]: nama file → isi. Kosong bila folder belum ada.
  /// File yang rusak atau diubah dari luar aplikasi tidak ikut.
  Future<Map<String, String>> bacaSemua(String uri, List<String> dir);

  Future<List<String>> daftarNama(String uri, List<String> dir);

  Future<bool> hapus(String uri, List<String> dir, String nama);
}

class MethodChannelFolderBackend implements FolderBackend {
  static const _channel = MethodChannel('nara/folder_offline');

  @override
  bool get didukung => !kIsWeb && Platform.isAndroid;

  @override
  Future<bool> punyaAkses(String uri) async {
    if (!didukung) return false;
    return await _channel.invokeMethod<bool>('hasAccess') ?? false;
  }

  @override
  Future<void> tulis(String uri, List<String> dir, String nama, String isi) =>
      _channel.invokeMethod<void>('writeFile', {
        'dir': dir,
        'name': nama,
        'content': isi,
      });

  @override
  Future<Map<String, String>> bacaSemua(String uri, List<String> dir) async {
    final hasil = await _channel.invokeMapMethod<String, String>('readAll', {
      'dir': dir,
    });
    return hasil ?? const {};
  }

  @override
  Future<List<String>> daftarNama(String uri, List<String> dir) async {
    final hasil = await _channel.invokeListMethod<String>('listNames', {
      'dir': dir,
    });
    return hasil ?? const [];
  }

  @override
  Future<bool> hapus(String uri, List<String> dir, String nama) async {
    return await _channel.invokeMethod<bool>('deleteFile', {
          'dir': dir,
          'name': nama,
        }) ??
        false;
  }
}
