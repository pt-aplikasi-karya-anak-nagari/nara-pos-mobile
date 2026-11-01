import 'dart:convert';
import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared_prefs.dart';
import 'jam_terpercaya.dart';

/// Jam untuk pengawasan offline: kapan tablet terakhir tersambung ke server,
/// dan apakah jam tablet pernah dimundurkan.
///
/// # KENAPA PERLU
///
/// - **Batas lama offline.** Kasir yang dinonaktifkan Pemilik saat tablet
///   offline bisa terus berjualan sampai tablet online lagi. Dengan batas,
///   penjualan offline baru ditolak setelah tablet terlalu lama tak tersambung.
/// - **Jam dimundurkan.** Memundurkan jam tablet bisa memindah omzet ke shift
///   atau hari lain, dan — tanpa pengaman — memperpanjang batas offline.
///
/// # CARA KERJANYA
///
/// Disimpan dua titik: terakhir tersambung ke server, dan jam TERBESAR yang
/// pernah dilihat aplikasi. Jam sekarang yang jauh lebih kecil dari jam
/// terbesar berarti jam tablet dimundurkan. Lama offline dihitung dari jam
/// terbesar, sehingga memundurkan jam tak memperpendeknya.
class JamOffline {
  JamOffline(this._prefs, {DateTime Function()? sekarang, SumberUptime? uptime})
    : _sekarang = sekarang ?? DateTime.now,
      _uptime = uptime ?? SumberUptime();

  static const _kunciOnline = 'offline.jam.terakhir_online';
  static const _kunciServer = 'offline.jam.server';
  static const _kunciTerbesar = 'offline.jam.terbesar';
  static const _kunciTitik = 'offline.jam.titik';
  static const _kunciDiubah = 'offline.jam.diubah';
  static const _kunciSelisihOnline = 'offline.jam.selisih_online_ms';

  final SumberUptime _uptime;

  /// Jam terpercaya hasil [periksa] terakhir + stopwatch sejak itu — supaya
  /// [waktuAcuan] (sinkron) tetap bisa memakainya.
  DateTime? _terpercaya;
  final Stopwatch _sejakTerpercaya = Stopwatch();

  /// Selisih jam yang masih dianggap wajar (sinkronisasi jam otomatis).
  static const toleransiMundur = Duration(minutes: 2);

  /// Respons server dicatat paling sering sekali per jeda ini.
  static const jedaCatat = Duration(seconds: 30);

  final SharedPreferences _prefs;
  final DateTime Function() _sekarang;

