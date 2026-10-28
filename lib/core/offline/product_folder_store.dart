import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show PlatformException;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/products/domain/product.dart';
import '../shared_prefs.dart';
import 'folder_offline.dart';

/// Salinan produk di folder pilihan pengguna: SATU file per produk, dikelompokkan
/// per outlet.
///
/// ```
/// <folder pilihan>/
///   outlet-<outletId>/
///     produk/
///       <productId>.json
/// ```
///
/// # UNTUK APA
///
/// Cache SQLite ([ProductCache]) ikut terhapus saat aplikasi di-uninstall.
/// Salinan di folder ini tidak: setelah install ulang, pengguna memilih folder
/// yang sama dan katalog outlet yang sedang login langsung bisa dipakai lagi,
/// walau tablet belum tersambung internet.
///
/// # KENAPA PER PRODUK
///
/// Produk ditulis satu per satu begitu diterima dari API, jadi sinkron yang
/// terputus di tengah tetap meninggalkan produk yang sudah sempat diterima.
/// Mengubah satu produk juga hanya menulis ulang satu file kecil.
class ProductFolderStore {
  ProductFolderStore(this._prefs, this._backend);

  static const kunciUri = 'offline.folder_uri';
  static const _versi = 1;

  final SharedPreferences _prefs;
  final FolderBackend _backend;

  /// `outlet|produk` → JSON produk yang terakhir ditulis/dibaca. Sinkron
  /// berulang jadi tidak menulis ulang file yang isinya tidak berubah.
  final Map<String, String> _terakhir = {};

  /// Semua operasi berjalan berurutan: produk 1 selesai ditulis, baru produk
  /// berikutnya.
  Future<void> _antrian = Future.value();

  /// Pesan galat terakhir saat menulis/membaca folder, untuk halaman
  /// pengaturan. Null bila operasi terakhir berhasil.
  String? galatTerakhir;

  /// outletId → ID produk yang filenya ada di folder. Diisi dari daftar file
  /// saat pertama diminta, lalu diperbarui setiap tulis/pangkas.
  final Map<String, Set<String>> _idDiketahui = {};

  final _perubahan = StreamController<String>.broadcast();

  /// Memancarkan outletId setiap isi folder outlet itu berubah, atau `*` bila
  /// folder diganti/dilepas.
  Stream<String> get perubahan => _perubahan.stream;

  bool get didukung => _backend.didukung;

  String? get folderUri {
    final uri = _prefs.getString(kunciUri);
    return uri == null || uri.isEmpty ? null : uri;
  }

  /// Folder sudah dipilih DAN izinnya masih ada.
  Future<bool> aktif() async => await _uriAktif() != null;

  Future<String?> namaFolder() async {
    final uri = await _uriAktif();
    if (uri == null) return null;
    try {
      return await _backend.namaFolder(uri);
    } catch (_) {
      return null;
    }
  }

  /// Membuka pemilih folder. Mengembalikan true bila folder baru tersimpan.
  Future<bool> pilihFolder() async {
    final uri = await _backend.pilihFolder();
    if (uri == null || uri.isEmpty) return false;
    await _prefs.setString(kunciUri, uri);
    // Folder baru: semua produk perlu ditulis lagi ke sana.
    _terakhir.clear();
    _idDiketahui.clear();
    galatTerakhir = null;
    _perubahan.add('*');
    return true;
  }

  Future<void> lepasFolder() async {
    await _prefs.remove(kunciUri);
    _terakhir.clear();
    _idDiketahui.clear();
    galatTerakhir = null;
    _perubahan.add('*');
  }

  /// Nama folder milik satu outlet di folder pilihan — dipakai juga oleh
  /// cadangan transaksi offline, supaya semua data satu outlet berkumpul.
  static String folderOutlet(String outletId) => 'outlet-${_aman(outletId)}';

  /// ID aman untuk dipakai sebagai nama file/folder.
  static String namaAman(String v) => _aman(v);

  /// Backend file yang dipakai — dibagi dengan cadangan transaksi offline.
  FolderBackend get backend => _backend;

  /// URI folder bila sudah dipilih DAN izinnya masih ada; null bila tidak.
  Future<String?> uriAktif() => _uriAktif();

  static List<String> dirProduk(String outletId) => [
    'outlet-${_aman(outletId)}',
    'produk',
  ];

  static String namaFile(String productId) => '${_aman(productId)}.json';

  /// Tulis [products] ke folder, satu file per produk, berurutan. Produk yang
  /// isinya sama dengan tulisan terakhir dilewati. Mengembalikan jumlah file
  /// yang ditulis; 0 bila folder belum dipilih.
  ///
  /// Tidak pernah melempar galat: kegagalan menyimpan salinan tidak boleh
  /// menggagalkan halaman kasir. Galatnya dicatat di [galatTerakhir].
  Future<int> simpan(String outletId, Iterable<Product> products) {
    final daftar = products.toList();
    return _jalankan(() async {
      final uri = await _uriAktif();
      if (uri == null || outletId.isEmpty) return 0;
      final dir = dirProduk(outletId);
      final diketahui = _idDiketahui[outletId];
      var ditulis = 0;
      try {
        for (final p in daftar) {
          final id = p.remoteId;
          if (id == null || id.isEmpty) continue;
          final json = p.toJson();
          final produk = jsonEncode(json);
          final kunci = '$outletId|$id';
          if (_terakhir[kunci] == produk) continue;

          final isi = jsonEncode({
            'versi': _versi,
            'outlet_id': outletId,
            'disimpan_pada': DateTime.now().toIso8601String(),
            'produk': json,
          });
          await _backend.tulis(uri, dir, namaFile(id), isi);
          _terakhir[kunci] = produk;
          diketahui?.add(id);
          ditulis++;
        }
        galatTerakhir = null;
      } catch (e) {
        galatTerakhir = _pesan(e);
      }
      if (ditulis > 0) _perubahan.add(outletId);
      return ditulis;
    });
  }

