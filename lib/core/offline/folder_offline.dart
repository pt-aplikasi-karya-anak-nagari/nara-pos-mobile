import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Operasi file di folder yang dipilih pengguna (lihat
/// `FolderOfflineChannel.kt`). Dipisah sebagai antarmuka supaya
/// [ProductFolderStore] bisa diuji tanpa perangkat Android.
abstract class FolderBackend {
  /// Apakah perangkat ini mendukung folder pilihan. Saat ini Android saja:
  /// di iOS seluruh file aplikasi ikut terhapus saat di-uninstall.
  bool get didukung;

  /// Membuka pemilih folder sistem. Null bila pengguna membatalkan.
  Future<String?> pilihFolder();

  Future<bool> punyaAkses(String uri);

  Future<String?> namaFolder(String uri);

  Future<void> tulis(String uri, List<String> dir, String nama, String isi);

  /// Seluruh file `.json` di [dir]: nama file → isi. Kosong bila folder belum
  /// ada.
  Future<Map<String, String>> bacaSemua(String uri, List<String> dir);

  Future<List<String>> daftarNama(String uri, List<String> dir);

  Future<bool> hapus(String uri, List<String> dir, String nama);
}

class MethodChannelFolderBackend implements FolderBackend {
  static const _channel = MethodChannel('nara/folder_offline');

  @override
  bool get didukung => !kIsWeb && Platform.isAndroid;

  @override
  Future<String?> pilihFolder() async {
    if (!didukung) return null;
    return _channel.invokeMethod<String>('pickFolder');
  }

  @override
  Future<bool> punyaAkses(String uri) async {
    if (!didukung || uri.isEmpty) return false;
    return await _channel.invokeMethod<bool>('hasAccess', {'uri': uri}) ??
        false;
  }

  @override
  Future<String?> namaFolder(String uri) =>
      _channel.invokeMethod<String>('folderName', {'uri': uri});

  @override
  Future<void> tulis(String uri, List<String> dir, String nama, String isi) =>
      _channel.invokeMethod<void>('writeFile', {
        'uri': uri,
        'dir': dir,
        'name': nama,
        'content': isi,
      });

  @override
  Future<Map<String, String>> bacaSemua(String uri, List<String> dir) async {
    final hasil = await _channel.invokeMapMethod<String, String>('readAll', {
      'uri': uri,
      'dir': dir,
    });
    return hasil ?? const {};
  }

  @override
  Future<List<String>> daftarNama(String uri, List<String> dir) async {
    final hasil = await _channel.invokeListMethod<String>('listNames', {
      'uri': uri,
      'dir': dir,
    });
    return hasil ?? const [];
  }

  @override
  Future<bool> hapus(String uri, List<String> dir, String nama) async {
    return await _channel.invokeMethod<bool>('deleteFile', {
          'uri': uri,
          'dir': dir,
          'name': nama,
        }) ??
        false;
  }
}
