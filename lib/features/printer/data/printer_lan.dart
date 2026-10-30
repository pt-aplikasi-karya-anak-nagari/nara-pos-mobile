import 'dart:async';
import 'dart:io';

/// Printer thermal jaringan (LAN / Wi-Fi) — ESC/POS mentah lewat TCP,
/// umumnya port 9100 ("RAW" / "JetDirect").
///
/// Banyak dapur memakai printer LAN, bukan Bluetooth: jaraknya jauh dari
/// kasir, dan satu printer dipakai beberapa tablet. Printer LAN disimpan di
/// slot printer yang SAMA dengan Bluetooth (`PrinterSettings.deviceMac`)
/// dengan bentuk `tcp:<host>:<port>`, jadi struk, tiket dapur, laporan shift,
/// dan laci kas otomatis ikut memakai transport ini.
class AlamatPrinterLan {
  const AlamatPrinterLan(this.host, this.port);

  final String host;
  final int port;

  static const portBawaan = 9100;
  static const _awalan = 'tcp:';

  /// Bentuk yang disimpan di pengaturan printer.
  String get kunci => '$_awalan$host:$port';

  String get label => port == portBawaan ? host : '$host:$port';

  /// Dari nilai `deviceMac` tersimpan; null bila itu printer Bluetooth.
  static AlamatPrinterLan? dariKunci(String simpanan) {
    if (!simpanan.startsWith(_awalan)) return null;
    return urai(simpanan.substring(_awalan.length));
  }

  /// Dari masukan pengguna: "192.168.1.50", "192.168.1.50:9100", atau nama
  /// host. Null bila tak sah. MURNI.
  static AlamatPrinterLan? urai(String masukan) {
    final s = masukan.trim();
    if (s.isEmpty || s.contains(' ') || s.contains('/')) return null;
    var host = s;
    var port = portBawaan;
    final i = s.lastIndexOf(':');
    if (i >= 0) {
      host = s.substring(0, i);
      final p = int.tryParse(s.substring(i + 1));
      if (p == null || p < 1 || p > 65535) return null;
      port = p;
    }
    if (!_hostSah(host)) return null;
    return AlamatPrinterLan(host, port);
  }

  static bool _hostSah(String h) {
    if (h.isEmpty || h.length > 253) return false;
    final bagian = h.split('.');
    final semuaAngka = bagian.every((b) => int.tryParse(b) != null);
    if (semuaAngka) {
      return bagian.length == 4 &&
          bagian.every((b) {
            final n = int.parse(b);
            return n >= 0 && n <= 255 && b == '$n';
          });
    }
    final label = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$');
    return bagian.every(label.hasMatch);
  }

  @override
  bool operator ==(Object other) =>
      other is AlamatPrinterLan && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

/// Pembuka koneksi — bisa diganti di tes.
typedef PembukaSoket =
    Future<Socket> Function(String host, int port, {Duration? timeout});

/// Kirim byte ESC/POS ke printer LAN. Koneksi dibuka per cetakan lalu
/// ditutup — printer LAN umumnya hanya melayani SATU koneksi, jadi tablet
/// lain bisa mencetak setelahnya. Tak pernah melempar: false bila gagal.
Future<bool> kirimKePrinterLan(
  AlamatPrinterLan a,
  List<int> bytes, {
  Duration batasWaktu = const Duration(seconds: 5),
  PembukaSoket buka = Socket.connect,
}) async {
  Socket? s;
  try {
    s = await buka(a.host, a.port, timeout: batasWaktu);
    s.add(bytes);
    await s.flush().timeout(batasWaktu);
    return true;
  } catch (_) {
    return false;
  } finally {
    try {
      await s?.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
    s?.destroy();
  }
}

/// Apakah printer LAN bisa dihubungi (tanpa mencetak apa pun).
Future<bool> cekPrinterLan(
  AlamatPrinterLan a, {
  Duration batasWaktu = const Duration(seconds: 3),
  PembukaSoket buka = Socket.connect,
}) async {
  try {
    final s = await buka(a.host, a.port, timeout: batasWaktu);
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}
