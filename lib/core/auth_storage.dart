import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthStorage {
  AuthStorage(this._prefs, {FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const accessTokenKey = 'auth.token';
  static const refreshTokenKey = 'auth.refreshToken';
  static const userDataKey = 'auth.userData';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;

  String? _accessToken;
  String? _refreshToken;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get userData => _prefs.getString(userDataKey);

  Future<void> init() async {
    // Baca secure-storage bisa throw (BadPaddingException / AEADBadTagException /
    // "Could not decrypt value") setelah restore backup ke device baru, upgrade
    // OS, atau key Keystore ter-invalidasi. Kalau dibiarkan naik, ini memblokir
    // startup (main() → runApp() tak jalan → layar putih). Tangkap: bersihkan
    // entry korup supaya login berikutnya bisa menulis ulang, lalu lanjut sebagai
    // logged-out (token null).
    try {
      _accessToken = await _secureStorage.read(key: accessTokenKey);
      _refreshToken = await _secureStorage.read(key: refreshTokenKey);
    } catch (_) {
      _accessToken = null;
      _refreshToken = null;
      try {
        await _secureStorage.deleteAll();
      } catch (_) {
        // Best-effort — abaikan bila menghapus keystore korup pun gagal.
      }
      return;
    }

    final legacyAccessToken = _prefs.getString(accessTokenKey);
    final legacyRefreshToken = _prefs.getString(refreshTokenKey);
    if (_accessToken == null && legacyAccessToken != null) {
      _accessToken = legacyAccessToken;
      await _secureStorage.write(key: accessTokenKey, value: legacyAccessToken);
    }
    if (_refreshToken == null && legacyRefreshToken != null) {
      _refreshToken = legacyRefreshToken;
      await _secureStorage.write(
        key: refreshTokenKey,
        value: legacyRefreshToken,
      );
    }

    await _prefs.remove(accessTokenKey);
    await _prefs.remove(refreshTokenKey);
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    await Future.wait([
      _secureStorage.write(key: accessTokenKey, value: accessToken),
      _secureStorage.write(key: refreshTokenKey, value: refreshToken),
      _prefs.remove(accessTokenKey),
      _prefs.remove(refreshTokenKey),
    ]);
  }

  Future<void> saveUserData(String userJson) async {
    await _prefs.setString(userDataKey, userJson);
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    await Future.wait([
      _secureStorage.delete(key: accessTokenKey),
      _secureStorage.delete(key: refreshTokenKey),
      _prefs.remove(accessTokenKey),
      _prefs.remove(refreshTokenKey),
      _prefs.remove(userDataKey),
    ]);
  }
}

final authStorageProvider = Provider<AuthStorage>((ref) {
  throw UnimplementedError('authStorageProvider was not overridden');
});
