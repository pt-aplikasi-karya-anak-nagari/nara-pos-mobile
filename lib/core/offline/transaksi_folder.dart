import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show PlatformException;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'offline_db.dart';
import 'product_folder_store.dart';

/// Cadangan transaksi offline di folder pilihan pengguna — tetap ada walau
/// aplikasi dihapus atau di-uninstall.
///
/// ```
/// <folder pilihan>/
///   outlet-<outletId>/
///     transaksi-offline/<local_id>.json   ← penjualan yang belum terkirim
///     shift-offline/<local_id>.json       ← buka/tutup shift yang belum terkirim
/// ```
///
/// # CARA KERJA
///
/// Folder adalah CERMIN antrian offline (tabel pending_sales & pending_ops):
///   - transaksi masuk antrian → filenya langsung ditulis;
///   - transaksi diterima server (keluar dari antrian) → filenya dihapus;
///   - setelah install ulang → pengguna memilih folder yang sama, isinya
///     dipulihkan ke antrian, lalu terkirim seperti biasa.
///
/// Mengirim ulang transaksi yang ternyata sudah sampai di server aman: setiap
/// transaksi membawa client_ref, dan server mengenali kiriman yang sama.
///
/// # ATURAN PALING PENTING
///
/// File HANYA boleh dihapus setelah folder outlet itu dipulihkan ke antrian
/// ([pulihkan]). Tepat setelah install ulang, antrian masih kosong; tanpa aturan
/// ini, penyamaan pertama akan menganggap semua file "sudah terkirim" dan
/// menghapus satu-satunya salinan transaksi yang belum sampai ke server.
///
/// # YANG TIDAK DISALIN
///
/// PIN otorisasi manajer (override_pin) tidak ditulis ke folder — folder bisa
/// dibuka aplikasi lain. Transaksi pulihan yang diskonnya butuh PIN akan
/// ditolak server dan muncul di "Pulihkan" untuk ditangani manual.
class CerminTransaksiOffline {
  CerminTransaksiOffline(this._folder, this._sumber);

  static const dirPenjualan = 'transaksi-offline';
  static const dirShift = 'shift-offline';
  static const _versi = 1;

  final ProductFolderStore _folder;
  final SumberAntrian _sumber;

  /// Outlet yang foldernya sudah dipulihkan di sesi ini — hanya untuk mereka
  /// file boleh dihapus.
  final Set<String> _sudahPulih = {};

  /// Isi file terakhir yang ditulis, per path — tulis ulang hanya bila berubah.
  final Map<String, String> _terakhir = {};

  Future<void> _antrian = Future.value();
  bool _adaPermintaan = false;

  /// Galat terakhir saat mengakses folder, untuk halaman pengaturan.
  String? galatTerakhir;

  static List<String> _dir(String outletId, String jenis) => [
    ProductFolderStore.folderOutlet(outletId),
    jenis,
  ];

  static String _namaFile(String localId) =>
      '${ProductFolderStore.namaAman(localId)}.json';

  /// Minta folder disamakan dengan antrian. Permintaan yang datang saat
  /// penyamaan sedang berjalan digabung menjadi satu putaran berikutnya.
  Future<void> jadwalkan() {
    if (_adaPermintaan) return _antrian;
    _adaPermintaan = true;
    return _jalankan(() async {
      _adaPermintaan = false;
      await _samakan();
    });
  }

  /// Folder lupa status pulihnya — dipakai saat folder diganti/dilepas.
  void lupakan() {
    _sudahPulih.clear();
    _terakhir.clear();
  }