  /// Seluruh produk outlet [outletId] yang tersimpan di folder. File yang rusak
  /// atau milik outlet lain dilewati.
  Future<List<Product>> muat(String outletId) {
    return _jalankan(() async {
      final uri = await _uriAktif();
      if (uri == null || outletId.isEmpty) return const <Product>[];
      final Map<String, String> files;
      try {
        files = await _backend.bacaSemua(uri, dirProduk(outletId));
        galatTerakhir = null;
      } catch (e) {
        galatTerakhir = _pesan(e);
        return const <Product>[];
      }

      final hasil = <Product>[];
      for (final isi in files.values) {
        try {
          final data = jsonDecode(isi);
          if (data is! Map<String, dynamic>) continue;
          if (data['outlet_id'] != outletId) continue;
          final json = data['produk'];
          if (json is! Map<String, dynamic>) continue;
          final p = Product.fromJson(json);
          final id = p.remoteId;
          if (id == null || id.isEmpty) continue;
          _terakhir['$outletId|$id'] = jsonEncode(p.toJson());
          hasil.add(p);
        } catch (_) {
          // Satu file rusak tidak boleh menyembunyikan produk lainnya.
        }
      }
      hasil.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return hasil;
    });
  }

  /// Jumlah file produk outlet [outletId] di folder.
  Future<int> jumlah(String outletId) {
    return _jalankan(() async {
      final uri = await _uriAktif();
      if (uri == null) return 0;
      try {
        final nama = await _backend.daftarNama(uri, dirProduk(outletId));
        return nama.where((n) => n.endsWith('.json')).length;
      } catch (e) {
        galatTerakhir = _pesan(e);
        return 0;
      }
    });
  }

  /// Hapus file produk yang tidak ada di [idTetap] — produk yang sudah dihapus
  /// atau dinonaktifkan di server. Hanya dipanggil setelah sinkron PENUH.
  Future<int> pangkas(String outletId, Set<String> idTetap) {
    return _jalankan(() async {
      final uri = await _uriAktif();
      if (uri == null) return 0;
      final dir = dirProduk(outletId);
      final tetap = idTetap.map(namaFile).toSet();
      var dihapus = 0;
      try {
        final nama = await _backend.daftarNama(uri, dir);
        for (final n in nama) {
          if (!n.endsWith('.json') || tetap.contains(n)) continue;
          if (await _backend.hapus(uri, dir, n)) dihapus++;
        }
        _terakhir.removeWhere((kunci, _) {
          if (!kunci.startsWith('$outletId|')) return false;
          return !idTetap.contains(kunci.substring(outletId.length + 1));
        });
        _idDiketahui[outletId]?.removeWhere((id) => !idTetap.contains(id));
      } catch (e) {
        galatTerakhir = _pesan(e);
      }
      if (dihapus > 0) _perubahan.add(outletId);
      return dihapus;
    });
  }

  /// ID produk outlet [outletId] yang sudah punya file di folder. Kosong bila
  /// folder belum dipilih.
  Future<Set<String>> idTersimpan(String outletId) {
    return _jalankan(() async {
      final uri = await _uriAktif();
      if (uri == null || outletId.isEmpty) return <String>{};
      final ada = _idDiketahui[outletId];
      if (ada != null) return Set.of(ada);
      try {
        final nama = await _backend.daftarNama(uri, dirProduk(outletId));
        final ids = {
          for (final n in nama)
            if (n.endsWith('.json')) n.substring(0, n.length - 5),
        };
        _idDiketahui[outletId] = ids;
        return Set.of(ids);
      } catch (e) {
        galatTerakhir = _pesan(e);
        return <String>{};
      }
    });
  }

  Future<String?> _uriAktif() async {
    final uri = folderUri;
    if (uri == null || !_backend.didukung) return null;
    try {
      return await _backend.punyaAkses(uri) ? uri : null;
    } catch (_) {
      return null;
    }
  }

  Future<T> _jalankan<T>(Future<T> Function() kerja) {
    final hasil = _antrian.then((_) => kerja());
    _antrian = hasil.then<void>((_) {}, onError: (_) {});
    return hasil;
  }

  /// ID dipakai sebagai nama file/folder; buang karakter yang bisa membentuk
  /// path lain.
  static String _aman(String v) => v.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static String _pesan(Object e) {
    if (e is PlatformException) return e.message ?? e.code;
    return e.toString();
  }
}

final folderBackendProvider = Provider<FolderBackend>(
  (ref) => MethodChannelFolderBackend(),
);

final productFolderStoreProvider = Provider<ProductFolderStore>(
  (ref) => ProductFolderStore(
    ref.watch(sharedPreferencesProvider),
    ref.watch(folderBackendProvider),
  ),
);
