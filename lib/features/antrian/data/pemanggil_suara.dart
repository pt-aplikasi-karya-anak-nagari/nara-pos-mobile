import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/connectivity_service.dart';
import '../../../core/shared_prefs.dart';
import '../../settings/data/app_settings.dart';
import '../domain/kalimat_panggilan.dart';
import '../domain/suara_tts.dart';

/// Suara panggilan antrian: bel "ding-dong" lalu kalimat panggilan lewat
/// Text-to-Speech perangkat (bahasa Indonesia).
///
/// # SUARA YANG ALAMI
///
/// Tanpa pengaturan, mesin TTS memakai suara bawaannya — sering suara lokal
/// berkualitas rendah atau mesin pabrikan yang kaku. Di sini:
///   - Android memakai mesin Google TTS bila terpasang;
///   - suara Indonesia dipilih menurut kualitasnya (lihat [pilihSuaraTerbaik]):
///     suara online (neural) saat ada internet, suara lokal terbaik saat
///     offline — dinilai ulang setiap memanggil;
///   - pengguna boleh memilih suara sendiri di pengaturan.
///
/// Panggilan diantrekan: menekan Panggil dua kali cepat tak membuat dua
/// suara saling menimpa. Tak pernah melempar: kegagalan suara tak
/// menggagalkan panggilan.
class PemanggilSuara {
  PemanggilSuara(
    this._prefs, {
    bool Function()? online,
    OutletAppSettings Function()? pengaturan,
  }) : _online = online ?? (() => true),
       _pengaturan = pengaturan ?? (() => const OutletAppSettings());

  static const _kunciAktif = 'antrian.suara.aktif';
  static const _kunciKecepatan = 'antrian.suara.kecepatan';
  static const _kunciSuara = 'antrian.suara.nama';

  final SharedPreferences _prefs;
  final bool Function() _online;

  /// Pengaturan outlet dari Pemilik (suara nyala/mati & kalimat panggilan).
  final OutletAppSettings Function() _pengaturan;

  // Dibuat saat pertama dipakai: membuka panel saja tak menyentuh mesin
  // suara (dan panel bisa diuji tanpa perangkat audio).
  late final FlutterTts _tts = FlutterTts();
  late final AudioPlayer _bel = AudioPlayer();
  bool _dipakai = false;

  Future<void> _antrean = Future.value();
  Future<void>? _persiapan;
  List<SuaraTts> _suaraIndonesia = const [];
  String? _suaraTerpasang;

  /// Suara di PERANGKAT INI (membisukan satu tablet saja).
  bool get aktif => _prefs.getBool(_kunciAktif) ?? true;

  /// Pemilik menyalakan suara antrian untuk outlet ini.
  bool get aktifDiOutlet => _pengaturan().antrianSuaraAktif;
  Future<void> setAktif(bool v) => _prefs.setBool(_kunciAktif, v);

  /// Kecepatan bicara 0.3 (pelan) … 0.6 (cepat). Bawaan 0.47 ≈ kecepatan
  /// bicara wajar (0.5 = normal di Android).
  double get kecepatan => _prefs.getDouble(_kunciKecepatan) ?? 0.47;
  Future<void> setKecepatan(double v) =>
      _prefs.setDouble(_kunciKecepatan, v.clamp(0.3, 0.6));

  /// Nama suara pilihan pengguna; null = otomatis (paling alami).
  String? get suaraPilihan => _prefs.getString(_kunciSuara);
  Future<void> setSuaraPilihan(String? nama) => nama == null
      ? _prefs.remove(_kunciSuara)
      : _prefs.setString(_kunciSuara, nama);

  /// Perangkat punya suara bahasa Indonesia? (setelah [daftarSuara]).
  bool get adaSuaraIndonesia => _suaraIndonesia.isNotEmpty;

  /// Suara Indonesia di perangkat ini, terbaik dulu.
  Future<List<SuaraTts>> daftarSuara() async {
    // Mesin TTS yang macet tak boleh membuat pengaturan menunggu selamanya.
    await _siapkan().timeout(const Duration(seconds: 6), onTimeout: () {});
    return _suaraIndonesia;
  }

  Future<void> _siapkan() => _persiapan ??= _persiapkan();