  DateTime? _baca(String kunci) {
    final ms = _prefs.getInt(kunci);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _tulis(String kunci, DateTime t) =>
      _prefs.setInt(kunci, t.millisecondsSinceEpoch);

  DateTime? get terakhirOnline => _baca(_kunciOnline);

  /// Jam SERVER pada kontak terakhir (header Date respons).
  DateTime? get jamServerTerakhir => _baca(_kunciServer);

  /// Catat jam server dari respons. Hanya pernah maju.
  Future<void> catatJamServer(DateTime server) async {
    final lama = jamServerTerakhir;
    if (lama == null || server.isAfter(lama)) {
      await _tulis(_kunciServer, server);
    }
  }

  /// Jam acuan yang tak bisa dimundurkan: yang paling akhir di antara jam
  /// tablet, jam terbesar yang pernah dilihat tablet, dan jam server pada
  /// kontak terakhir. Dipakai untuk masa berlaku langganan saat offline —
  /// memundurkan jam tablet tak membuat langganan yang habis hidup lagi.
  DateTime waktuAcuan() {
    var acuan = _sekarang();
    final terpercaya = _terpercaya?.add(_sejakTerpercaya.elapsed);
    for (final t in [jamTerbesar, jamServerTerakhir, terpercaya]) {
      if (t != null && t.isAfter(acuan)) acuan = t;
    }
    return acuan;
  }

  TitikJam? get _titik {
    final raw = _prefs.getString(_kunciTitik);
    if (raw == null) return null;
    try {
      return TitikJam.dariJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// true bila jam perangkat pernah terdeteksi diubah sejak kontak terakhir
  /// dengan server. Ikut dikirim di transaksi offline supaya Pemilik bisa
  /// meninjaunya, walau jamnya sudah dibetulkan sebelum menjual.
  bool get pernahDiubah => _prefs.getBool(_kunciDiubah) ?? false;

  /// Selisih jam perangkat terhadap server pada kontak terakhir (perangkat −
  /// server). Untuk peringatan saat online — struk mencetak jam perangkat.
  Duration? get selisihSaatOnline {
    final ms = _prefs.getInt(_kunciSelisihOnline);
    return ms == null ? null : Duration(milliseconds: ms);
  }

  /// Kontak dengan server: jam server [server] (header Date) adalah kebenaran.
  ///
  /// Dicatat sebagai titik jam terpercaya (server + uptime sistem), sebagai
  /// waktu terakhir online, dan sebagai jam terbesar — BUKAN jam perangkat,
  /// yang bisa saja sudah diubah selagi online lalu dibawa offline.
  Future<void> catatKontakServer(DateTime server) async {
    final now = _sekarang();
    final lalu = terakhirOnline;
    final titikLama = _titik;
    if (lalu != null &&
        titikLama != null &&
        !server.isBefore(lalu) &&
        server.difference(lalu) < jedaCatat) {
      return;
    }
    await catatJamServer(server);
    final kini = await _uptime.baca();
    if (kini != null) {
      await _prefs.setString(
        _kunciTitik,
        jsonEncode(
          TitikJam(
            server: server,
            uptimeMs: kini.uptimeMs,
            boot: kini.boot,
          ).toJson(),
        ),
      );
    }
    await _tulis(_kunciOnline, server);
    await _tulis(_kunciTerbesar, server);
    await _prefs.setInt(
      _kunciSelisihOnline,
      now.difference(server).inMilliseconds,
    );
    await _prefs.remove(_kunciDiubah);
    _terpercaya = server;
    _sejakTerpercaya
      ..reset()
      ..start();
  }

  /// Nilai jam perangkat sekarang terhadap jam terpercaya (atau, bila tak
  /// diketahui, terhadap jam terbesar yang pernah terlihat).
  ///
  /// Hasil tak wajar dicatat ([pernahDiubah]) sampai kontak server berikutnya.
  /// Jam terbesar hanya dinaikkan oleh jam yang wajar.
  Future<PenilaianJam> periksa() async {
    final now = _sekarang();
    final terpercaya = waktuTerpercaya(_titik, await _uptime.baca());
    if (terpercaya != null) {
      _terpercaya = terpercaya;
      _sejakTerpercaya
        ..reset()
        ..start();
    }
    final hasil = nilaiJam(
      perangkat: now,
      terpercaya: terpercaya,
      terbesar: jamTerbesar,
    );
    if (!hasil.wajar) {
      await _prefs.setBool(_kunciDiubah, true);
      return hasil;
    }
    final terbesar = jamTerbesar;
    if (terbesar == null || now.isAfter(terbesar)) {
      await _tulis(_kunciTerbesar, now);
    }
    return hasil;
  }

  DateTime? get jamTerbesar => _baca(_kunciTerbesar);

  /// Dipanggil setiap ada respons dari server. Jam tablet saat itu dianggap
  /// benar — server sendiri memeriksa jam tablet saat transaksi dikirim.
  Future<void> catatOnline() async {
    final now = _sekarang();
    final lalu = terakhirOnline;
    if (lalu != null &&
        !now.isBefore(lalu) &&
        now.difference(lalu) < jedaCatat) {
      return;
    }
    await _tulis(_kunciOnline, now);
    await _tulis(_kunciTerbesar, now);
  }

  /// `true` bila jam perangkat terdeteksi diubah (mundur ATAU maju).
  Future<bool> amati() async => !(await periksa()).wajar;

  /// Lama tablet tak tersambung ke server. Null bila belum pernah tercatat
  /// (aplikasi baru diperbarui) — tak ada yang bisa dinilai.
  Duration? lamaOffline() {
    final online = terakhirOnline;
    if (online == null) return null;
    // Jam acuan yang tak bisa dimundurkan (termasuk jam terpercaya), supaya
    // memundurkan jam perangkat tak memperpendek hitungan lama offline.
    final lama = waktuAcuan().difference(online);
    return lama.isNegative ? Duration.zero : lama;
  }
}

/// Batas lama offline dari PLATFORM (jam) — tak bisa dilonggarkan Pemilik.
/// Tanpa ini, outlet yang mengisi batasnya 0 ("tanpa batas") bisa memakai
/// aplikasi offline selamanya, termasuk setelah langganannya habis, karena
/// status langganan tak pernah diperbarui.
const batasOfflinePlatformJam = 168; // 7 hari

/// Batas yang benar-benar berlaku: pengaturan Pemilik, tapi tak pernah lebih
/// longgar dari batas platform.
int batasOfflineEfektif(int pengaturanPemilik) =>
    pengaturanPemilik <= 0 || pengaturanPemilik > batasOfflinePlatformJam
    ? batasOfflinePlatformJam
    : pengaturanPemilik;

/// `true` bila tablet sudah lebih lama offline dari batas outlet.
/// [batasJam] 0 = tanpa batas.
bool melewatiBatasOffline(Duration? lama, int batasJam) =>
    batasJam > 0 && lama != null && lama > Duration(hours: batasJam);

/// Pesan untuk kasir saat penjualan offline ditolak karena batas.
String pesanBatasOffline(Duration lama, int batasJam) {
  final jam = lama.inHours;
  final teks = jam >= 48 ? '${jam ~/ 24} hari' : '$jam jam';
  return 'Tablet sudah $teks tidak tersambung ke internet (batas $batasJam '
      'jam). Sambungkan ke internet dulu untuk melanjutkan penjualan — '
      'transaksi yang sudah tersimpan tetap aman.';
}

/// Peringatan sebelum batas offline tercapai, atau null bila belum perlu.
/// Muncul saat sisa waktu ≤ seperempat batas (48 jam → 12 jam terakhir),
/// supaya kasir sempat mencari internet SEBELUM penjualan terhenti di tengah
/// ramai. MURNI.
String? peringatanBatasOffline(Duration? lama, int batasJam) {
  if (batasJam <= 0 || lama == null) return null;
  final batas = Duration(hours: batasJam);
  final sisa = batas - lama;
  if (sisa <= Duration.zero) {
    return 'penjualan offline terkunci — sambungkan internet';
  }
  if (sisa > batas ~/ 4) return null;
  final teks = sisa.inHours >= 1
      ? '${sisa.inHours} jam'
      : '${max(1, sisa.inMinutes)} menit';
  return 'tablet harus online dalam $teks';
}

final jamOfflineProvider = Provider<JamOffline>(
  (ref) => JamOffline(ref.watch(sharedPreferencesProvider)),
);

/// Galat aksi offline (shift, kas, pelunasan) yang ditahan karena jam
/// perangkat diubah. Pesannya siap ditampilkan ke kasir.
class JamPerangkatDiubah implements Exception {
  JamPerangkatDiubah(this.pesan);
  final String pesan;
  @override
  String toString() => pesan;
}

/// Tahan aksi offline bila jam perangkat diubah. Dipanggil sebelum aksi
/// offline apa pun yang mencatat waktu kejadian dari jam perangkat.
Future<void> pastikanJamWajar(JamOffline jam) async {
  final p = await jam.periksa();
  if (!p.wajar) throw JamPerangkatDiubah(pesanJamTidakWajar(p));
}
