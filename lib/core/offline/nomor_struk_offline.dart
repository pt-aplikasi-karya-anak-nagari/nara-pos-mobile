import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../device_identity.dart';
import '../shared_prefs.dart';

/// Nomor struk untuk transaksi yang dibuat saat offline:
/// `OFF-<kode perangkat>-<urut>`, mis. `OFF-3FA9C2-00042`.
///
/// # KENAPA PERLU
///
/// Sebelumnya semua struk offline bernomor "OFFLINE". Pelanggan memegang struk
/// yang tak bisa dicocokkan ke transaksi mana pun di server, dan Pemilik tak
/// bisa memeriksa apakah setiap struk yang tercetak benar-benar tercatat.
///
/// Nomor ini dicetak di struk dan dikirim ke server (offline_ref). Urutannya
/// per perangkat dan tak pernah dipakai ulang, jadi nomor yang hilang dari
/// urutan berarti ada transaksi yang tak pernah sampai ke server.
///
/// # KODE PERANGKAT
///
/// Enam karakter pertama ID perangkat (DeviceIdentity). Setelah aplikasi
/// di-install ulang, ID perangkat — dan kodenya — baru, sehingga urutan yang
/// mulai lagi dari 1 tak pernah menabrak nomor lama.
class NomorStrukOffline {
  NomorStrukOffline(this._prefs, {String Function()? idPerangkat})
    : _idPerangkat = idPerangkat ?? (() => DeviceIdentity.current.id);

  static const _kunciUrut = 'offline.struk.urut';

  final SharedPreferences _prefs;
  final String Function() _idPerangkat;

  String get kodePerangkat {
    final hex = _idPerangkat().replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (hex.length < 6) return 'TANPAID';
    return hex.substring(0, 6).toUpperCase();
  }

  /// Nomor urut terakhir yang sudah dipakai (0 = belum pernah). Dilaporkan
  /// ke server supaya transaksi yang dihapus dari perangkat sebelum terkirim
  /// tetap meninggalkan jejak.
  int get urutTerakhir => _prefs.getInt(_kunciUrut) ?? 0;

  /// Ambil nomor berikutnya. Nomor yang sudah diambil tak pernah dipakai lagi,
  /// walau transaksinya kemudian gagal disimpan.
  Future<String> berikutnya() async {
    final urut = (_prefs.getInt(_kunciUrut) ?? 0) + 1;
    await _prefs.setInt(_kunciUrut, urut);
    return 'OFF-$kodePerangkat-${urut.toString().padLeft(5, '0')}';
  }
}

final nomorStrukOfflineProvider = Provider<NomorStrukOffline>(
  (ref) => NomorStrukOffline(ref.watch(sharedPreferencesProvider)),
);

/// Nomor antrian untuk penjualan OFFLINE: `<3 karakter kode perangkat>-<urut>`,
/// mis. `3FA-012` (urut tiga digit, seperti nomor online). Urutannya per perangkat dan kembali ke 1 setiap hari.
///
/// # KENAPA BUKAN NOMOR BIASA
///
/// Saat online, server memberi nomor antrian (1, 2, 3, …) satu urutan untuk
/// semua kasir & pesanan QR. Tablet yang offline tak bisa bertanya ke server;
/// kalau ia ikut memberi "12", nomor itu bisa sama dengan "12" yang sedang
/// dipanggil kasir lain yang online. Awalan kode perangkat membuatnya tak
/// pernah bentrok — dan tetap pendek untuk dipanggil.
class NomorAntrianOffline {
  NomorAntrianOffline(
    this._prefs, {
    String Function()? idPerangkat,
    DateTime Function()? jam,
  }) : _struk = NomorStrukOffline(_prefs, idPerangkat: idPerangkat),
       _jam = jam ?? DateTime.now;

  static const _kunciTanggal = 'offline.antrian.tanggal';
  static const _kunciUrut = 'offline.antrian.urut';

  final SharedPreferences _prefs;
  final NomorStrukOffline _struk;
  final DateTime Function() _jam;

  String get _awalan {
    final kode = _struk.kodePerangkat;
    return kode == 'TANPAID' ? 'OFF' : kode.substring(0, 3);
  }

  static String _tanggal(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  /// Ambil nomor berikutnya hari ini.
  Future<String> berikutnya() async {
    final hari = _tanggal(_jam());
    final urut = _prefs.getString(_kunciTanggal) == hari
        ? (_prefs.getInt(_kunciUrut) ?? 0) + 1
        : 1;
    await _prefs.setString(_kunciTanggal, hari);
    await _prefs.setInt(_kunciUrut, urut);
    return '$_awalan-${urut.toString().padLeft(3, '0')}';
  }
}

final nomorAntrianOfflineProvider = Provider<NomorAntrianOffline>(
  (ref) => NomorAntrianOffline(ref.watch(sharedPreferencesProvider)),
);
