/// Kalimat yang diucapkan saat nomor antrian dipanggil. MURNI — disamakan
/// dengan `susunPanggilan` di web (nara-pos-web/lib/antrian.ts).
///
/// Pemilik mengatur kalimatnya di Pengaturan App (antrian_teks_panggilan),
/// dengan penanda:
///   {nomor} — nomor antrian, dieja per karakter ("nol, nol, tujuh") seperti
///             loket antrian, supaya tak salah dengar di ruangan ramai;
///   {nama}  — nama pelanggan;
///   {meja}  — nama/nomor meja.
/// Bagian dalam kurung siku dilewati bila penanda di dalamnya kosong:
/// "Nomor {nomor}[ atas nama {nama}]." → "Nomor nol, nol, tujuh." untuk
/// pelanggan tanpa nama.
library;

/// Kalimat bawaan — sama dengan entity.TeksPanggilanBawaan di server.
const teksPanggilanBawaan = 'Nomor antrian {nomor}. Silakan menuju kasir.';

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

/// Susun kalimat dari [template] Pemilik.
String susunPanggilan(
  String template,
  String nomor, {
  String nama = '',
  String meja = '',
  bool ulang = false,
}) {
  final t = template.trim().isEmpty ? teksPanggilanBawaan : template;
  final nilai = <String, String>{
    'nomor': ejaNomor(nomor),
    'nama': nama.trim(),
    'meja': meja.trim(),
  };
  String isi(String s) =>
      s.replaceAllMapped(RegExp(r'\{(nomor|nama|meja)\}'), (m) => nilai[m[1]]!);
  // Bagian opsional [ … ]: dibuang bila ada penanda kosong di dalamnya.
  var hasil = t.replaceAllMapped(RegExp(r'\[([^\[\]]*)\]'), (m) {
    final dalam = m[1]!;
    final kosong = RegExp(
      r'\{(nomor|nama|meja)\}',
    ).allMatches(dalam).any((x) => nilai[x[1]]!.isEmpty);
    return kosong ? '' : isi(dalam);
  });
  hasil = isi(hasil);
  // Rapikan sisa penanda kosong di luar kurung: spasi ganda & spasi sebelum
  // tanda baca.
  hasil = hasil
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAllMapped(RegExp(r'\s+([.,!?])'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'([.,!?])\1+'), (m) => m[1]!)
      .trim();
  return ulang ? 'Panggilan ulang. $hasil' : hasil;
}

/// Kalimat dengan teks bawaan (dipakai bila pengaturan belum termuat).
String kalimatPanggilan(String nomor, {bool ulang = false}) =>
    susunPanggilan(teksPanggilanBawaan, nomor, ulang: ulang);
