import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'auth_storage.dart';

/// Masa berlaku sesi login tanpa diperbarui — sama dengan RefreshTokenTTL di
/// server (nara-pos-be/internal/utils/security.go). Ubah keduanya bersamaan.
///
/// # KENAPA PERLU DIPERHATIKAN SAAT OFFLINE
///
/// Selama online, sesi diperbarui otomatis setiap token akses habis, jadi tak
/// pernah benar-benar berakhir. Tablet yang offline tak bisa memperbaruinya.
/// Lewat 7 hari, begitu internet kembali server menolak sesinya: kasir harus
/// login ulang — yang butuh Pemilik untuk mengotorisasi — sebelum transaksi
/// offline bisa terkirim. Kasir perlu tahu ini SEBELUM terjadi.
const masaBerlakuSesi = Duration(days: 7);

/// Peringatan mulai muncul saat sisa sesi kurang dari ini.
const ambangPeringatanSesi = Duration(days: 2);

/// Sisa masa sesi; null bila tak diketahui (belum pernah tercatat).
Duration? sisaSesi(DateTime? diperbaruiPada, DateTime kini) {
  if (diperbaruiPada == null) return null;
  return diperbaruiPada.add(masaBerlakuSesi).difference(kini);
}

/// Teks peringatan sesi untuk banner offline, atau null bila belum perlu.
String? peringatanSesi(Duration? sisa) {
  if (sisa == null || sisa > ambangPeringatanSesi) return null;
  if (sisa <= Duration.zero) {
    return 'sesi login sudah berakhir — transaksi tetap tersimpan, '
        'login ulang saat online untuk mengirimnya';
  }
  final waktu = sisa.inHours >= 24
      ? '${sisa.inDays} hari'
      : sisa.inHours >= 1
      ? '${sisa.inHours} jam'
      : '${sisa.inMinutes.clamp(1, 59)} menit';
  return 'sambungkan internet dalam $waktu agar tak perlu login ulang';
}

/// Detak per menit — supaya peringatan sesi ikut bergerak walau tak ada hal
/// lain yang membuat banner dibangun ulang (tablet bisa offline berhari-hari).
final detakMenitProvider = StreamProvider<DateTime>(
  (ref) => Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now()),
);

/// Peringatan sesi saat ini (null = tak perlu).
final peringatanSesiProvider = Provider<String?>((ref) {
  final kini = ref.watch(detakMenitProvider).value ?? DateTime.now();
  final storage = ref.watch(authStorageProvider);
  if ((storage.refreshToken ?? '').isEmpty) return null;
  return peringatanSesi(sisaSesi(storage.sesiDiperbaruiPada, kini));
});