  Future<void> _persiapkan() async {
    _dipakai = true;
    try {
      await _tts.awaitSpeakCompletion(true);
      if (Platform.isAndroid) {
        final mesin = await _tts.getEngines;
        if (mesin is List && mesin.contains(mesinGoogle)) {
          await _tts.setEngine(mesinGoogle);
        }
      }
      if (Platform.isIOS) {
        // Tetap terdengar di speaker walau sakelar senyap iPad menyala.
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        ], IosTextToSpeechAudioMode.spokenAudio);
      }
      await _tts.setLanguage('id-ID');
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      _suaraIndonesia = await _muatSuara();
      // Mesin yang baru diganti kadang belum selesai memuat daftarnya.
      if (_suaraIndonesia.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        _suaraIndonesia = await _muatSuara();
      }
    } catch (_) {
      // Tanpa daftar suara: tetap bicara dengan suara bawaan id-ID.
    }
  }

  Future<List<SuaraTts>> _muatSuara() async {
    final mentah = await _tts.getVoices;
    if (mentah is! List) return const [];
    return urutkanSuaraIndonesia([
      for (final m in mentah)
        if (m is Map) SuaraTts.dariMap(m),
    ], online: _online());
  }

  /// Pasang suara yang paling cocok SAAT INI (online/offline bisa berubah).
  Future<void> _pasangSuara({String? paksaNama}) async {
    final online = _online();
    SuaraTts? pilih;
    final nama = paksaNama ?? suaraPilihan;
    if (nama != null) {
      for (final s in _suaraIndonesia) {
        if (s.nama == nama && (online || !s.butuhInternet)) pilih = s;
      }
    }
    pilih ??= pilihSuaraTerbaik(_suaraIndonesia, online: online);
    if (pilih == null || pilih.nama == _suaraTerpasang) return;
    try {
      await _tts.setVoice(pilih.kePlatform);
      _suaraTerpasang = pilih.nama;
    } catch (_) {}
  }

  /// Bunyikan panggilan untuk [nomor]. Diam bila Pemilik mematikan suara
  /// antrian atau perangkat ini dibisukan; [paksa] tetap membunyikan
  /// (tombol "Uji suara").
  Future<void> panggil(
    String nomor, {
    bool ulang = false,
    bool paksa = false,
    String nama = '',
    String meja = '',
  }) {
    if (!paksa && (!aktif || !aktifDiOutlet)) return Future.value();
    final teks = susunPanggilan(
      _pengaturan().antrianTeksPanggilan,
      nomor,
      nama: nama,
      meja: meja,
      ulang: ulang,
    );
    return _antre(() => _bunyikan(teks));
  }

  /// Dengarkan satu suara tertentu (pilihan suara di pengaturan); null =
  /// suara otomatis yang akan dipakai saat ini.
  Future<void> pratinjau(String? namaSuara) => _antre(
    () => _bunyikan(
      susunPanggilan(
        _pengaturan().antrianTeksPanggilan,
        '001',
        nama: 'Budi',
        meja: '4',
      ),
      suara: namaSuara,
      bel: false,
    ),
  );

  Future<void> _antre(Future<void> Function() kerja) {
    final giliran = _antrean.then((_) => kerja());
    _antrean = giliran.catchError((_) {});
    return _antrean;
  }

  Future<void> _bunyikan(
    String kalimat, {
    String? suara,
    bool bel = true,
  }) async {
    await _siapkan();
    if (bel) {
      try {
        await _bel.stop();
        final selesai = _bel.onPlayerComplete.first;
        await _bel.play(AssetSource('sounds/panggil.wav'));
        await selesai.timeout(const Duration(seconds: 3), onTimeout: () {});
      } catch (_) {}
    }
    try {
      await _pasangSuara(paksaNama: suara);
      await _tts.setSpeechRate(kecepatan);
      await _tts.speak(kalimat);
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
  final p = PemanggilSuara(
    ref.watch(sharedPreferencesProvider),
    online: () => !ref.read(isOfflineProvider),
    pengaturan: () =>
        ref.read(outletAppSettingsProvider).value ?? const OutletAppSettings(),
  );
  ref.onDispose(p.berhenti);
  return p;
});
