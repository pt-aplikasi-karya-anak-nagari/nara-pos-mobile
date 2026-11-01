import 'package:flutter/services.dart';

/// Jam terpercaya untuk mode offline — jam yang TIDAK ikut berubah ketika
/// pengguna mengubah tanggal & jam perangkat.
///
/// # MASALAHNYA
///
/// Saat offline, satu-satunya jam yang dimiliki aplikasi adalah jam
/// perangkat, dan jam itu bisa diubah siapa saja di Pengaturan:
///
///   dimundurkan  memindah penjualan ke shift/hari lain, memperpanjang masa
///                langganan dan batas lama offline;
///   dimajukan    memindah penjualan ke hari berikutnya, mengacaukan urutan.
///
/// Penjagaan lama hanya mengingat jam terbesar yang pernah terlihat — itu
/// menangkap jam yang dimundurkan, tapi tidak yang dimajukan, dan tidak bila
/// jam sudah salah sejak sebelum tablet offline.
///
/// # CARANYA
///
/// Setiap kali tersambung, aplikasi mencatat [TitikJam]: jam SERVER saat itu
/// dan uptime sistem (milidetik sejak perangkat dinyalakan — terus berjalan
/// saat layar mati, dan tak bisa diubah pengguna). Kemudian, selama perangkat
/// belum dinyalakan ulang:
///
///   jam terpercaya = jam server di titik itu + (uptime sekarang − uptime titik)
///
/// Selisih jam perangkat terhadap jam terpercaya itulah yang dinilai. Setelah
/// perangkat dinyalakan ulang (atau di platform tanpa uptime), jam terpercaya
/// tak diketahui dan penilaian jatuh ke penjagaan lama: jam terbesar.
class TitikJam {
  final DateTime server;
  final int uptimeMs;
  final int? boot;
  const TitikJam({required this.server, required this.uptimeMs, this.boot});

  Map<String, dynamic> toJson() => {
    'server': server.millisecondsSinceEpoch,
    'uptime_ms': uptimeMs,
    'boot': boot,
  };

  static TitikJam? dariJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final s = j['server'], u = j['uptime_ms'];
    if (s is! int || u is! int) return null;
    return TitikJam(
      server: DateTime.fromMillisecondsSinceEpoch(s),
      uptimeMs: u,
      boot: j['boot'] as int?,
    );
  }
}

/// Bacaan jam sistem saat ini.
typedef BacaanUptime = ({int uptimeMs, int? boot});

/// Jam terpercaya sekarang, atau null bila tak bisa dihitung (belum ada
/// titik, platform tanpa uptime, atau perangkat sudah dinyalakan ulang).
DateTime? waktuTerpercaya(TitikJam? titik, BacaanUptime? kini) {
  if (titik == null || kini == null) return null;
  // Nyala ulang: uptime mulai dari nol lagi. Dengan BOOT_COUNT dikenali
  // langsung; tanpanya, uptime yang lebih kecil adalah tandanya.
  if (titik.boot != null && kini.boot != null && titik.boot != kini.boot) {
    return null;
  }
  if (kini.uptimeMs < titik.uptimeMs) return null;
  return titik.server.add(
    Duration(milliseconds: kini.uptimeMs - titik.uptimeMs),
  );
}

enum StatusJam { wajar, dimundurkan, dimajukan }

/// Hasil penilaian jam perangkat.
class PenilaianJam {
  final StatusJam status;

  /// Jam perangkat − jam acuan (negatif = dimundurkan). Nol bila wajar atau
  /// tak bisa dihitung.
  final Duration selisih;

  /// Jam yang seharusnya (terpercaya), bila diketahui — untuk ditunjukkan ke
  /// kasir agar ia bisa membetulkan jam perangkatnya.
  final DateTime? seharusnya;

  const PenilaianJam(
    this.status, {
    this.selisih = Duration.zero,
    this.seharusnya,
  });

  bool get wajar => status == StatusJam.wajar;
}

/// Toleransi: jam perangkat yang disetel otomatis tak pernah persis sama
/// dengan server, dan header Date server hanya beresolusi detik. Sama dengan
/// toleransi server (offlinecheck.ToleransiJam).
const toleransiJam = Duration(minutes: 10);

/// Nilai jam perangkat. MURNI.
///
/// [terpercaya] tersedia → selisih ke arah mana pun di luar toleransi
/// dianggap diubah. Tidak tersedia → hanya jam yang mundur dari [terbesar]
/// (jam terbesar yang pernah terlihat) yang bisa dikenali.
PenilaianJam nilaiJam({
  required DateTime perangkat,
  DateTime? terpercaya,
  DateTime? terbesar,
  Duration toleransi = toleransiJam,
}) {
  if (terpercaya != null) {
    final selisih = perangkat.difference(terpercaya);
    if (selisih > toleransi) {
      return PenilaianJam(
        StatusJam.dimajukan,
        selisih: selisih,
        seharusnya: terpercaya,
      );
    }
    if (selisih < -toleransi) {
      return PenilaianJam(
        StatusJam.dimundurkan,
        selisih: selisih,
        seharusnya: terpercaya,
      );
    }
    return const PenilaianJam(StatusJam.wajar);
  }
  if (terbesar != null && perangkat.isBefore(terbesar.subtract(toleransi))) {
    return PenilaianJam(
      StatusJam.dimundurkan,
      selisih: perangkat.difference(terbesar),
    );
  }
  return const PenilaianJam(StatusJam.wajar);
}

/// "2 jam 15 menit" / "3 hari" — untuk pesan ke kasir.
String teksDurasi(Duration d) {
  final a = d.abs();
  if (a.inDays >= 1) {
    final jam = a.inHours % 24;
    return '${a.inDays} hari${jam > 0 ? ' $jam jam' : ''}';
  }
  if (a.inHours >= 1) {
    final menit = a.inMinutes % 60;
    return '${a.inHours} jam${menit > 0 ? ' $menit menit' : ''}';
  }
  return '${a.inMinutes} menit';
}

/// Pesan untuk kasir saat aksi offline ditahan karena jam perangkat diubah.
String pesanJamTidakWajar(PenilaianJam p) {
  final arah = p.status == StatusJam.dimajukan ? 'dimajukan' : 'dimundurkan';
  final s = p.seharusnya?.toLocal();
  final seharusnya = s == null
      ? ''
      : ' Jam sekarang seharusnya sekitar '
            '${s.hour.toString().padLeft(2, '0')}.${s.minute.toString().padLeft(2, '0')}.';
  return 'Jam perangkat terdeteksi $arah ${teksDurasi(p.selisih)}.$seharusnya '
      'Nyalakan "Tanggal & waktu otomatis" di Pengaturan perangkat atau '
      'betulkan jamnya, lalu coba lagi — transaksi offline ditahan supaya '
      'tak tercatat di waktu yang salah.';
}

/// Sumber uptime sistem. Android lewat kanal native (JamSistemChannel.kt);
/// platform lain / galat → null, dan penilaian jatuh ke penjagaan lama.
class SumberUptime {
  static const _channel = MethodChannel('nara/jam_sistem');

  Future<BacaanUptime?> baca() async {
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>('baca');
      final u = r?['uptime_ms'];
      if (u is! int) return null;
      return (uptimeMs: u, boot: r?['boot'] as int?);
    } catch (_) {
      return null; // MissingPluginException (iOS/tes), PlatformException
    }
  }
}
