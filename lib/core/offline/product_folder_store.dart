import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show PlatformException;
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/products/domain/product.dart';
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
  ProductFolderStore(this._backend);

  static const _versi = 1;

  /// Penanda penyimpanan cadangan. Lokasi sebenarnya ditentukan di sisi
  /// native dan sengaja tidak pernah diketahui atau ditampilkan aplikasi.
  static const lokasiCadangan = 'cadangan';

  final FolderBackend _backend;

  /// `outlet|produk` → JSON produk yang terakhir ditulis/dibaca. Sinkron
  /// berulang jadi tidak menulis ulang file yang isinya tidak berubah.
  final Map<String, String> _terakhir = {};

  /// Semua operasi berjalan berurutan: produk 1 selesai ditulis, baru produk
  /// berikutnya.
  Future<void> _antrian = Future.value();

  /// Pesan galat terakhir saat menulis/membaca cadangan, untuk halaman
  /// pengaturan. Null bila operasi terakhir berhasil.
  String? galatTerakhir;

  /// outletId → ID produk yang filenya ada di cadangan. Diisi dari daftar
  /// file saat pertama diminta, lalu diperbarui setiap tulis/pangkas.
  final Map<String, Set<String>> _idDiketahui = {};

  final _perubahan = StreamController<String>.broadcast();

  /// Memancarkan outletId setiap isi cadangan outlet itu berubah, atau `*`
  /// bila akses ke cadangan berubah.
  Stream<String> get perubahan => _perubahan.stream;

  bool get didukung => _backend.didukung;

  /// Izin penyimpanan cadangan sudah diberikan.
  Future<bool> aktif() async => await _uriAktif() != null;

  /// Dipanggil saat izin baru saja diberikan: lupakan memori tulis supaya
  /// semua data ditulis lagi ke cadangan.
  void aksesBerubah() {
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

  /// Cadangan add-on seluruh produk outlet (productId → grup, JSON mentah dari
  /// server) — satu file per outlet.
  Future<void> simpanAddOn(
    String outletId,
    Map<String, List<Map<String, dynamic>>> semua,
  ) {
    return _jalankan(() async {
      final uri = await _uriAktif();
      if (uri == null || outletId.isEmpty) return;
      try {
        await _backend.tulis(
          uri,
          [folderOutlet(outletId), 'addon'],
          'semua.json',
          jsonEncode({'versi': _versi, 'outlet_id': outletId, 'addon': semua}),
        );
      } catch (e) {
        galatTerakhir = _pesan(e);
      }
    });
  }

  /// Add-on seluruh produk outlet dari cadangan; kosong bila tak ada.
  Future<Map<String, List<Map<String, dynamic>>>> muatAddOn(String outletId) {
    return _jalankan(() async {
      final uri = await _uriAktif();
      if (uri == null || outletId.isEmpty) return const {};
      try {
        final files = await _backend.bacaSemua(uri, [
          folderOutlet(outletId),
          'addon',
        ]);
        final data = jsonDecode(files['semua.json'] ?? '{}');
        if (data is! Map || data['outlet_id'] != outletId) return const {};
        final addon = data['addon'];
        if (addon is! Map) return const {};
        return {
          for (final e in addon.entries)
            if (e.value is List)
              e.key.toString(): [
                for (final g in e.value as List)
                  if (g is Map) Map<String, dynamic>.from(g),
              ],
        };
      } catch (e) {
        galatTerakhir = _pesan(e);
        return const {};
      }
    });
  }

  Future<String?> _uriAktif() async {
    if (!_backend.didukung) return null;
    try {
      return await _backend.punyaAkses(lokasiCadangan) ? lokasiCadangan : null;
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
  (ref) => ProductFolderStore(ref.watch(folderBackendProvider)),
);
