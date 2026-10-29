import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/user/data/auth_api_service.dart';
import '../shared_prefs.dart';

/// Ganti kasir saat tablet OFFLINE.
///
/// # MASALAHNYA
///
/// Sesi staf wajib diverifikasi server. Saat pergantian shift tanpa internet,
/// kasir berikutnya terpaksa berjualan atas nama kasir sebelumnya — tanggung
/// jawab kas tercampur.
///
/// # CARANYA
///
/// Selagi online, tablet menyimpan daftar staf outlet beserta:
///  - **sidik kartu login** dari server (logincard.VerifierOffline). Token
///    kartu 256 bit acak, jadi sidiknya aman disimpan: tak bisa ditebak balik;
///  - **sidik PIN** (PBKDF2) — hanya untuk staf yang PERNAH masuk online
///    dengan PIN di tablet ini. Server sendiri hanya menyimpan bcrypt PIN,
///    jadi sidik ini lahir di tablet saat PIN itu diterima server.
///
/// Saat offline, kartu yang discan / PIN yang diketik dicocokkan dengan sidik
/// itu. PIN salah 5 kali mengunci staf tersebut, makin lama makin panjang.
///
/// Sesi yang dibuka begini adalah **sesi offline**: semua permintaan ke server
/// ditahan (lihat dio_client), transaksinya diberi penanda `sesi_offline`, dan
/// begitu internet kembali staf wajib verifikasi ulang ke server sebelum apa
/// pun terkirim atas namanya.
///
/// # BATAS YANG DIKETAHUI
///
/// PIN pendek: orang yang membongkar tablet (root) dan mengambil sidiknya bisa
/// menebak PIN di luar aplikasi, PBKDF2 hanya memperlambat. Karena itu fitur
/// ini bisa dimatikan Pemilik per outlet, dan sesi offline tetap diverifikasi
/// ulang server.

/// Sidik kartu login untuk dicocokkan offline — sama persis dengan
/// logincard.VerifierOffline(logincard.HashToken(token)) di server.
String sidikKartu(String token) {
  final hash = sha256.convert(utf8.encode(token.trim())).toString();
  return sha256.convert(utf8.encode('np-kartu-offline:$hash')).toString();
}

/// PBKDF2-HMAC-SHA256.
Uint8List pbkdf2(
  List<int> sandi,
  List<int> garam,
  int iterasi, [
  int panjang = 32,
]) {
  final hmac = Hmac(sha256, sandi);
  final keluar = BytesBuilder();
  var blok = 1;
  while (keluar.length < panjang) {
    var u = hmac.convert([
      ...garam,
      (blok >> 24) & 0xff,
      (blok >> 16) & 0xff,
      (blok >> 8) & 0xff,
      blok & 0xff,
    ]).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iterasi; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    keluar.add(t);
    blok++;
  }
  return Uint8List.fromList(keluar.toBytes().sublist(0, panjang));
}

/// Sidik PIN satu staf.
class SidikPin {
  const SidikPin({
    required this.garam,
    required this.hash,
    required this.iterasi,
  });

  final String garam; // base64
  final String hash; // base64
  final int iterasi;

  static const iterasiAsal = 60000;

  /// Buat sidik dari PIN yang baru saja diterima server. Dijalankan di
  /// isolate terpisah — PBKDF2 sengaja lambat, layar tak boleh ikut macet.
  static Future<SidikPin> buat(
    String pin, {
    int iterasi = iterasiAsal,
    Random? acak,
  }) async {
    final r = acak ?? Random.secure();
    final garam = List<int>.generate(16, (_) => r.nextInt(256));
    final hash = await Isolate.run(
      () => pbkdf2(utf8.encode(pin), garam, iterasi),
    );
    return SidikPin(
      garam: base64Encode(garam),
      hash: base64Encode(hash),
      iterasi: iterasi,
    );
  }

