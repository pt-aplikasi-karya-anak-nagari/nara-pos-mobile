import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/user/ui/widgets/keypad_kode.dart';

// Papan angka PIN staf.
//
// # APA YANG SEBENARNYA DIPERTARUHKAN
//
// Ini satu-satunya pintu masuk perangkat kasir. Keypad yang salah tidak
// menampilkan galat — ia membuat orang yang PIN-nya benar tetap tak bisa
// masuk, di tengah antrean, tanpa petunjuk apa pun tentang sebabnya.
//
// Jebakan utamanya panjang yang TIDAK tetap: PIN staf 4-6 digit (server:
// "PIN harus 4-6 digit angka"), kode email persis 6. Keypad yang mengirim
// otomatis di 4 digit akan mengirim PIN separuh untuk yang ber-PIN 6; yang
// mewajibkan 6 digit akan mengunci semua yang ber-PIN 4.

/// Membungkus keypad dengan state, seperti pemakaian sebenarnya.
class _Uji extends StatefulWidget {
  const _Uji({this.aktif = true, this.onPenuh});
  final bool aktif;
  final VoidCallback? onPenuh;

  @override
  State<_Uji> createState() => _UjiState();
}

class _UjiState extends State<_Uji> {
  String nilai = '';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: KeypadKode(
            nilai: nilai,
            aktif: widget.aktif,
            onBerubah: (v) => setState(() => nilai = v),
            onPenuh: widget.onPenuh,
          ),
        ),
      ),
    );
  }
}

/// Mengembalikan pembaca nilai terkini, bukan state-nya sendiri — tipe privat
/// tak boleh bocor lewat API publik.
Future<String Function()> buka(
  WidgetTester t, {
  bool aktif = true,
  VoidCallback? onPenuh,
}) async {
  await t.pumpWidget(_Uji(aktif: aktif, onPenuh: onPenuh));
  return () => t.state<_UjiState>(find.byType(_Uji)).nilai;
}

Future<void> tekan(WidgetTester t, List<String> urutan) async {
  for (final k in urutan) {
    await t.tap(find.byKey(ValueKey('keypad-$k')));
    await t.pump();
  }
}

void main() {
  testWidgets('angka tersusun sesuai urutan ketukan', (t) async {
    final nilai = await buka(t);
    await tekan(t, ['1', '2', '3', '4']);
    expect(nilai(), '1234');
  });

  testWidgets('tidak bisa melebihi 6 digit', (t) async {
    // Digit ke-7 harus diabaikan diam-diam, bukan menggeser digit pertama
    // keluar — PIN yang bergeser menghasilkan angka yang tampak wajar dan
    // salah.
    final nilai = await buka(t);
    await tekan(t, ['1', '2', '3', '4', '5', '6', '7', '8']);
    expect(nilai(), '123456');
  });

  testWidgets('⌫ menghapus TEPAT satu digit', (t) async {
    final nilai = await buka(t);
    await tekan(t, ['9', '8', '7', '⌫']);
    expect(nilai(), '98');
  });

  testWidgets('⌫ pada isi kosong tidak menghancurkan apa pun', (t) async {
    final nilai = await buka(t);
    await tekan(t, ['⌫', '⌫']);
    expect(nilai(), '');
  });

  testWidgets('C mengosongkan seluruhnya', (t) async {
    final nilai = await buka(t);
    await tekan(t, ['1', '2', '3', 'C']);
    expect(nilai(), '');
  });

  group('kirim otomatis dan panjang PIN yang berubah-ubah', () {
    testWidgets('TIDAK terkirim di 4 digit', (t) async {
      // Kalau terkirim di sini, staf ber-PIN 6 digit mengirim 4 digit pertama
      // sebagai PIN — selalu ditolak, dan percobaannya habis tanpa ia pernah
      // selesai mengetik.
      var terkirim = 0;
      await buka(t, onPenuh: () => terkirim++);
      await tekan(t, ['1', '2', '3', '4']);
      expect(terkirim, 0);
    });

    testWidgets('TIDAK terkirim di 5 digit', (t) async {
      var terkirim = 0;
      await buka(t, onPenuh: () => terkirim++);
      await tekan(t, ['1', '2', '3', '4', '5']);
      expect(terkirim, 0);
    });

    testWidgets('terkirim TEPAT SEKALI di 6 digit', (t) async {
      // 6 adalah batas atas: tak ada digit ke-7 yang mungkin diketik, jadi
      // mengirim di sini tak pernah memotong ketikan siapa pun.
      var terkirim = 0;
      await buka(t, onPenuh: () => terkirim++);
      await tekan(t, ['1', '2', '3', '4', '5', '6']);
      expect(terkirim, 1);
    });

    testWidgets('ketukan setelah penuh tidak mengirim ulang', (t) async {
      // Kasir yang menekan lagi karena mengira ketukannya tak terbaca akan
      // mengirim permintaan kedua — dan menghabiskan percobaan yang sama
      // dua kali.
      var terkirim = 0;
      await buka(t, onPenuh: () => terkirim++);
      await tekan(t, ['1', '2', '3', '4', '5', '6', '7', '8']);
      expect(terkirim, 1);
    });

    testWidgets('PIN 4 digit tetap utuh dan siap dikirim tombol', (t) async {
      // Jalur inilah yang dipakai staf ber-PIN pendek. Nilainya harus tetap
      // persis 4 digit itu — tombol kirim di halaman verifikasi yang
      // mengirimkannya.
      final nilai = await buka(t);
      await tekan(t, ['5', '0', '2', '9']);
      expect(nilai(), '5029');
    });
  });

  testWidgets('saat nonaktif seluruh ketukan diabaikan', (t) async {
    // aktif=false berarti verifikasi sedang berjalan. Ketukan yang lolos di
    // sana mengubah PIN yang sedang dikirim.
    var terkirim = 0;
    final nilai = await buka(t, aktif: false, onPenuh: () => terkirim++);
    await tekan(t, ['1', '2', '3', '4', '5', '6']);
    expect(nilai(), '');
    expect(terkirim, 0);
  });

  testWidgets('titik terisi mengikuti jumlah digit', (t) async {
    await buka(t);
    await tekan(t, ['1', '2', '3']);

    Color warna(int i) {
      final c = t.widget<AnimatedContainer>(
        find.byKey(ValueKey('keypad-titik-$i')),
      );
      return (c.decoration! as BoxDecoration).color!;
    }

    expect(warna(0), equals(warna(2)), reason: 'titik 0-2 harus terisi');
    expect(
      warna(3),
      isNot(equals(warna(0))),
      reason:
          'titik ke-4 belum terisi tapi tampak sama — kasir tak bisa '
          'menghitung sudah berapa digit yang masuk',
    );
  });

  testWidgets('nol bisa jadi digit pertama', (t) async {
    // PIN boleh diawali nol; keypad yang memperlakukan '0' seperti angka
    // biasa di kalkulator akan membuangnya.
    final nilai = await buka(t);
    await tekan(t, ['0', '0', '1', '2']);
    expect(nilai(), '0012');
  });
}
