import 'package:image_cropper/image_cropper.dart';

/// Wrapper tipis di atas `image_cropper` plugin. Memanggil native crop UI
/// (UCrop di Android, TOCropViewController di iOS) untuk meng-crop foto
/// SEBELUM upload ke backend.
///
/// Default aspect ratio 1:1 — sesuai permintaan project: semua gambar
/// yang masuk ke server (bukti pembayaran, produk, absensi, dll)
/// dipangkas jadi kotak supaya:
///   * Konsisten di UI grid (galeri produk, riwayat)
///   * Mudah di-thumbnail tanpa cropping ulang di server
///   * Storage backend tidak nyimpen foto extra-tall yang banyak
///     bagian tidak relevan
///
/// Return path file hasil crop atau `null` kalau user batal.
class ImageCrop {
  /// Crop foto ke aspect ratio 1:1 (kotak).
  ///
  /// [sourcePath] — path file gambar asli (mis. dari ImagePicker).
  /// [title] — judul yang muncul di toolbar native UI. Default
  ///           "Sesuaikan gambar".
  static Future<String?> square(
    String sourcePath, {
    String title = 'Sesuaikan gambar',
  }) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: title,
          // Lock aspect ratio supaya user tidak tidak sengaja ganti
          // ke aspect lain — semua harus 1:1.
          lockAspectRatio: true,
          hideBottomControls: true,
        ),
        IOSUiSettings(
          title: title,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
        ),
      ],
    );
    return cropped?.path;
  }
}