  Future<bool> cocok(String pin) async {
    final garamB = base64Decode(garam);
    final n = iterasi;
    final hasil = await Isolate.run(() => pbkdf2(utf8.encode(pin), garamB, n));
    final harap = base64Decode(hash);
    if (hasil.length != harap.length) return false;
    var beda = 0;
    for (var i = 0; i < hasil.length; i++) {
      beda |= hasil[i] ^ harap[i];
    }
    return beda == 0;
  }

  Map<String, dynamic> toJson() => {
    'garam': garam,
    'hash': hash,
    'iterasi': iterasi,
  };

  static SidikPin? fromJson(Object? j) {
    if (j is! Map) return null;
    final g = j['garam'], h = j['hash'], n = j['iterasi'];
    if (g is! String || h is! String || n is! int) return null;
    return SidikPin(garam: g, hash: h, iterasi: n);
  }
}

/// Staf outlet yang tersimpan untuk masuk offline.
class KasirTersimpan {
  const KasirTersimpan({
    required this.id,
    required this.nama,
    required this.role,
    this.kartu = const [],
    this.pin,
  });

  final String id;
  final String nama;
  final String role;
  final List<String> kartu;
  final SidikPin? pin;

  KasirTersimpan denganPin(SidikPin? p) =>
      KasirTersimpan(id: id, nama: nama, role: role, kartu: kartu, pin: p);

  Map<String, dynamic> toJson() => {
    'id': id,
    'nama': nama,
    'role': role,
    'kartu': kartu,
    if (pin != null) 'pin': pin!.toJson(),
  };

  factory KasirTersimpan.fromJson(Map<String, dynamic> j) => KasirTersimpan(
    id: j['id']?.toString() ?? '',
    nama: j['nama']?.toString() ?? '',
    role: j['role']?.toString() ?? '',
    kartu: [for (final k in (j['kartu'] as List? ?? const [])) k.toString()],
    pin: SidikPin.fromJson(j['pin']),
  );
}

/// Gabungkan daftar staf terbaru dari server dengan sidik PIN yang sudah
/// tersimpan. Staf yang tak lagi ada di daftar server (dinonaktifkan,
/// dipindah) ikut hilang — beserta sidik PIN-nya. MURNI.
List<KasirTersimpan> gabungDaftarStaf(
  List<StaffCandidate> server,
  List<KasirTersimpan> lama,
) {
  final pinLama = {for (final k in lama) k.id: k.pin};
  return [
    for (final s in server)
      KasirTersimpan(
        id: s.id,
        nama: s.fullName,
        role: s.role,
        kartu: s.kartuOffline,
        pin: pinLama[s.id],
      ),
  ];
}

/// Status kunci PIN satu staf.
class KunciPin {
  const KunciPin({this.gagal = 0, this.ronde = 0, this.sampai});

  final int gagal;
  final int ronde; // berapa kali sudah terkunci — durasinya berlipat
  final DateTime? sampai;

  static const batasGagal = 5;
  static const durasiAwal = Duration(minutes: 5);

  bool terkunci(DateTime kini) => sampai != null && kini.isBefore(sampai!);

  /// PIN salah sekali lagi. Ke-5 berturut-turut → terkunci 5, 10, 20… menit.
  KunciPin salah(DateTime kini) {
    final g = gagal + 1;
    if (g < batasGagal) return KunciPin(gagal: g, ronde: ronde, sampai: sampai);
    final lama = durasiAwal * (1 << min(ronde, 6));
    return KunciPin(gagal: 0, ronde: ronde + 1, sampai: kini.add(lama));
  }

  Map<String, dynamic> toJson() => {
    'gagal': gagal,
    'ronde': ronde,
    if (sampai != null) 'sampai': sampai!.toIso8601String(),
  };

  factory KunciPin.fromJson(Map<String, dynamic> j) => KunciPin(
    gagal: j['gagal'] as int? ?? 0,
    ronde: j['ronde'] as int? ?? 0,
    sampai: DateTime.tryParse(j['sampai']?.toString() ?? ''),
  );
}

sealed class HasilPinOffline {
  const HasilPinOffline();
}

class PinBenar extends HasilPinOffline {
  const PinBenar(this.kasir);
  final KasirTersimpan kasir;
}

