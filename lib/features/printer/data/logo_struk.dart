import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../../core/network/dio_client.dart';

/// Logo di kepala struk = logo yang diunggah Pemilik di Pengaturan Struk
/// (`header_logo_url`).
///
/// Dulu printer selalu mencetak logo Flutter bawaan — logo Pemilik tak pernah
/// diunduh. Kini logonya diunduh, disimpan di perangkat per outlet (struk
/// tetap berlogo saat offline), lalu disiapkan untuk printer thermal.

/// Lebar logo (titik printer) per ukuran kertas. Kertas 58 mm = 384 titik,
/// 80 mm = 576 titik; logo dibuat ±60% lebar supaya tak mendominasi struk.
int lebarLogoUntuk(PaperSize kertas) => kertas == PaperSize.mm80 ? 320 : 240;

/// Siapkan gambar logo untuk printer thermal (hitam-putih):
///  - bagian transparan jadi PUTIH — tanpa ini PNG transparan tercetak hitam
///    pekat, karena printer membaca piksel transparan sebagai gelap;
///  - diperkecil ke [lebarMaks] (tak pernah diperbesar), tinggi dibatasi
///    sama supaya logo tegak tak memanjangkan struk;
///  - grayscale.
/// Null bila bukan gambar yang bisa dibaca.
img.Image? siapkanLogoStruk(Uint8List bytes, {required int lebarMaks}) {
  img.Image? asli;
  try {
    asli = img.decodeImage(bytes);
  } catch (_) {
    return null; // bukan gambar yang dikenali
  }
  if (asli == null || asli.width == 0 || asli.height == 0) return null;

  final putih = img.Image(width: asli.width, height: asli.height);
  img.fill(putih, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(putih, asli);

  var hasil = putih;
  final skala = [
    lebarMaks / hasil.width,
    lebarMaks / hasil.height,
    1.0,
  ].reduce((a, b) => a < b ? a : b);
  if (skala < 1) {
    hasil = img.copyResize(
      hasil,
      width: (hasil.width * skala).round().clamp(1, lebarMaks),
      height: (hasil.height * skala).round().clamp(1, lebarMaks),
      interpolation: img.Interpolation.average,
    );
  }
  return img.grayscale(hasil);
}

/// Simpanan logo struk di perangkat, per outlet.
class LogoStrukStore {
  LogoStrukStore({required this.unduh, Future<Directory> Function()? folder})
    : _folder = folder ?? _folderAsal;

  /// Mengunduh bytes logo dari URL-nya (path relatif server).
  final Future<Uint8List> Function(String url) unduh;
  final Future<Directory> Function() _folder;

  static Future<Directory> _folderAsal() async {
    final dasar = await getApplicationSupportDirectory();
    return Directory('${dasar.path}/logo_struk');
  }

  Future<File> _berkas(String outletId, String akhiran) async {
    final dir = await _folder();
    if (!await dir.exists()) await dir.create(recursive: true);
    final aman = outletId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}/$aman.$akhiran');
  }

  /// Bytes logo untuk [url]. Diunduh bila belum tersimpan atau logonya
  /// diganti. Gagal mengunduh (offline) → logo terakhir yang tersimpan,
  /// walau dari URL lama: logo lama lebih baik daripada struk tanpa logo.
  /// [url] kosong = Pemilik menghapus logonya → simpanan ikut dihapus.
  Future<Uint8List?> ambil(String outletId, String? url) async {
    final data = await _berkas(outletId, 'img');
    final meta = await _berkas(outletId, 'json');
    final u = url?.trim() ?? '';
    if (u.isEmpty) {
      for (final f in [data, meta]) {
        if (await f.exists()) await f.delete();
      }
      return null;
    }
    String? urlTersimpan;
    if (await meta.exists()) {
      try {
        urlTersimpan =
            (jsonDecode(await meta.readAsString()) as Map)['url'] as String?;
      } catch (_) {}
    }
    if (urlTersimpan == u && await data.exists()) {
      return data.readAsBytes();
    }
    try {
      final bytes = await unduh(u);
      if (img.decodeImage(bytes) == null) throw const FormatException();
      await data.writeAsBytes(bytes, flush: true);
      await meta.writeAsString(jsonEncode({'url': u}), flush: true);
      return bytes;
    } catch (_) {
      return await data.exists() ? data.readAsBytes() : null;
    }
  }
}

final logoStrukStoreProvider = Provider<LogoStrukStore>((ref) {
  return LogoStrukStore(
    unduh: (url) async {
      final res = await ref
          .read(dioProvider)
          .get<List<int>>(
            resolveAssetUrl(url),
            options: Options(
              responseType: ResponseType.bytes,
              // Kegagalan unduh logo tak perlu toast: struk tetap tercetak.
              extra: {'senyap': true},
            ),
          );
      return Uint8List.fromList(res.data ?? const []);
    },
  );
});
