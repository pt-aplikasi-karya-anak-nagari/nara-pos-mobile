import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Compress image file di frontend SEBELUM upload ke backend. Tujuan:
///   1. Upload cepat di koneksi cafe yang umumnya lemah / dibatasi.
///   2. Hemat storage server — foto bukti pembayaran / produk seringkali
///      tidak butuh resolusi 4000×3000 px dari kamera HP modern.
///
/// Pendekatan:
///   * Decode pakai package `image` (pure Dart, lintas platform).
///   * Resize ke max [maxDimension] px pada sisi terpanjang (default 1600).
///   * Re-encode JPEG dengan [quality] (default 50 — "compress 50%").
///   * Tulis ke file temp dengan suffix `-compressed.jpg`.
///   * Heavy lifting di-offload ke isolate via `compute()` supaya UI
///     tidak freeze saat memproses gambar besar.
///
/// Skip kompresi (return file asli) bila:
///   * Bukan file image valid (decode gagal)
///   * Ukuran < 200 KB (overhead JPEG header tidak worth)
///   * Hasil kompresi lebih besar dari file asli (jarang, tapi mungkin
///     untuk PNG kecil yang sudah optimal)
class ImageCompress {
  static const int defaultQuality = 50;
  static const int defaultMaxDimension = 1600;

  /// Kompres file di [sourcePath]. Return path file hasil kompresi
  /// (file baru di temp dir) atau path asli kalau skip.
  static Future<String> compressFile(
    String sourcePath, {
    int quality = defaultQuality,
    int maxDimension = defaultMaxDimension,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) return sourcePath;
    final originalSize = await source.length();
    if (originalSize < 200 * 1024) return sourcePath;

    final bytes = await source.readAsBytes();
    final params = _CompressParams(
      bytes: bytes,
      quality: quality,
      maxDimension: maxDimension,
    );
    final result = await compute(_compressIsolate, params);
    if (result == null) return sourcePath; // decode failed
    if (result.length >= originalSize) return sourcePath;

    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final destPath = '${dir.path}/compressed_${ts}_${_baseName(sourcePath)}.jpg';
    final dest = File(destPath);
    await dest.writeAsBytes(result, flush: true);
    return destPath;
  }

  static String _baseName(String path) {
    final last = path.split(Platform.pathSeparator).last;
    final dot = last.lastIndexOf('.');
    return dot > 0 ? last.substring(0, dot) : last;
  }
}

/// Payload untuk isolate. Harus dipisah jadi top-level class supaya
/// bisa di-serialize antar isolate (closure tidak boleh).
class _CompressParams {
  final Uint8List bytes;
  final int quality;
  final int maxDimension;
  const _CompressParams({
    required this.bytes,
    required this.quality,
    required this.maxDimension,
  });
}

/// Function top-level untuk `compute()`. Decode → resize (kalau perlu)
/// → encode JPEG. Return null kalau decode gagal (mis. file rusak).
Uint8List? _compressIsolate(_CompressParams p) {
  final decoded = img.decodeImage(p.bytes);
  if (decoded == null) return null;

  // Resize hanya kalau melewati batas — hemat CPU untuk foto kecil.
  img.Image resized = decoded;
  final longest = decoded.width >= decoded.height ? decoded.width : decoded.height;
  if (longest > p.maxDimension) {
    if (decoded.width >= decoded.height) {
      resized = img.copyResize(
        decoded,
        width: p.maxDimension,
        interpolation: img.Interpolation.cubic,
      );
    } else {
      resized = img.copyResize(
        decoded,
        height: p.maxDimension,
        interpolation: img.Interpolation.cubic,
      );
    }
  }

  final jpg = img.encodeJpg(resized, quality: p.quality);
  return Uint8List.fromList(jpg);
}
