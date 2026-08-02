import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Izin sistem yang WAJIB diberikan sebelum aplikasi bisa dipakai.
///
/// Ketiganya menyentuh pekerjaan inti kasir, dan tak satu pun punya jalan
/// memutar di dalam aplikasi:
///
///   perangkatSekitar  tanpa ini struk tak bisa dicetak. Pelanggan menunggu di
///                     depan kasir yang tak punya apa pun untuk diserahkan.
///   kamera            tanpa ini barcode harus diketik manual satu per satu.
///   notifikasi        tanpa ini pesanan dari QR meja masuk diam-diam. Makanan
///                     tak pernah dibuat, dan tak ada yang tahu sampai
///                     pelanggan datang bertanya.
///
/// # YANG SENGAJA TIDAK MASUK DAFTAR INI
///
/// GALERI FOTO. Sejak Android 13 image_picker memakai Photo Picker sistem yang
/// TIDAK butuh izin apa pun — Permission.photos di sana selalu berakhir
/// ditolak. Memasukkannya ke daftar wajib akan mengunci setiap perangkat
/// Android modern di gerbang izin selamanya, tanpa cara keluar.
///
/// LOKASI. Bukan izin tersendiri di sini: ia hanya jalan cadangan Bluetooth
/// untuk Android 11 ke bawah, dan diurus di dalam [IzinAplikasi.perangkatSekitar].
enum IzinAplikasi { perangkatSekitar, kamera, notifikasi }

extension IzinAplikasiInfo on IzinAplikasi {
  String get judul => switch (this) {
    IzinAplikasi.perangkatSekitar => 'Perangkat Sekitar',
    IzinAplikasi.kamera => 'Kamera',
    IzinAplikasi.notifikasi => 'Notifikasi',
  };

  String get alasan => switch (this) {
    IzinAplikasi.perangkatSekitar =>
      'Menyambung ke printer struk Bluetooth di kasir.',
    IzinAplikasi.kamera => 'Memindai barcode produk saat transaksi.',
    IzinAplikasi.notifikasi =>
      'Memberi tahu kasir saat ada pesanan baru dari QR meja.',
  };
}

/// Hasil pemeriksaan satu izin.
enum StatusIzin {
  diberikan,

  /// Ditolak, tapi masih bisa diminta lagi lewat dialog sistem.
  ditolak,

  /// Ditolak permanen ("Jangan tanya lagi") atau dikunci kebijakan perangkat.
  /// Dialog sistem TIDAK akan muncul lagi — satu-satunya jalan adalah halaman
  /// Pengaturan aplikasi.
  ditolakPermanen,
}

/// Izin sistem: Bluetooth/perangkat sekitar, kamera, notifikasi.
class SystemPermissionService {
  SystemPermissionService({DeviceInfoPlugin? deviceInfo})
    : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfo;
  int? _sdkAndroid;

  /// Versi SDK Android perangkat ini, di-cache karena tak pernah berubah.
  ///
  /// # KENAPA TIDAK DITEBAK DARI STATUS IZIN
  ///
  /// Versi sebelumnya menebak begini: "kalau bluetoothScan ATAU
  /// bluetoothConnect sudah diberikan, berarti Android 12+". Pada pemasangan
  /// BARU — satu-satunya keadaan yang penting untuk gerbang izin — belum ada
  /// satu pun yang diberikan, jadi tebakannya selalu jatuh ke cabang Android
  /// 11, lalu meminta izin lokasi yang di Android 12+ memang tak akan pernah
  /// menghasilkan akses Bluetooth. Gerbangnya akan menolak untuk selamanya
  /// tepat pada perangkat yang paling umum dipakai.
  Future<int> _sdk() async {
    if (!Platform.isAndroid) return 0;
    return _sdkAndroid ??= (await _deviceInfo.androidInfo).version.sdkInt;
  }

  Future<List<Permission>> _petakan(IzinAplikasi izin) async => petakanIzin(
    izin: izin,
    android: Platform.isAndroid,
    ios: Platform.isIOS,
    sdkAndroid: await _sdk(),
  );

  Future<StatusIzin> status(IzinAplikasi izin) async {
    final daftar = await _petakan(izin);
    if (daftar.isEmpty) return StatusIzin.diberikan;
    return rangkumStatus(await Future.wait(daftar.map((p) => p.status)));
  }

