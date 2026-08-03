import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/kasir/ui/widgets/tab_badge.dart';

// Lencana jumlah di tab kasir.
//
// # APA YANG DIPERTARUHKAN
//
// Kasir hanya melihat SATU tab pada satu waktu. Pesanan meja yang masuk saat ia
// sedang menyusun keranjang tak terlihat sama sekali sampai ia menyentuh tab
// sebelah — dan pelanggan di meja itu menunggu tanpa ada yang tahu.
//
// Kegagalan lencana selalu diam: ia tidak menampilkan galat, ia hanya
// menampilkan angka yang salah, atau tidak menampilkan apa-apa saat seharusnya
// menampilkan sesuatu.

Future<void> pasang(WidgetTester t, {int? jumlah, String label = 'Tab'}) async {
  await t.pumpWidget(
    MaterialApp(
      home: DefaultTabController(
        length: 1,
        child: Scaffold(
          appBar: AppBar(
            bottom: TabBar(
              tabs: [TabBerlencana(label: label, jumlah: jumlah)],
            ),
          ),
          body: const SizedBox(),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('label selalu tampil', (t) async {
    await pasang(t, jumlah: 3, label: 'Pesanan dari Scan Meja');
    expect(find.text('Pesanan dari Scan Meja'), findsOneWidget);
  });

  testWidgets('jumlah tampil saat lebih dari nol', (t) async {
    await pasang(t, jumlah: 3);
    expect(find.text('3'), findsOneWidget);
  });

  group('nol vs belum diketahui', () {
    testWidgets('NOL tidak menampilkan lencana', (t) async {
      // Lencana "0" yang selalu menempel jadi hiasan yang diabaikan mata, dan
      // begitu ia berubah jadi "1" tak ada yang menyadarinya — persis saat
      // kesadaran itu paling dibutuhkan.
      await pasang(t, jumlah: 0);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('BELUM DIKETAHUI juga tidak menampilkan lencana', (t) async {
      // null = data belum tiba dari jaringan. Menampilkan "0" di sini adalah
      // kebohongan kecil: kasir menyimpulkan tak ada pesanan masuk, lalu
      // berhenti memeriksa.
      await pasang(t, jumlah: null);
      expect(find.text('0'), findsNothing);
      expect(find.byKey(const ValueKey('tab-badge-0')), findsNothing);
    });
  });

  testWidgets('angka besar dipangkas jadi 99+', (t) async {
    // Tanpa batas, lencananya melebar dan mendorong label tab keluar layar.
    await pasang(t, jumlah: 250);
    expect(find.text('99+'), findsOneWidget);
    expect(find.text('250'), findsNothing);
  });

  testWidgets('99 TEPAT masih ditampilkan apa adanya', (t) async {
    // Batasnya di ATAS 99, bukan pada 99. Memangkas 99 jadi "99+" membuang
    // ketepatan tanpa alasan.
    await pasang(t, jumlah: 99);
    expect(find.text('99'), findsOneWidget);
    expect(find.text('99+'), findsNothing);
  });

  testWidgets('label panjang tidak meluber di tab sempit', (t) async {
    // Label "Pesanan dari Scan Meja" ditambah lencana lebih lebar daripada
    // ruang tabnya di layar kecil. Yang boleh terjadi adalah teksnya dipotong,
    // BUKAN garis kuning-hitam menutupi antarmuka kasir.
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              bottom: const TabBar(
                tabs: [
                  TabBerlencana(label: 'Langsung di Kasir', jumlah: 12),
                  TabBerlencana(label: 'Pesanan dari Scan Meja', jumlah: 34),
                ],
              ),
            ),
            body: const SizedBox(),
          ),
        ),
      ),
    );
    expect(
      t.takeException(),
      isNull,
      reason:
          'tab meluber — kasir melihat garis kuning-hitam alih-alih '
          'nama tabnya',
    );
    expect(find.text('12'), findsOneWidget);
    expect(find.text('34'), findsOneWidget);
  });

  testWidgets('jumlah negatif diperlakukan seperti kosong', (t) async {
    // Tak seharusnya terjadi, tapi lencana "-1" di layar kasir jauh lebih
    // membingungkan daripada tak ada lencana sama sekali.
    await pasang(t, jumlah: -1);
    expect(find.text('-1'), findsNothing);
  });
}
