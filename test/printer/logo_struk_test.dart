import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:nara_pos_mobile/features/printer/data/logo_struk.dart';

// Struk dulu selalu dicetak dengan logo Flutter bawaan — logo yang diunggah
// Pemilik tak pernah dipakai.

Uint8List _png(int w, int h, {img.Color? warna, bool transparan = false}) {
  final g = img.Image(width: w, height: h, numChannels: 4);
  img.fill(
    g,
    color: transparan
        ? img.ColorRgba8(0, 0, 0, 0)
        : (warna ?? img.ColorRgb8(0, 0, 0)),
  );
  return Uint8List.fromList(img.encodePng(g));
}

void main() {
  group('siapkanLogoStruk', () {
    test('bagian transparan tercetak putih, bukan hitam', () {
      final logo = siapkanLogoStruk(
        _png(50, 50, transparan: true),
        lebarMaks: 240,
      )!;
      expect(logo.getPixel(10, 10).r, 255);
    });

    test('logo besar diperkecil ke lebar kertas, proporsional', () {
      final logo = siapkanLogoStruk(_png(1000, 500), lebarMaks: 240)!;
      expect(logo.width, 240);
      expect(logo.height, 120);
    });

    test('logo tegak dibatasi tingginya', () {
      final logo = siapkanLogoStruk(_png(300, 900), lebarMaks: 240)!;
      expect(logo.height, 240);
      expect(logo.width, 80);
    });

    test('logo kecil tak diperbesar', () {
      final logo = siapkanLogoStruk(_png(100, 60), lebarMaks: 240)!;
      expect((logo.width, logo.height), (100, 60));
    });

    test('bukan gambar → tanpa logo', () {
      expect(
        siapkanLogoStruk(Uint8List.fromList([1, 2, 3]), lebarMaks: 240),
        isNull,
      );
    });

    test('lebar mengikuti ukuran kertas', () {
      expect(
        lebarLogoUntuk(PaperSize.mm58),
        lessThan(lebarLogoUntuk(PaperSize.mm80)),
      );
      expect(lebarLogoUntuk(PaperSize.mm58), lessThanOrEqualTo(384));
    });
  });

  group('LogoStrukStore', () {
    late Directory dir;
    late List<String> diunduh;
    late Object? galat;
    late Map<String, Uint8List> server;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('logo_struk_');
      diunduh = [];
      galat = null;
      server = {
        '/uploads/receipt-logos/a.png': _png(20, 20),
        '/uploads/receipt-logos/b.png': _png(30, 30),
      };
    });
    tearDown(() => dir.delete(recursive: true));

    LogoStrukStore store() => LogoStrukStore(
      folder: () async => dir,
      unduh: (url) async {
        diunduh.add(url);
        if (galat != null) throw galat!;
        return server[url] ?? Uint8List(0);
      },
    );

    test('diunduh sekali, lalu dibaca dari perangkat', () async {
      final a = await store().ambil('o1', '/uploads/receipt-logos/a.png');
      final b = await store().ambil('o1', '/uploads/receipt-logos/a.png');
      expect(a, isNotNull);
      expect(b, a);
      expect(diunduh, hasLength(1));
    });

    test('tetap berlogo saat offline', () async {
      await store().ambil('o1', '/uploads/receipt-logos/a.png');
      galat = const SocketException('offline');
      final logo = await store().ambil('o1', '/uploads/receipt-logos/a.png');
      expect(logo, isNotNull);
    });

    test('logo diganti Pemilik → yang baru diunduh', () async {
      await store().ambil('o1', '/uploads/receipt-logos/a.png');
      final baru = await store().ambil('o1', '/uploads/receipt-logos/b.png');
      expect(img.decodeImage(baru!)!.width, 30);
      // Offline saat logo diganti: logo lama tetap dicetak.
      galat = const SocketException('offline');
      server.remove('/uploads/receipt-logos/b.png');
      final lama = await store().ambil('o1', '/uploads/receipt-logos/c.png');
      expect(img.decodeImage(lama!)!.width, 30);
    });

    test('logo dihapus Pemilik → struk tanpa logo', () async {
      await store().ambil('o1', '/uploads/receipt-logos/a.png');
      expect(await store().ambil('o1', ''), isNull);
      galat = const SocketException('offline');
      expect(await store().ambil('o1', null), isNull);
    });

    test('balasan yang bukan gambar tak disimpan', () async {
      final logo = await store().ambil(
        'o1',
        '/uploads/receipt-logos/rusak.png',
      );
      expect(logo, isNull);
      expect(dir.listSync(), isEmpty);
    });

    test('simpanan terpisah per outlet', () async {
      await store().ambil('o1', '/uploads/receipt-logos/a.png');
      await store().ambil('o2', '/uploads/receipt-logos/b.png');
      final o1 = await store().ambil('o1', '/uploads/receipt-logos/a.png');
      expect(img.decodeImage(o1!)!.width, 20);
    });
  });
}
