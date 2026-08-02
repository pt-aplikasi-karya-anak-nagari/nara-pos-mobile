import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme.dart';
import '../../../../core/format.dart';

/// Kalkulator kasir — dialog cepat untuk hitungan di depan pelanggan.
///
/// # KENAPA BUKAN MEMANGGIL KALKULATOR BAWAAN
///
/// Membuka aplikasi lain berarti aplikasi kasir masuk background. Di sana
/// cetak-otomatis berhenti (printer Bluetooth butuh main isolate), dan kasir
/// yang lupa kembali menemukan pesanan menumpuk tanpa struk. Hitungan cepat
/// tak sepadan dengan itu.
///
/// # KENAPA DESIMALNYA DIBATASI DUA
///
/// Rupiah tak punya pecahan yang dipakai, tapi pembagian menghasilkannya:
/// 10.000 ÷ 3 = 3333,333… Membiarkannya panjang membuat angka di layar tak
/// bisa dibacakan ke pelanggan. Dibulatkan dua desimal, dan bila hasilnya
/// bulat, koma-nya dibuang.
class DialogKalkulator extends StatefulWidget {
  const DialogKalkulator({super.key});

  @override
  State<DialogKalkulator> createState() => _DialogKalkulatorState();
}

class _DialogKalkulatorState extends State<DialogKalkulator> {
  String _tampil = '0';

  /// Nilai yang sudah "dikunci" oleh operator sebelumnya, dan operatornya.
  double? _tertunda;
  String? _operator;

  /// true tepat setelah operator/sama-dengan ditekan: digit berikutnya
  /// MEMULAI angka baru alih-alih menempel ke hasil.
  bool _mulaiBaru = true;

  double get _nilaiTampil => double.tryParse(_tampil) ?? 0;

  void _ketikDigit(String d) {
    setState(() {
      if (_mulaiBaru) {
        _tampil = d == '.' ? '0.' : d;
        _mulaiBaru = false;
        return;
      }
      if (d == '.') {
        if (_tampil.contains('.')) return; // satu koma saja
        _tampil += '.';
        return;
      }
      // "0" tunggal diganti, bukan ditempeli — kalau tidak, mengetik 5
      // menghasilkan "05".
      _tampil = _tampil == '0' ? d : _tampil + d;
    });
  }

  void _pilihOperator(String op) {
    setState(() {
      // Operator berturut-turut hanya MENGGANTI operatornya. Menghitung di
      // sini akan memakai operand yang sama dua kali: 8 × ÷ 2 jadi 32, bukan 4.
      if (_operator != null && _mulaiBaru) {
        _operator = op;
        return;
      }
      if (_tertunda != null && _operator != null) {
        final hasil = _hitung(_tertunda!, _nilaiTampil, _operator!);
        _tampil = _format(hasil);
        _tertunda = hasil;
      } else {
        _tertunda = _nilaiTampil;
      }
      _operator = op;
      _mulaiBaru = true;
    });
  }

  void _samaDengan() {
    if (_tertunda == null || _operator == null) return;
    setState(() {
      _tampil = _format(_hitung(_tertunda!, _nilaiTampil, _operator!));
      _tertunda = null;
      _operator = null;
      _mulaiBaru = true;
    });
  }

  double _hitung(double a, double b, String op) {
    switch (op) {
      case '+':
        return a + b;
      case '−':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        // Pembagian nol dibiarkan menghasilkan Infinity di sini; _format yang
        // menahannya sebelum sampai ke layar. Penjaga kedua di baris ini
        // pernah ada dan terbukti TAK BISA DIAMATI dari luar — suntikan yang
        // mencabutnya tidak memerahkan satu tes pun. Penjaga yang tak bisa
        // diuji hanya membuat pembaca berikutnya mengira ada dua perlindungan
        // padahal yang bekerja cuma satu.
        return a / b;
      default:
        return b;
    }
  }

