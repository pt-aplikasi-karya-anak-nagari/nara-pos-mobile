import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/format.dart';
import 'riwayat_kalkulator.dart';

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
class DialogKalkulator extends ConsumerStatefulWidget {
  const DialogKalkulator({super.key});

  @override
  ConsumerState<DialogKalkulator> createState() => _DialogKalkulatorState();
}

class _DialogKalkulatorState extends ConsumerState<DialogKalkulator> {
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
    // Ekspresi disusun SEBELUM state diubah — sesudahnya _tertunda dan
    // _operator sudah kosong, dan riwayatnya jadi "= 45000" tanpa asal-usul.
    final ekspresi =
        '${_format(_tertunda!)} $_operator ${_format(_nilaiTampil)}';
    final hasil = _format(_hitung(_tertunda!, _nilaiTampil, _operator!));
    ref.read(riwayatKalkulatorProvider.notifier).tambah(ekspresi, hasil);
    setState(() {
      _tampil = hasil;
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
    final riwayat = ref.watch(riwayatKalkulatorProvider);

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: LayoutBuilder(
        builder: (context, batas) {
          // Riwayat di KIRI hanya bila ada ruangnya. Di layar sempit,
          // memaksakan dua kolom membuat tombol jadi terlalu kecil untuk
          // ditekan jari — dan kalkulator yang salah tekan lebih buruk
          // daripada kalkulator tanpa riwayat. Di sana riwayatnya pindah ke
          // ATAS keypad dengan tinggi terbatas.
          final lebarTersedia = MediaQuery.sizeOf(context).width - 40;
          final muatDuaKolom = lebarTersedia >= 620;

          final papan = _papanTombol();
          final panel = _PanelRiwayat(
            riwayat: riwayat,
            onPakai: _pakaiDariRiwayat,
            onBersihkan: () =>
                ref.read(riwayatKalkulatorProvider.notifier).bersihkan(),
          );

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: muatDuaKolom ? 660 : 380,
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
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
                  if (muatDuaKolom)
                    // IntrinsicHeight supaya panel riwayat setinggi keypad —
                    // tanpa itu kolom kiri mengerut mengikuti isinya dan
                    // daftar kosongnya tampak seperti tampilan rusak.
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 240, child: panel),
                          const SizedBox(width: 16),
                          Expanded(child: papan),
                        ],
                      ),
                    )
                  else ...[
                    SizedBox(height: 150, child: panel),
                    const SizedBox(height: 12),
                    Flexible(child: SingleChildScrollView(child: papan)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Muat hasil dari riwayat ke layar untuk dipakai lagi.
  void _pakaiDariRiwayat(String hasil) {
    setState(() {
      _tampil = hasil;
      // mulaiBaru: digit berikutnya MENGGANTI angka ini, bukan menempel di
      // belakangnya — kasir yang mengetuk riwayat lalu mengetik angka baru
      // sedang memulai hitungan baru, bukan menyambung yang lama.
      _mulaiBaru = true;
    });
  }

  Widget _papanTombol() {
    const tombol = <List<String>>[
      ['C', '⌫', '%', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '−'],
      ['1', '2', '3', '+'],
      ['00', '0', '.', '='],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Layar. Baris atas menampilkan EKSPRESI yang sedang disusun, bukan
        // hanya operand tertunda — kasir yang terganggu di tengah hitungan
        // bisa melihat lagi apa yang sedang ia kerjakan.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                height: 16,
                child: _operator != null && _tertunda != null
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          key: const ValueKey('kalkulator-ekspresi'),
                          '${_format(_tertunda!)} $_operator'
                          '${_mulaiBaru ? '' : ' $_tampil'}',
                          style: TextStyle(fontSize: 12, color: kTextMid),
                        ),
                      )
                    : null,
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
        TextButton.icon(
          key: const ValueKey('kalkulator-salin'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _tampil));
            if (!mounted) return;
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

/// Panel riwayat — daftar perhitungan yang sudah selesai.
///
/// # KENAPA TIAP BARIS BISA DIKETUK
///
/// Riwayat yang hanya bisa dibaca memaksa kasir mengetik ulang angka yang
/// sudah ada di layar, dan mengetik ulang adalah tempat salah ketik terjadi.
/// Mengetuk satu baris memuat hasilnya kembali ke layar, siap dipakai untuk
/// hitungan berikutnya.
class _PanelRiwayat extends StatelessWidget {
  const _PanelRiwayat({
    required this.riwayat,
    required this.onPakai,
    required this.onBersihkan,
  });

  final List<BarisRiwayat> riwayat;
  final void Function(String hasil) onPakai;
  final VoidCallback onBersihkan;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
            child: Row(
              children: [
                Text(
                  'Riwayat',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: kTextMid,
                  ),
                ),
                const Spacer(),
                if (riwayat.isNotEmpty)
                  TextButton(
                    key: const ValueKey('kalkulator-riwayat-bersihkan'),
                    onPressed: onBersihkan,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      foregroundColor: kTextMid,
                    ),
                    child: const Text(
                      'Bersihkan',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: riwayat.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Belum ada perhitungan.\nHasil yang kamu tekan "=" muncul di sini.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: kTextLight,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: riwayat.length,
                    itemBuilder: (_, i) {
                      final r = riwayat[i];
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: ValueKey('kalkulator-riwayat-$i'),
                          onTap: () => onPakai(r.hasil),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 7,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  r.ekspresi,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: kTextMid,
                                  ),
                                ),
                                Text(
                                  r.hasil,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: kTextDark,
                                  ),
                                ),
                                Text(
                                  formatRupiah(double.tryParse(r.hasil) ?? 0),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: kPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
