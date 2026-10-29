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