  /// Dua desimal, dan koma dibuang bila hasilnya bulat.
  ///
  /// SATU-SATUNYA yang menahan Infinity/NaN sampai ke layar. Dart tak
  /// menganggap pembagian nol sebagai galat — ia mengembalikan Infinity, dan
  /// tanpa baris ini layar menampilkan "Infinity" lalu kalkulatornya buntu
  /// sampai ditekan C.
  String _format(double v) {
    if (v.isNaN || v.isInfinite) return '0';
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  void _bersih() {
    setState(() {
      _tampil = '0';
      _tertunda = null;
      _operator = null;
      _mulaiBaru = true;
    });
  }

  void _hapusSatu() {
    setState(() {
      if (_mulaiBaru || _tampil.length <= 1) {
        _tampil = '0';
        _mulaiBaru = true;
        return;
      }
      _tampil = _tampil.substring(0, _tampil.length - 1);
      if (_tampil == '-' || _tampil.isEmpty) _tampil = '0';
    });
  }

  @override
  Widget build(BuildContext context) {
    final tombol = <List<String>>[
      ['C', '⌫', '%', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '−'],
      ['1', '2', '3', '+'],
      ['00', '0', '.', '='],
    ];

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Kalkulator',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: kTextDark,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const ValueKey('kalkulator-tutup'),
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),

              // Layar. Angkanya juga ditulis dalam rupiah supaya kasir bisa
              // langsung membacakannya ke pelanggan tanpa menghitung nol.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: kBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_operator != null && _tertunda != null)
                      Text(
                        '${_format(_tertunda!)} $_operator',
                        style: TextStyle(fontSize: 12, color: kTextMid),
                      ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        key: const ValueKey('kalkulator-layar'),
                        _tampil,
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: kTextDark,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatRupiah(_nilaiTampil),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: kPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              for (final baris in tombol)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      for (final t in baris) ...[
                        Expanded(
                          child: _Tombol(teks: t, onTap: () => _tekan(t)),
                        ),
                        if (t != baris.last) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),

              // Salin — hitungan yang tak bisa dipindahkan ke nota harus
              // diketik ulang, dan itulah tempat salah ketik terjadi.
              TextButton.icon(
                key: const ValueKey('kalkulator-salin'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _tampil));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$_tampil disalin'),
                      backgroundColor: kSuccess,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Salin hasil'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _tekan(String t) {
    switch (t) {
      case 'C':
        _bersih();
      case '⌫':
        _hapusSatu();
      case '%':
        // Persen di kalkulator kasir = "berapa persen dari angka sebelumnya",
        // bukan sekadar bagi 100. Diskon 10% dari 50.000 diketik 50000 − 10 %
        // dan menghasilkan 5.000 untuk dikurangkan — bukan 0,1.
        setState(() {
          final dasar = _tertunda;
          _tampil = _format(
            dasar == null ? _nilaiTampil / 100 : dasar * _nilaiTampil / 100,
          );
          _mulaiBaru = true;
        });
      case '=':
        _samaDengan();
      case '+':
      case '−':
      case '×':
      case '÷':
        _pilihOperator(t);
      default:
        _ketikDigit(t);
    }
  }
}

class _Tombol extends StatelessWidget {
  final String teks;
  final VoidCallback onTap;
  const _Tombol({required this.teks, required this.onTap});

  bool get _operator => const ['÷', '×', '−', '+', '='].contains(teks);
  bool get _fungsi => const ['C', '⌫', '%'].contains(teks);

  @override
  Widget build(BuildContext context) {
    final latar = teks == '='
        ? kPrimary
        : _operator
        ? kPrimary.withValues(alpha: 0.1)
        : _fungsi
        ? kDivider.withValues(alpha: 0.5)
        : kBg;
    final warna = teks == '='
        ? Colors.white
        : _operator
        ? kPrimary
        : kTextDark;

    return Material(
      color: latar,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('kalkulator-$teks'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 52,
          child: Center(
            child: Text(
              teks,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: warna,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
