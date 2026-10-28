import 'dart:async';

import 'package:flutter_riverpod/legacy.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../features/outlet/data/outlet_service.dart';
import '../../features/products/domain/product.dart';
import '../../features/user/data/auth_service.dart';
import '../connectivity_service.dart';
import '../outlet_scope.dart';
import 'product_cache.dart';

class HasilSinkronProduk {
  const HasilSinkronProduk({
    this.jumlah = 0,
    this.basi = 0,
    this.bertambah = 0,
    this.dihapus = 0,
    this.lengkap = false,
    this.dilewati = false,
    this.galat,
  });

  /// Produk yang diambil dari API dan disimpan pada sinkron ini.
  final int jumlah;

  /// Produk yang flag-nya diubah menjadi "belum tersimpan" (versi berubah).
  final int basi;

  /// Produk yang sebelumnya belum ada di lokal (produk baru).
  final int bertambah;

  /// Produk lokal yang dibuang karena sudah tidak ada di server.
  final int dihapus;

  /// Katalog lokal kini sama persis dengan server.
  final bool lengkap;

  /// Tidak dijalankan: sinkron lain untuk outlet ini sedang berjalan, atau
  /// pemeriksaan terakhir masih baru.
  final bool dilewati;

  final Object? galat;

  /// Ada yang berubah di katalog lokal — tampilan kasir perlu dimuat ulang.
  bool get adaPerubahan => jumlah > 0 || basi > 0 || dihapus > 0;

  /// Daftar produknya berubah (ada yang baru / hilang), bukan hanya isinya.
  /// Isi yang berubah sudah tampil lewat produkLokalProvider; daftar yang
  /// berubah perlu grid dimuat ulang.
  bool get daftarBerubah => bertambah > 0 || dihapus > 0;
}

/// Menjaga katalog produk di perangkat tetap sama dengan server, sambil
/// mengambil data sesedikit mungkin dari API.
///
/// # ALURNYA
///
///   1. Ambil daftar versi semua produk outlet (`/products/versions`) — hanya
///      `{id, version}`, jauh lebih kecil dari data produknya.
///   2. Bandingkan dengan versi lokal tiap produk:
///        - sama          → flag tetap "tersimpan", produk TIDAK diambil.
///        - beda / baru   → flag diubah "belum tersimpan".
///        - tak ada lagi  → salinan lokal dibuang.
///   3. Ambil HANYA produk yang belum tersimpan (`/products/by-ids`, 100 per
///      panggilan), simpan satu per satu, flag kembali "tersimpan".
///
/// Server lama yang belum punya endpoint versi → jatuh ke cara lama: ambil
/// seluruh katalog per halaman.
class ProductOfflineSync {
  ProductOfflineSync({
    required this.ambilVersi,
    required this.ambilPerId,
    required this.ambilHalaman,
    required this.versiLokal,
    required this.tandaiBasi,
    required this.simpan,
    required this.pangkas,
    required this.tandaiLengkap,
    this.jedaMinimum = const Duration(seconds: 30),
    DateTime Function()? jam,
  }) : _jam = jam ?? DateTime.now;

  static const ukuranHalaman = 100;
  static const maksIdPerPanggilan = 100;

  /// Batas pengaman cara lama: 100 halaman × 100 = 10.000 produk.
  static const maksHalaman = 100;

  /// Null = server belum punya endpoint versi.
  final Future<Map<String, String>?> Function(String outletId) ambilVersi;
  final Future<List<Product>> Function(String outletId, List<String> ids)
  ambilPerId;
  final Future<List<Product>> Function(String outletId, int page, int limit)
  ambilHalaman;
  final Future<Map<String, String>> Function(String outletId) versiLokal;
  final Future<void> Function(String outletId, Iterable<String> ids) tandaiBasi;
  final Future<void> Function(String outletId, List<Product> products) simpan;
  final Future<void> Function(String outletId, Set<String> idTetap) pangkas;
  final Future<void> Function(String outletId) tandaiLengkap;
  final Duration jedaMinimum;
  final DateTime Function() _jam;

  final Set<String> _berjalan = {};
  final Map<String, DateTime> _terakhirDicek = {};

  DateTime? terakhirDicek(String outletId) => _terakhirDicek[outletId];

  Future<HasilSinkronProduk> sinkron(
    String outletId, {
    bool paksa = false,
  }) async {
    if (outletId.isEmpty || _berjalan.contains(outletId)) {
      return const HasilSinkronProduk(dilewati: true);
    }
    final terakhir = _terakhirDicek[outletId];
    if (!paksa &&
        terakhir != null &&
        _jam().difference(terakhir) < jedaMinimum) {
      return const HasilSinkronProduk(dilewati: true);
    }

    _berjalan.add(outletId);
    try {
      final Map<String, String>? server;
      try {
        server = await ambilVersi(outletId);
      } catch (e) {
        return HasilSinkronProduk(galat: e);
      }
      if (server == null) return await _sinkronPenuh(outletId);
      return await _sinkronVersi(outletId, server);
    } finally {
      _berjalan.remove(outletId);
    }
  }