class PinSalah extends HasilPinOffline {
  const PinSalah(this.sisa);
  final int sisa;
}

class PinTerkunci extends HasilPinOffline {
  const PinTerkunci(this.sampai);
  final DateTime sampai;
}

/// Staf belum pernah masuk online dengan PIN di tablet ini.
class PinBelumTersimpan extends HasilPinOffline {
  const PinBelumTersimpan();
}

class SesiOfflineStore {
  SesiOfflineStore(
    this._prefs, {
    FlutterSecureStorage? secure,
    DateTime Function()? kini,
  }) : _secure = secure ?? const FlutterSecureStorage(),
       _kini = kini ?? DateTime.now;

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  final DateTime Function() _kini;

  static String _kunciDaftar(String outletId) => 'sesi_offline.staf.$outletId';
  static String _kunciPin(String outletId, String staffId) =>
      'sesi_offline.kunci.$outletId.$staffId';

  Future<List<KasirTersimpan>> daftar(String outletId) async {
    try {
      final raw = await _secure.read(key: _kunciDaftar(outletId));
      if (raw == null) return const [];
      return [
        for (final j in jsonDecode(raw) as List)
          KasirTersimpan.fromJson(Map<String, dynamic>.from(j as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _tulis(String outletId, List<KasirTersimpan> d) => _secure.write(
    key: _kunciDaftar(outletId),
    value: jsonEncode([for (final k in d) k.toJson()]),
  );

  /// Simpan daftar staf terbaru dari server (setiap layar pilih staf terbuka
  /// online).
  Future<void> simpanDaftar(
    String outletId,
    List<StaffCandidate> server,
  ) async {
    if (outletId.isEmpty) return;
    await _tulis(outletId, gabungDaftarStaf(server, await daftar(outletId)));
  }

  /// PIN [pin] baru saja diterima server untuk [staffId]: simpan sidiknya.
  Future<void> simpanPin(String outletId, String staffId, String pin) async {
    final d = await daftar(outletId);
    if (!d.any((k) => k.id == staffId)) return;
    final sidik = await SidikPin.buat(pin);
    await _tulis(outletId, [
      for (final k in d) k.id == staffId ? k.denganPin(sidik) : k,
    ]);
    await _prefs.remove(_kunciPin(outletId, staffId));
  }

  /// Kartu yang discan → staf pemiliknya, atau null.
  Future<KasirTersimpan?> masukKartu(String outletId, String token) async {
    final s = sidikKartu(token);
    for (final k in await daftar(outletId)) {
      if (k.kartu.contains(s)) return k;
    }
    return null;
  }

  KunciPin _bacaKunci(String outletId, String staffId) {
    try {
      final raw = _prefs.getString(_kunciPin(outletId, staffId));
      if (raw == null) return const KunciPin();
      return KunciPin.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const KunciPin();
    }
  }

  Future<HasilPinOffline> masukPin(
    String outletId,
    String staffId,
    String pin,
  ) async {
    final kasir = (await daftar(
      outletId,
    )).where((k) => k.id == staffId).firstOrNull;
    if (kasir == null || kasir.pin == null) return const PinBelumTersimpan();
    final kini = _kini();
    final kunci = _bacaKunci(outletId, staffId);
    if (kunci.terkunci(kini)) return PinTerkunci(kunci.sampai!);
    if (await kasir.pin!.cocok(pin)) {
      await _prefs.remove(_kunciPin(outletId, staffId));
      return PinBenar(kasir);
    }
    final baru = kunci.salah(kini);
    await _prefs.setString(
      _kunciPin(outletId, staffId),
      jsonEncode(baru.toJson()),
    );
    if (baru.terkunci(kini)) return PinTerkunci(baru.sampai!);
    return PinSalah(KunciPin.batasGagal - baru.gagal);
  }
}

final sesiOfflineStoreProvider = Provider<SesiOfflineStore>(
  (ref) => SesiOfflineStore(ref.watch(sharedPreferencesProvider)),
);
