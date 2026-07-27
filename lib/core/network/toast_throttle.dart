/// Peredam toast berulang.
///
/// MASALAH YANG DISELESAIKAN
///
/// Halaman kasir mem-polling beberapa endpoint (kategori, produk, shift aktif,
/// konfigurasi printer) tiap beberapa detik. Kalau ada SATU kondisi yang bikin
/// semuanya gagal — langganan outlet habis, outlet di-suspend, izin kurang —
/// tiap putaran polling melahirkan 3-4 toast sekaligus. Dalam belasan detik
/// layar tertutup tumpukan toast merah yang isinya sama persis.
///
/// Menampilkan pesan yang sama berkali-kali tidak menambah informasi apa pun;
/// yang pertama sudah menyampaikan seluruhnya.
///
/// DUA JEDA, KARENA ADA DUA JENIS KEGAGALAN
///
///   - Kegagalan sesaat (validasi gagal, server error) — cukup diredam selama
///     toast sebelumnya masih terlihat, supaya percobaan berikutnya yang
///     benar-benar baru tetap terlihat.
///   - Kondisi menetap (langganan habis, outlet di-suspend) — tidak berubah
///     hanya karena ditunggu. Mengulanginya tiap polling murni kebisingan, jadi
///     jedanya jauh lebih panjang.
class ToastThrottle {
  /// Jeda untuk kegagalan biasa. Sedikit lebih panjang dari durasi tampil toast
  /// (4 detik) supaya beberapa request paralel yang gagal bersamaan hanya
  /// memunculkan satu toast.
  final Duration jedaUmum;

  /// Jeda untuk kondisi yang tidak berubah dengan menunggu.
  final Duration jedaKondisiMenetap;

  final Map<String, DateTime> _terakhir = {};

  ToastThrottle({
    this.jedaUmum = const Duration(seconds: 8),
    this.jedaKondisiMenetap = const Duration(minutes: 5),
  });

  /// Apakah [pesan] boleh ditampilkan sekarang. Memanggil ini MENCATAT waktu
  /// tampil, jadi panggil sekali per calon toast.
  ///
  /// [sekarang] hanya untuk pengujian; kosongkan di kode produksi.
  bool boleh(String pesan, {bool kondisiMenetap = false, DateTime? sekarang}) {
    final kini = sekarang ?? DateTime.now();
    final jeda = kondisiMenetap ? jedaKondisiMenetap : jedaUmum;

    final sebelumnya = _terakhir[pesan];
    if (sebelumnya != null && kini.difference(sebelumnya) < jeda) {
      return false;
    }

    _terakhir[pesan] = kini;
    // Buang catatan yang sudah lewat jeda terpanjang supaya map tidak tumbuh
    // seumur aplikasi hanya karena pesan error yang selalu berbeda.
    _terakhir.removeWhere(
      (_, waktu) => kini.difference(waktu) > jedaKondisiMenetap,
    );
    return true;
  }

  /// Lupakan seluruh catatan — dipakai saat ganti sesi/pengguna supaya kondisi
  /// milik sesi sebelumnya tidak membungkam toast sesi baru.
  void reset() => _terakhir.clear();
}

/// Kode error backend untuk kondisi yang tidak berubah dengan menunggu.
const _kodeKondisiMenetap = {
  'subscription_expired',
  'subscription_grace_period',
  'feature_not_in_plan',
  'outlet_suspended',
  'permission_denied',
};

/// Apakah respons error ini mewakili kondisi menetap (langganan/izin), bukan
/// kegagalan sesaat.
bool kondisiMenetapDariRespons(int? statusCode, Object? data) {
  if (statusCode != 402 && statusCode != 403) return false;
  if (data is Map) {
    final kode = data['code'];
    if (kode is String) return _kodeKondisiMenetap.contains(kode);
  }
  // 402 selalu soal langganan di API ini, apa pun bentuk body-nya.
  return statusCode == 402;
}