  /// Munculkan dialog sistem untuk [izin], kembalikan hasil akhirnya.
  Future<StatusIzin> minta(IzinAplikasi izin) async {
    final daftar = await _petakan(izin);
    if (daftar.isEmpty) return StatusIzin.diberikan;
    final hasil = await daftar.request();
    return rangkumStatus(
      daftar.map((p) => hasil[p] ?? PermissionStatus.denied),
    );
  }

  Future<Map<IzinAplikasi, StatusIzin>> periksaSemua() async {
    final hasil = <IzinAplikasi, StatusIzin>{};
    for (final izin in IzinAplikasi.values) {
      hasil[izin] = await status(izin);
    }
    return hasil;
  }

  Future<bool> get semuaDiberikan async =>
      (await periksaSemua()).values.every((s) => s == StatusIzin.diberikan);

  /// Buka halaman Pengaturan aplikasi — satu-satunya jalan keluar dari
  /// [StatusIzin.ditolakPermanen].
  Future<void> bukaPengaturan() => openAppSettings();

  // ── Kompatibilitas jalur printer yang sudah ada ──────────────────────────
  // printer_service & printer_settings_page memanggil dua nama ini. Keduanya
  // kini memakai pemetaan berbasis versi di atas, bukan tebakan lama.

  Future<bool> get isNearbyDevicesGranted async =>
      await status(IzinAplikasi.perangkatSekitar) == StatusIzin.diberikan;

  Future<bool> requestNearbyDevices() async =>
      await minta(IzinAplikasi.perangkatSekitar) == StatusIzin.diberikan;

  Future<void> openSettings() => bukaPengaturan();
}

final systemPermissionServiceProvider = Provider<SystemPermissionService>(
  (ref) => SystemPermissionService(),
);

/// Izin permission_handler yang mewakili [izin] pada sebuah perangkat.
///
/// Fungsi MURNI — tak menyentuh Platform maupun plugin apa pun, supaya
/// pemetaannya bisa diuji untuk tiap versi Android tanpa perangkat.
///
/// # DUA CABANG YANG MENENTUKAN
///
/// Android 12 (SDK 31) mengganti seluruh model izin Bluetooth: BLUETOOTH +
/// BLUETOOTH_ADMIN + izin lokasi digantikan BLUETOOTH_SCAN dan
/// BLUETOOTH_CONNECT. Meminta yang salah untuk versi yang salah selalu
/// berakhir ditolak permanen — izin itu memang tak ada di OS tersebut, dan
/// dialognya tak pernah muncul.
///
/// Platform selain Android & iOS tidak punya izin runtime sama sekali. Di
/// lingkungan tes, memanggil permission_handler di sana melempar
/// MissingPluginException, dan gerbang izin akan menutup aplikasi karena
/// kesalahan yang tak ada hubungannya dengan izin apa pun.
List<Permission> petakanIzin({
  required IzinAplikasi izin,
  required bool android,
  required bool ios,
  required int sdkAndroid,
}) {
  if (!android && !ios) return const [];
  switch (izin) {
    case IzinAplikasi.perangkatSekitar:
      if (ios) return [Permission.bluetooth];
      return sdkAndroid >= 31
          ? [Permission.bluetoothScan, Permission.bluetoothConnect]
          : [Permission.location];
    case IzinAplikasi.kamera:
      return [Permission.camera];
    case IzinAplikasi.notifikasi:
      return [Permission.notification];
  }
}

/// Satu status ringkas dari beberapa izin yang mewakili satu [IzinAplikasi].
///
/// Kosong = izin ini tak berlaku di perangkat tersebut, jadi dianggap sudah
/// diberikan; kalau tidak, gerbang izin akan menahan selamanya sesuatu yang
/// memang tak bisa diminta.
StatusIzin rangkumStatus(Iterable<PermissionStatus> semua) {
  if (semua.isEmpty) return StatusIzin.diberikan;
  // limited/provisional (iOS) tetap dihitung diberikan: aksesnya ada.
  if (semua.every((s) => s.isGranted || s.isLimited || s.isProvisional)) {
    return StatusIzin.diberikan;
  }
  if (semua.any((s) => s.isPermanentlyDenied || s.isRestricted)) {
    return StatusIzin.ditolakPermanen;
  }
  return StatusIzin.ditolak;
}