  Future<HasilSinkronProduk> _sinkronVersi(
    String outletId,
    Map<String, String> server,
  ) async {
    final lokal = await versiLokal(outletId);

    // Produk yang perlu diambil: belum ada di lokal, atau versinya berbeda.
    final perluAmbil = [
      for (final e in server.entries)
        if (lokal[e.key] != e.value) e.key,
    ];
    // Yang sudah ada di lokal tapi berubah → flag "belum tersimpan" dulu,
    // supaya status ini tetap tercatat walau pengambilan di bawah terputus.
    final basi = perluAmbil.where(lokal.containsKey).toList();
    final bertambah = perluAmbil.length - basi.length;
    await tandaiBasi(outletId, basi);

    final dihapus = lokal.keys.where((id) => !server.containsKey(id)).length;
    if (dihapus > 0) await pangkas(outletId, server.keys.toSet());

    var jumlah = 0;
    try {
      for (var i = 0; i < perluAmbil.length; i += maksIdPerPanggilan) {
        final potong = perluAmbil.sublist(
          i,
          (i + maksIdPerPanggilan).clamp(0, perluAmbil.length),
        );
        final produk = await ambilPerId(outletId, potong);
        if (produk.isNotEmpty) {
          await simpan(outletId, produk);
          jumlah += produk.length;
        }
      }
    } catch (e) {
      return HasilSinkronProduk(
        jumlah: jumlah,
        basi: basi.length,
        bertambah: bertambah,
        dihapus: dihapus,
        galat: e,
      );
    }

    await tandaiLengkap(outletId);
    _terakhirDicek[outletId] = _jam();
    return HasilSinkronProduk(
      jumlah: jumlah,
      basi: basi.length,
      bertambah: bertambah,
      dihapus: dihapus,
      lengkap: true,
    );
  }

  /// Cara lama untuk server tanpa endpoint versi: seluruh katalog per halaman.
  Future<HasilSinkronProduk> _sinkronPenuh(String outletId) async {
    final ids = <String>{};
    var jumlah = 0;
    try {
      for (var page = 1; page <= maksHalaman; page++) {
        final produk = await ambilHalaman(outletId, page, ukuranHalaman);
        if (produk.isNotEmpty) {
          await simpan(outletId, produk);
          jumlah += produk.length;
          for (final p in produk) {
            final id = p.remoteId;
            if (id != null && id.isNotEmpty) ids.add(id);
          }
        }
        if (produk.length < ukuranHalaman) {
          await pangkas(outletId, ids);
          await tandaiLengkap(outletId);
          _terakhirDicek[outletId] = _jam();
          return HasilSinkronProduk(
            jumlah: jumlah,
            bertambah: jumlah,
            lengkap: true,
          );
        }
      }
      return HasilSinkronProduk(jumlah: jumlah);
    } catch (e) {
      return HasilSinkronProduk(jumlah: jumlah, galat: e);
    }
  }
}

final productOfflineSyncProvider = Provider<ProductOfflineSync>((ref) {
  final cache = ref.watch(productCacheProvider);
  OutletService api() => ref.read(outletServiceProvider);
  return ProductOfflineSync(
    ambilVersi: (outletId) => api().getProductVersions(outletId),
    ambilPerId: (outletId, ids) => api().getProductsByIds(outletId, ids),
    ambilHalaman: (outletId, page, limit) =>
        api().getProducts(outletId, page: page, limit: limit),
    versiLokal: cache.versiLokal,
    tandaiBasi: cache.tandaiBasi,
    simpan: cache.simpanBanyak,
    pangkas: cache.pangkas,
    tandaiLengkap: cache.tandaiKatalogLengkap,
  );
});

/// Naik setiap kali DAFTAR produk lokal berubah (produk baru / dihapus) karena
/// sinkron. Halaman kasir memuat ulang gridnya saat nilai ini berubah.
final katalogLokalBerubahProvider = StateProvider<int>((ref) => 0);

/// Tombol "periksa katalog sekarang" untuk outlet aktif. Aman dipanggil
/// sesering apa pun: pemanggilan berdekatan dilewati (lihat
/// [ProductOfflineSync.jedaMinimum]) kecuali [paksa] — dan sinkron yang
/// sedang berjalan untuk outlet yang sama tidak pernah digandakan.
class SinkronProduk {
  SinkronProduk(this._ref);
  final Ref _ref;

  Future<HasilSinkronProduk?> jalankan({bool paksa = false}) async {
    // Tanpa sesi login, request hanya berujung 401 dan toast "Sesi berakhir".
    if (_ref.read(authProvider).user == null) return null;
    final outletId = _ref.read(activeOutletIdProvider);
    if (outletId == null || outletId.isEmpty) return null;
    if (_ref.read(isOfflineProvider)) return null;

    final hasil = await _ref
        .read(productOfflineSyncProvider)
        .sinkron(outletId, paksa: paksa);
    if (hasil.adaPerubahan || hasil.lengkap) {
      _ref.invalidate(offlineDataSyncedAtProvider);
    }
    if (hasil.daftarBerubah) {
      _ref.read(katalogLokalBerubahProvider.notifier).state++;
    }
    return hasil;
  }
}

final sinkronProdukProvider = Provider<SinkronProduk>(SinkronProduk.new);

/// Menjalankan sinkron produk otomatis: saat outlet aktif berganti (termasuk
/// tepat setelah login), setiap koneksi kembali online, dan berkala tiap 5
/// menit selama aplikasi terbuka. Di-watch sekali di shell aplikasi.
final productOfflineAutoSyncProvider = Provider<void>((ref) {
  void jalan() => unawaited(ref.read(sinkronProdukProvider).jalankan());

  ref.listen<String?>(activeOutletIdProvider, (_, _) => jalan());
  ref.listen<AsyncValue<ConnectionStatus>>(connectivityProvider, (_, next) {
    if (next.value == ConnectionStatus.online) jalan();
  });
  final timer = Timer.periodic(const Duration(minutes: 5), (_) => jalan());
  ref.onDispose(timer.cancel);
  Future.microtask(jalan);
});
