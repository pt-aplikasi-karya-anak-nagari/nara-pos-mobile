import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Pembuka URL di browser — provider supaya tes bisa menggantinya tanpa
/// benar-benar membuka browser.
final pembukaUrlProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Buka [url] di browser. Gagal (tak ada browser / ditolak) → tampilkan
/// alamatnya di snackbar supaya bisa diketik manual.
Future<void> bukaDiBrowser(
  BuildContext context,
  WidgetRef ref,
  String url, {
  String? pesanGagal,
}) async {
  var berhasil = false;
  try {
    berhasil = await ref.read(pembukaUrlProvider)(Uri.parse(url));
  } catch (_) {
    berhasil = false;
  }
  if (!berhasil && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(pesanGagal ?? 'Buka $url di browser.')),
    );
  }
}