  Future<void> _samakan() async {
    final uri = await _folder.uriAktif();
    if (uri == null) return;
    final backend = _folder.backend;
    try {
      final penjualan = await _sumber.semuaPenjualan();
      final shift = await _sumber.semuaOpShift();

      // 1. Tulis yang baru / berubah.
      final adaDi = <String, Set<String>>{}; // "outlet|jenis" → nama file
      Future<void> tulis(Map<String, Object?> baris, String jenis) async {
        final outlet = baris['outlet_id']?.toString() ?? '';
        final id = baris['local_id']?.toString() ?? '';
        if (outlet.isEmpty || id.isEmpty) return;
        final nama = _namaFile(id);
        (adaDi['$outlet|$jenis'] ??= {}).add(nama);
        final isi = jsonEncode({
          'versi': _versi,
          'jenis': jenis,
          'baris': _tanpaRahasia(baris),
        });
        final kunci = '$outlet/$jenis/$nama';
        if (_terakhir[kunci] == isi) return;
        await backend.tulis(uri, _dir(outlet, jenis), nama, isi);
        _terakhir[kunci] = isi;
      }

      for (final b in penjualan) {
        await tulis(b, dirPenjualan);
      }
      for (final b in shift) {
        await tulis(b, dirShift);
      }

      // 2. Hapus yang sudah tak di antrian (= sudah diterima server) — HANYA
      //    untuk outlet yang foldernya sudah dipulihkan.
      for (final outlet in _sudahPulih) {
        for (final jenis in const [dirPenjualan, dirShift]) {
          final ada = adaDi['$outlet|$jenis'] ?? const <String>{};
          final nama = await backend.daftarNama(uri, _dir(outlet, jenis));
          for (final n in nama) {
            if (!n.endsWith('.json') || ada.contains(n)) continue;
            await backend.hapus(uri, _dir(outlet, jenis), n);
            _terakhir.remove('$outlet/$jenis/$n');
          }
        }
      }
      galatTerakhir = null;
    } catch (e) {
      galatTerakhir = _pesan(e);
    }
  }

  /// Pulihkan transaksi offline outlet [outletId] dari folder ke antrian.
  /// Baris yang sudah ada di antrian tidak ditimpa. Setelah ini, file outlet
  /// tersebut boleh dihapus saat transaksinya terkirim.
  Future<HasilPulih> pulihkan(String outletId) {
    return _jalankan(() async {
      final uri = await _folder.uriAktif();
      if (uri == null || outletId.isEmpty) return const HasilPulih();
      try {
        final backend = _folder.backend;
        List<Map<String, Object?>> baca(
          Map<String, String> files,
          String jenis,
        ) {
          final hasil = <Map<String, Object?>>[];
          for (final isi in files.values) {
            try {
              final data = jsonDecode(isi);
              if (data is! Map || data['jenis'] != jenis) continue;
              final baris = data['baris'];
              if (baris is! Map) continue;
              final b = Map<String, Object?>.from(baris);
              // File milik outlet lain yang tersasar tidak ikut dipulihkan.
              if (b['outlet_id']?.toString() != outletId) continue;
              if ((b['local_id']?.toString() ?? '').isEmpty) continue;
              hasil.add(b);
            } catch (_) {
              // Satu file rusak tak boleh menggagalkan pemulihan lainnya.
            }
          }
          return hasil;
        }

        final penjualan = baca(
          await backend.bacaSemua(uri, _dir(outletId, dirPenjualan)),
          dirPenjualan,
        );
        final shift = baca(
          await backend.bacaSemua(uri, _dir(outletId, dirShift)),
          dirShift,
        );
        final p = await _sumber.sisipkanPenjualan(penjualan);
        final s = await _sumber.sisipkanOpShift(shift);
        _sudahPulih.add(outletId);
        galatTerakhir = null;
        return HasilPulih(penjualan: p, shift: s, dibaca: true);
      } catch (e) {
        galatTerakhir = _pesan(e);
        return const HasilPulih();
      }
    }).then((hasil) async {
      // Tulis yang ada di antrian tapi belum di folder, dan buang file yang
      // transaksinya sudah terkirim.
      if (hasil.dibaca) await jadwalkan();
      return hasil;
    });
  }

  /// Jumlah file transaksi & shift outlet di folder.
  Future<({int penjualan, int shift})> jumlah(String outletId) {
    return _jalankan(() async {
      final uri = await _folder.uriAktif();
      if (uri == null) return (penjualan: 0, shift: 0);
      try {
        final backend = _folder.backend;
        int hitung(List<String> n) =>
            n.where((x) => x.endsWith('.json')).length;
        return (
          penjualan: hitung(
            await backend.daftarNama(uri, _dir(outletId, dirPenjualan)),
          ),
          shift: hitung(
            await backend.daftarNama(uri, _dir(outletId, dirShift)),
          ),
        );
      } catch (e) {
        galatTerakhir = _pesan(e);
        return (penjualan: 0, shift: 0);
      }
    });
  }

