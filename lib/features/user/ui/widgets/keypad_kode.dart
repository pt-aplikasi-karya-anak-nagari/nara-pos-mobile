import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Papan angka untuk memasukkan PIN staf atau kode email 6 digit.
///
/// # KENAPA BUKAN PAPAN KETIK BAWAAN
///
/// Perangkat kasir dipakai berdiri, sering dengan sarung tangan atau tangan
/// basah, dan papan ketik OS memakan separuh layar lalu menutup daftar staf
/// yang baru saja dipilih. Tombol besar yang selalu di tempat yang sama bisa
/// ditekan tanpa melihat — dan kasir yang antre di belakangnya tidak menunggu.
///
/// # PANJANGNYA TIDAK TETAP, DAN ITU JEBAKANNYA
///
/// PIN staf 4-6 digit (server: "PIN harus 4-6 digit angka"), sedangkan kode
/// email persis 6. Keypad yang mengirim otomatis begitu 6 titik penuh akan
/// membuat PIN 4 digit TIDAK PERNAH bisa dikirim — karyawannya terkunci di
/// luar aplikasi, tanpa satu pun pesan galat yang menjelaskan kenapa.
///
/// Karena itu kirim-otomatis hanya terjadi di [maksimal] digit, tempat tak ada
/// lagi digit yang mungkin diketik; untuk PIN yang lebih pendek, tombol kirim
/// di bawahnya tetap satu-satunya jalan, dan tombol itu wajib tetap ada.
class KeypadKode extends StatelessWidget {
  const KeypadKode({
    super.key,
    required this.nilai,
    required this.onBerubah,
    this.onPenuh,
    this.aktif = true,
    this.maksimal = 6,
  });

  /// Isi saat ini. Widget ini tidak menyimpan state sendiri supaya nilainya
  /// tetap satu sumber dengan controller yang dipakai saat verifikasi.
  final String nilai;

  final ValueChanged<String> onBerubah;

  /// Dipanggil saat digit ke-[maksimal] baru saja ditekan. Boleh null bila
  /// pemanggilnya ingin selalu menunggu tombol kirim.
  final VoidCallback? onPenuh;

  /// false saat sedang memverifikasi — tanpa ini ketukan kedua mengirim
  /// permintaan kedua dan menghabiskan percobaan yang sama dua kali.
  final bool aktif;

  final int maksimal;

  void _tekanAngka(String d) {
    if (nilai.length >= maksimal) return;
    final baru = nilai + d;
    onBerubah(baru);
    if (baru.length == maksimal) onPenuh?.call();
  }

  void _hapus() {
    if (nilai.isEmpty) return;
    onBerubah(nilai.substring(0, nilai.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    const baris = <List<String>>[
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', '⌫'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TitikKode(terisi: nilai.length, total: maksimal),
        const SizedBox(height: 22),
        for (final r in baris)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                for (final t in r)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: _Tombol(
                        label: t,
                        aktif: aktif,
                        onTekan: () {
                          if (t == 'C') {
                            onBerubah('');
                          } else if (t == '⌫') {
                            _hapus();
                          } else {
                            _tekanAngka(t);
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Titik-titik yang terisi mengikuti jumlah digit.
///
/// Kenapa titik, bukan angkanya: perangkat kasir menghadap ke pelanggan, dan
/// PIN staf juga dipakai mengesahkan void/refund. Menampilkannya terbaca
/// berarti siapa pun yang berdiri di depan konter ikut menghafalnya.
class _TitikKode extends StatelessWidget {
  const _TitikKode({required this.terisi, required this.total});

  final int terisi;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: AnimatedContainer(
              key: ValueKey('keypad-titik-$i'),
              duration: const Duration(milliseconds: 120),
              width: i < terisi ? 14 : 12,
              height: i < terisi ? 14 : 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < terisi
                    ? kPrimary
                    : kTextLight.withValues(alpha: 0.3),
              ),
            ),
          ),
      ],
    );
  }
}

class _Tombol extends StatelessWidget {
  const _Tombol({
    required this.label,
    required this.aktif,
    required this.onTekan,
  });

  final String label;
  final bool aktif;
  final VoidCallback onTekan;

  @override
  Widget build(BuildContext context) {
    final angka = label != 'C' && label != '⌫';
    return SizedBox(
      // Tinggi TETAP, bukan Expanded. Keypad ini hidup di dalam halaman login
      // yang bisa digulir, jadi tingginya tak terbatas — dan widget yang
      // meminta sisa ruang di ruang tak terbatas gagal saat layout.
      height: 56,
      child: Material(
        color: angka ? kBg : kTextLight.withValues(alpha: aktif ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey('keypad-$label'),
          onTap: aktif ? onTekan : null,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: label == '⌫'
                ? Icon(
                    Icons.backspace_outlined,
                    size: 20,
                    color: aktif ? kTextDark : kTextLight,
                  )
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: angka ? 22 : 18,
                      fontWeight: FontWeight.w600,
                      color: aktif ? kTextDark : kTextLight,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
