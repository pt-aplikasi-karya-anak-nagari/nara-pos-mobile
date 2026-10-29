import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app/theme.dart';
import '../../core/connectivity_service.dart';

/// Tolak aksi yang harus dicatat server SAAT ITU JUGA bila perangkat offline,
/// dengan pesan yang jelas — bukan galat jaringan setelah menunggu.
///
/// Dipakai untuk refund, void, pelunasan, pindah meja, dan sejenisnya. Aksi
/// semacam ini sengaja TIDAK diantrekan: dua tablet bisa me-void atau melunasi
/// tagihan yang sama saat offline, uang laci ikut berubah, dan bentroknya baru
/// ketahuan setelah sinkron — saat uangnya sudah berpindah tangan.
///
/// Mengembalikan true (dan memberi tahu kasir) bila aksinya ditolak.
bool tolakSaatOffline(BuildContext context, WidgetRef ref, String aksi) {
  if (!ref.read(isOfflineProvider)) return false;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        '$aksi butuh koneksi internet supaya langsung tercatat di server. '
        'Coba lagi setelah online.',
      ),
      backgroundColor: kWarning,
    ),
  );
  return true;
}
