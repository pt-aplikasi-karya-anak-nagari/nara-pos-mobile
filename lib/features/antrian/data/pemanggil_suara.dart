import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/shared_prefs.dart';
import '../domain/kalimat_panggilan.dart';

/// Suara panggilan antrian: bel "ding-dong" lalu kalimat panggilan lewat
/// Text-to-Speech perangkat (bahasa Indonesia).
///
/// Panggilan diantrekan: menekan Panggil dua kali cepat tak membuat dua
/// suara saling menimpa — yang kedua menunggu yang pertama selesai.
/// Tak pernah melempar: perangkat tanpa mesin TTS bahasa Indonesia tetap
/// membunyikan bel, dan kegagalan suara tak menggagalkan panggilan.
class PemanggilSuara {
  PemanggilSuara(this._prefs);

  static const _kunciAktif = 'antrian.suara.aktif';
  static const _kunciKecepatan = 'antrian.suara.kecepatan';

  final SharedPreferences _prefs;
  // Dibuat saat pertama dipakai: membuka panel saja tak menyentuh mesin
  // suara (dan panel bisa diuji tanpa perangkat audio).
  late final FlutterTts _tts = FlutterTts();
  late final AudioPlayer _bel = AudioPlayer();
  bool _dipakai = false;
  Future<void> _antrean = Future.value();
  bool _siap = false;
  bool _adaSuaraIndonesia = true;

  bool get aktif => _prefs.getBool(_kunciAktif) ?? true;
  Future<void> setAktif(bool v) => _prefs.setBool(_kunciAktif, v);

  /// Kecepatan bicara 0.3 (pelan) … 0.6 (cepat). Bawaan 0.45: jelas di ruang
  /// ramai.
  double get kecepatan => _prefs.getDouble(_kunciKecepatan) ?? 0.45;
  Future<void> setKecepatan(double v) =>
      _prefs.setDouble(_kunciKecepatan, v.clamp(0.3, 0.6));

  /// Perangkat punya suara bahasa Indonesia? (diketahui setelah suara
  /// pertama disiapkan).
  bool get adaSuaraIndonesia => _adaSuaraIndonesia;

  Future<void> _siapkan() async {
    if (_siap) return;
    _siap = true;
    try {
      await _tts.awaitSpeakCompletion(true);
      var bahasa = 'id-ID';
      final ok = await _tts.isLanguageAvailable(bahasa);
      if (ok != true) {
        bahasa = 'id';
        _adaSuaraIndonesia = (await _tts.isLanguageAvailable(bahasa)) == true;
      }
      await _tts.setLanguage(bahasa);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
    } catch (_) {
      _adaSuaraIndonesia = false;
    }
  }

  /// Bunyikan panggilan untuk [nomor]. [paksa] membunyikan walau suara
  /// dimatikan (tombol "Uji suara").
  Future<void> panggil(String nomor, {bool ulang = false, bool paksa = false}) {
    if (!paksa && !aktif) return Future.value();
    final giliran = _antrean.then((_) => _bunyikan(nomor, ulang));
    _antrean = giliran.catchError((_) {});
    return _antrean;
  }

  Future<void> _bunyikan(String nomor, bool ulang) async {
    _dipakai = true;
    await _siapkan();
    try {
      await _bel.stop();
      final selesai = _bel.onPlayerComplete.first;
      await _bel.play(AssetSource('sounds/panggil.wav'));
      await selesai.timeout(const Duration(seconds: 3), onTimeout: () {});
    } catch (_) {}
    try {
      await _tts.setSpeechRate(kecepatan);
      await _tts.speak(kalimatPanggilan(nomor, ulang: ulang));
    } catch (_) {}
  }

  Future<void> berhenti() async {
    if (!_dipakai) return;
    try {
      await _tts.stop();
      await _bel.stop();
    } catch (_) {}
  }
}

final pemanggilSuaraProvider = Provider<PemanggilSuara>((ref) {
  final p = PemanggilSuara(ref.watch(sharedPreferencesProvider));
  ref.onDispose(p.berhenti);
  return p;
});
