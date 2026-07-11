import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../app/theme.dart';
import 'network/dio_client.dart';

/// Thumbnail produk yang menampilkan gambar real dari `imageUrl` (dapat
/// berupa path relatif `/uploads/...` atau URL absolut). Bila kosong/error,
/// menampilkan badge inisial dua huruf pertama dari `name` di atas warna
/// pastel yang stabil per-nama.
class ProductImage extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;
  final double radius;
  final bool fill;

  const ProductImage({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 48,
    this.radius = 12,
    this.fill = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasUrl = imageUrl != null && imageUrl!.trim().isNotEmpty;
    final w = fill ? double.infinity : size;
    final h = fill ? double.infinity : size;

    Widget content;
    if (hasUrl) {
      content = CachedNetworkImage(
        imageUrl: resolveAssetUrl(imageUrl),
        width: w,
        height: h,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, _) => Skeletonizer(
          enabled: true,
          child: Bone(width: w, height: h, borderRadius: BorderRadius.zero),
        ),
        errorWidget: (_, _, _) =>
            _InitialsBadge(name: name, size: size, fill: fill),
      );
    } else {
      content = _InitialsBadge(name: name, size: size, fill: fill);
    }

    if (radius == 0) return content;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: content,
    );
  }
}

/// Badge inisial 2 huruf — fallback saat `imageUrl` kosong / gagal load.
class _InitialsBadge extends StatelessWidget {
  final String name;
  final double size;
  final bool fill;
  const _InitialsBadge({
    required this.name,
    required this.size,
    required this.fill,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _initialsFromName(name);

    final fg = Colors.white;
    final w = fill ? double.infinity : size;
    final h = fill ? double.infinity : size;

    return Container(
      width: w,
      height: h,
      color: kPrimary.withValues(alpha: 0.9),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            initials,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.42,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Ambil 2 huruf depan dari nama. Kalau ada spasi, ambil huruf pertama
/// dari 2 kata pertama (mis. "Es Teh" → "ET"). Kalau 1 kata, ambil 2 huruf
/// pertama (mis. "Kopi" → "KO").
String _initialsFromName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    final first = parts[0].isNotEmpty ? parts[0][0] : '';
    final second = parts[1].isNotEmpty ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }
  return trimmed.length >= 2
      ? trimmed.substring(0, 2).toUpperCase()
      : trimmed.toUpperCase();
}

/// Warna stabil untuk satu nama produk, supaya badge inisial tidak berubah
/// tiap rebuild. Pakai palet POS yang sudah ada agar konsisten dengan tema.
