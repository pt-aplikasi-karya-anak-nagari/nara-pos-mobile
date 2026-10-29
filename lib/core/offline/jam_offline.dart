import 'dart:math';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared_prefs.dart';

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
  JamOffline(this._prefs, {DateTime Function()? sekarang})
    : _sekarang = sekarang ?? DateTime.now;

  static const _kunciOnline = 'offline.jam.terakhir_online';
  static const _kunciTerbesar = 'offline.jam.terbesar';

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

  /// Periksa jam sekarang. `true` bila jam tablet dimundurkan dibanding jam
  /// terbesar yang pernah terlihat. Jam terbesar hanya pernah naik.
  Future<bool> amati() async {
    final now = _sekarang();
    final terbesar = jamTerbesar;
    if (terbesar != null && now.isBefore(terbesar.subtract(toleransiMundur))) {
      return true;
    }
    if (terbesar == null || now.isAfter(terbesar)) {
      await _tulis(_kunciTerbesar, now);
    }
    return false;
  }

  /// Lama tablet tak tersambung ke server. Null bila belum pernah tercatat
  /// (aplikasi baru diperbarui) — tak ada yang bisa dinilai.
  Duration? lamaOffline() {
    final online = terakhirOnline;
    if (online == null) return null;
    final now = _sekarang();
    final terbesar = jamTerbesar;
    final acuan = terbesar != null && terbesar.isAfter(now) ? terbesar : now;
    final lama = acuan.difference(online);
    return lama.isNegative ? Duration.zero : lama;
  }
}

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
