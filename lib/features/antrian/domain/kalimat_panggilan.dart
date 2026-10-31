/// Kalimat yang diucapkan saat nomor antrian dipanggil. MURNI — dipakai juga
/// oleh tes, dan disamakan dengan `kalimatPanggilan` di web
/// (nara-pos-web/lib/antrian.ts).
///
/// Nomor dieja per karakter ("nol, nol, tujuh") — cara loket antrian di
/// Indonesia memanggil — supaya tak salah dengar di ruangan yang ramai.
/// Huruf pada nomor offline ("3FA-007") dieja sebagai huruf.
library;

const _angka = [
  'nol',
  'satu',
  'dua',
  'tiga',
  'empat',
  'lima',
  'enam',
  'tujuh',
  'delapan',
  'sembilan',
];

/// Eja [nomor] per karakter: "007" → "nol, nol, tujuh"; "3FA-012" →
/// "tiga, F, A, nol, satu, dua". Tanda pemisah diabaikan.
String ejaNomor(String nomor) {
  final bagian = <String>[];
  for (final c in nomor.trim().toUpperCase().split('')) {
    final d = int.tryParse(c);
    if (d != null) {
      bagian.add(_angka[d]);
    } else if (RegExp(r'[A-Z]').hasMatch(c)) {
      bagian.add(c);
    }
  }
  return bagian.join(', ');
}

/// Kalimat panggilan lengkap, mis. "Nomor antrian, nol, nol, tujuh. Silakan
/// menuju kasir." — [tujuan] bisa diganti ("mengambil pesanan di kasir").
String kalimatPanggilan(
  String nomor, {
  String tujuan = 'menuju kasir',
  bool ulang = false,
}) {
  final awal = ulang ? 'Panggilan ulang. Nomor antrian' : 'Nomor antrian';
  return '$awal, ${ejaNomor(nomor)}. Silakan $tujuan.';
}
