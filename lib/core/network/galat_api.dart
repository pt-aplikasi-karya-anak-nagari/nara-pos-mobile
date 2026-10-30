/// Galat API yang membawa kode mesin dari server (`code` di respons), mis.
/// `perlu_pin_stok` atau `aturan_absen`. `toString()` tetap pesan untuk
/// pengguna — pemanggil lama yang menampilkan `'$e'` tak berubah perilakunya.
class GalatApi implements Exception {
  const GalatApi(this.kode, this.pesan);

  final String kode;
  final String pesan;

  @override
  String toString() => pesan;
}

/// Kode galat [e] bila ia [GalatApi], selain itu null.
String? kodeGalat(Object? e) => e is GalatApi ? e.kode : null;
