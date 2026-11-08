import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app/theme.dart';
import 'buka_url.dart';

/// Paksa update aplikasi kasir.
///
/// Aplikasi mengirim nomor build-nya (angka setelah `+` di `pubspec.yaml`)
/// di header `X-App-Build`. Server yang dikonfigurasi `MOBILE_MIN_BUILD`
/// menolak build lebih tua dengan HTTP 426 + kode [kodePerluUpdate]; app lalu
/// menampilkan [LayarPerbaruiApp] di atas semua halaman. Antrian transaksi
/// offline TIDAK dibuang — penolakan 426 diperlakukan seperti offline
/// (lihat dio_client) dan terkirim setelah update.
class VersiApp {
  VersiApp._();

  /// Nomor build aplikasi yang sedang berjalan. 0 bila belum/ gagal dibaca.
  static int build = 0;

  /// Versi tampilan, mis. `1.0.0`.
  static String nama = '';

  /// Baca versi dari platform. Panggil sekali di `main()` sebelum `runApp`.
  static Future<void> muat() async {
    try {
      final info = await PackageInfo.fromPlatform();
      build = int.tryParse(info.buildNumber) ?? 0;
      nama = info.version;
    } catch (e) {
      debugPrint('[NARA] gagal membaca versi aplikasi: $e');
    }
  }
}

/// Kode galat server untuk build di bawah minimum.
const kodePerluUpdate = 'APP_PERLU_UPDATE';

/// Alamat update bawaan bila server tidak mengirimkannya.
const urlUpdateBawaan =
    'https://play.google.com/store/apps/details?id=id.nara.pos';

@immutable
class InfoPerluUpdate {
  final int minBuild;
  final String updateUrl;
  final String pesan;

  const InfoPerluUpdate({
    required this.minBuild,
    required this.updateUrl,
    required this.pesan,
  });
}

class PerluUpdateNotifier extends Notifier<InfoPerluUpdate?> {
  @override
  InfoPerluUpdate? build() => null;

  void tandai(InfoPerluUpdate info) {
    if (state == null) state = info;
  }
}

/// null = aplikasi boleh dipakai; terisi = wajib update.
final perluUpdateProvider =
    NotifierProvider<PerluUpdateNotifier, InfoPerluUpdate?>(
      PerluUpdateNotifier.new,
    );

const _pesanBawaan =
    'Versi aplikasi kasir ini sudah tidak didukung. Perbarui aplikasi untuk '
    'melanjutkan.';

/// Ambil info update dari respons galat 426 server; null bila bukan.
InfoPerluUpdate? infoDariRespons(Response<dynamic>? res) {
  if (res == null || res.statusCode != 426) return null;
  final body = res.data;
  if (body is! Map || body['code'] != kodePerluUpdate) return null;
  final data = body['data'];
  final peta = data is Map ? data : const {};
  final url = peta['update_url'];
  return InfoPerluUpdate(
    minBuild: (peta['min_build'] as num?)?.toInt() ?? 0,
    updateUrl: url is String && url.isNotEmpty ? url : urlUpdateBawaan,
    pesan: (body['message'] as String?) ?? _pesanBawaan,
  );
}

/// Cek batas build saat app dibuka (sebelum login pun) — tanpa menunggu ada
/// permintaan yang ditolak. Gagal (offline) diabaikan: kasir tetap bisa jualan
/// offline, dan penegakan sesungguhnya ada di server.
Future<void> cekVersiSaatMulai(Dio dio, PerluUpdateNotifier notifier) async {
  if (VersiApp.build <= 0) return;
  try {
    final res = await dio.get<dynamic>('/mobile/versi');
    final body = res.data;
    final data = body is Map ? body['data'] : null;
    if (data is! Map) return;
    final min = (data['min_build'] as num?)?.toInt() ?? 0;
    if (min > VersiApp.build) {
      final url = data['update_url'];
      notifier.tandai(
        InfoPerluUpdate(
          minBuild: min,
          updateUrl: url is String && url.isNotEmpty ? url : urlUpdateBawaan,
          pesan: _pesanBawaan,
        ),
      );
    }
  } catch (_) {
    // Offline / server lama tanpa endpoint ini — abaikan.
  }
}

/// Layar penuh "Perbarui aplikasi" — menutup semua halaman sampai update.
class LayarPerbaruiApp extends ConsumerWidget {
  final InfoPerluUpdate info;
  const LayarPerbaruiApp({super.key, required this.info});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      key: const ValueKey('layar-perbarui-app'),
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.system_update_rounded,
                      size: 36,
                      color: kPrimary,
                    ),
                  ),
                  const Gap(20),
                  Text(
                    'Perbarui aplikasi',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: kTextDark,
                    ),
                  ),
                  const Gap(10),
                  Text(
                    info.pesan,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.5, color: kTextMid),
                  ),
                  const Gap(16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kDivider),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified_user_outlined, color: kSuccess),
                        const Gap(10),
                        Expanded(
                          child: Text(
                            'Transaksi yang tersimpan di perangkat ini tetap aman '
                            'dan terkirim otomatis setelah aplikasi diperbarui.',
                            style: TextStyle(fontSize: 13, color: kTextDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('tombol-perbarui-app'),
                      onPressed: () => bukaDiBrowser(
                        context,
                        ref,
                        info.updateUrl,
                        pesanGagal: 'Buka ${info.updateUrl} untuk memperbarui.',
                      ),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Perbarui sekarang'),
                    ),
                  ),
                  const Gap(12),
                  Text(
                    'Versi terpasang ${VersiApp.nama.isEmpty ? '-' : VersiApp.nama} '
                    '(build ${VersiApp.build})',
                    style: TextStyle(fontSize: 12, color: kTextMid),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
