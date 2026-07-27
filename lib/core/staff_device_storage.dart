import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Pengesahan perangkat kasir yang tersimpan di keystore.
///
/// MASALAH YANG DISELESAIKAN
///
/// Sesi kasir mensyaratkan Owner/Manajer mengetik email+password SETIAP kali
/// staf berganti. Di satu tablet yang dipakai bergantian sepanjang hari, itu
/// berarti pengelola harus berdiri di dekat kasir tiap pergantian.
///
/// Setelah pengelola sekali membuktikan diri DAN memilih outlet, server
/// menerbitkan token perangkat. Token itu disimpan di sini, dan pergantian staf
/// berikutnya cukup: pilih staf → setujui OTP. Tanpa password lagi.
///
/// KENAPA TOKEN, BUKAN CUMA ID OUTLET
///
/// Menyimpan hanya ID outlet lalu mengirimkannya tidak membuktikan apa pun ke
/// server: ID outlet bukan rahasia, muncul di URL dan respons API, dan siapa pun
/// bisa mengarang satu. Yang membuktikan perangkat ini pernah lolos password
/// pengelola adalah token acaknya. ID outlet tetap disimpan, tapi perannya cuma
/// untuk ditampilkan ("Perangkat ini terdaftar di FEB KOPI") — server selalu
/// menentukan outlet dari barisnya sendiri, bukan dari kiriman perangkat.
///
/// APA YANG TIDAK DIBERIKAN TOKEN INI
///
/// Token TIDAK menerbitkan sesi. Sesi kasir tetap hanya terbit setelah OTP ke
/// email pengelola (atau PIN pengelola) diverifikasi. Jadi tablet yang hilang
/// tidak bisa dipakai berjualan — pencurinya tak bisa membaca email pengelola.
class StaffDeviceStorage {
  StaffDeviceStorage({FlutterSecureStorage? secureStorage})
    : _storage = secureStorage ?? const FlutterSecureStorage();

  static const tokenKey = 'staffDevice.token';
  static const outletIdKey = 'staffDevice.outletId';
  static const outletNameKey = 'staffDevice.outletName';

  final FlutterSecureStorage _storage;

  /// Simpan pengesahan. Dipanggil setelah pengelola berhasil masuk DAN outlet
  /// sudah pasti — momen yang sama saat server menerbitkan tokennya.
  ///
  /// [token] kosong berarti server tidak menerbitkan apa-apa (mis. outlet belum
  /// dipilih); jangan menimpa pengesahan yang sudah ada dengan nilai kosong,
  /// karena itu justru mencabut kemudahan yang sudah didapat.
  Future<void> simpan({
    required String token,
    required String outletId,
    required String outletName,
  }) async {
    if (token.isEmpty || outletId.isEmpty) return;
    try {
      await _storage.write(key: tokenKey, value: token);
      await _storage.write(key: outletIdKey, value: outletId);
      await _storage.write(key: outletNameKey, value: outletName);
    } catch (_) {
      // Gagal menulis keystore tidak boleh menggagalkan sesi yang sedang
      // berjalan — pengelola sudah terverifikasi, staf tetap bisa dipilih.
      // Konsekuensinya hanya: lain kali diminta password lagi.
    }
  }

  /// Token perangkat, atau null bila perangkat belum disahkan.
  Future<String?> bacaToken() => _bacaAman(tokenKey);

  Future<String?> bacaOutletId() => _bacaAman(outletIdKey);

  Future<String?> bacaOutletName() => _bacaAman(outletNameKey);

  /// Hapus pengesahan — dipakai saat server menolak token (dicabut, pengelola
  /// tak lagi berwenang) dan saat pengguna sengaja melepas perangkat.
  Future<void> hapus() async {
    try {
      await _storage.delete(key: tokenKey);
      await _storage.delete(key: outletIdKey);
      await _storage.delete(key: outletNameKey);
    } catch (_) {
      // Diabaikan: pemanggil sudah beralih ke layar login pengelola, dan entri
      // yang tertinggal akan ditolak server pada percobaan berikutnya.
    }
  }

  /// Baca yang menoleransi keystore rusak.
  ///
  /// Membaca secure storage bisa melempar (BadPaddingException,
  /// AEADBadTagException, "Could not decrypt value") setelah restore backup ke
  /// perangkat baru, upgrade OS, atau key Keystore ter-invalidasi. Kalau
  /// dibiarkan naik, layar login gagal dimuat sama sekali. Perlakukan sebagai
  /// "belum disahkan" dan bersihkan entri rusaknya supaya provisioning
  /// berikutnya bisa menulis ulang.
  ///
  /// Pola ini menyamai AuthStorage.init(), yang sudah menghadapi persoalan yang
  /// sama untuk token sesi.
  Future<String?> _bacaAman(String key) async {
    try {
      final nilai = await _storage.read(key: key);
      if (nilai == null || nilai.isEmpty) return null;
      return nilai;
    } catch (_) {
      await hapus();
      return null;
    }
  }
}

/// Satu instance dipakai bersama: keystore adalah sumber tunggal, dan membuat
/// beberapa pembungkus hanya memperbanyak jalur yang bisa saling menyimpang.
final staffDeviceStorageProvider = Provider<StaffDeviceStorage>((ref) {
  return StaffDeviceStorage();
});