  static Map<String, Object?> _tanpaRahasia(Map<String, Object?> baris) {
    final salin = Map<String, Object?>.from(baris);
    final raw = salin['payload'];
    if (raw is String) {
      try {
        final payload = jsonDecode(raw);
        if (payload is Map && payload.containsKey('override_pin')) {
          payload.remove('override_pin');
          salin['payload'] = jsonEncode(payload);
        }
      } catch (_) {
        // Payload tak terbaca: salin apa adanya.
      }
    }
    return salin;
  }

  Future<T> _jalankan<T>(Future<T> Function() kerja) {
    final hasil = _antrian.then((_) => kerja());
    _antrian = hasil.then<void>((_) {}, onError: (_) {});
    return hasil;
  }

  static String _pesan(Object e) {
    if (e is PlatformException) return e.message ?? e.code;
    return e.toString();
  }
}

class HasilPulih {
  const HasilPulih({this.penjualan = 0, this.shift = 0, this.dibaca = false});

  /// Baris yang benar-benar ditambahkan ke antrian (yang sudah ada dilewati).
  final int penjualan;
  final int shift;

  /// Folder berhasil dibaca.
  final bool dibaca;

  int get total => penjualan + shift;
}

/// Akses ke tabel antrian offline. Dipisah supaya cermin bisa diuji tanpa
/// SQLite.
abstract class SumberAntrian {
  Future<List<Map<String, Object?>>> semuaPenjualan();
  Future<List<Map<String, Object?>>> semuaOpShift();

  /// Tambahkan baris yang belum ada (berdasarkan local_id). Mengembalikan
  /// jumlah yang benar-benar ditambahkan.
  Future<int> sisipkanPenjualan(List<Map<String, Object?>> baris);
  Future<int> sisipkanOpShift(List<Map<String, Object?>> baris);
}

class SumberAntrianSqlite implements SumberAntrian {
  static const _kolomPenjualan = [
    'local_id',
    'outlet_id',
    'payload',
    'created_at',
    'attempts',
    'last_error',
  ];
  static const _kolomShift = [
    'local_id',
    'op_type',
    'outlet_id',
    'client_ref',
    'payload',
    'depends_on',
    'local_shift_id',
    'server_shift_id',
    'status',
    'created_at',
    'occurred_at',
    'attempts',
    'last_error',
  ];

  @override
  Future<List<Map<String, Object?>>> semuaPenjualan() async {
    final db = await OfflineDb.instance.database;
    return db.query('pending_sales', columns: _kolomPenjualan);
  }

  @override
  Future<List<Map<String, Object?>>> semuaOpShift() async {
    final db = await OfflineDb.instance.database;
    return db.query(
      'pending_ops',
      columns: _kolomShift,
      where: "status != 'done'",
    );
  }

  @override
  Future<int> sisipkanPenjualan(List<Map<String, Object?>> baris) =>
      _sisipkan('pending_sales', _kolomPenjualan, baris);

  @override
  Future<int> sisipkanOpShift(List<Map<String, Object?>> baris) =>
      _sisipkan('pending_ops', _kolomShift, baris);

  Future<int> _sisipkan(
    String tabel,
    List<String> kolom,
    List<Map<String, Object?>> baris,
  ) async {
    if (baris.isEmpty) return 0;
    final db = await OfflineDb.instance.database;
    var n = 0;
    await db.transaction((tx) async {
      final ada = {
        for (final r in await tx.query(tabel, columns: ['local_id']))
          r['local_id'] as String,
      };
      for (final b in baris) {
        final id = b['local_id']?.toString() ?? '';
        if (id.isEmpty || ada.contains(id)) continue;
        await tx.insert(tabel, {
          for (final k in kolom)
            if (b.containsKey(k)) k: b[k],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        ada.add(id);
        n++;
      }
    });
    return n;
  }
}

final cerminTransaksiProvider = Provider<CerminTransaksiOffline>(
  (ref) => CerminTransaksiOffline(
    ref.watch(productFolderStoreProvider),
    SumberAntrianSqlite(),
  ),
);
