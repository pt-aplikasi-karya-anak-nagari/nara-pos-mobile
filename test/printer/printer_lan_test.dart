import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/printer/data/printer_lan.dart';

void main() {
  group('alamat printer jaringan', () {
    test('masukan pengguna', () {
      expect(AlamatPrinterLan.urai('192.168.1.50'),
          const AlamatPrinterLan('192.168.1.50', 9100));
      expect(AlamatPrinterLan.urai(' 10.0.0.7:9101 '),
          const AlamatPrinterLan('10.0.0.7', 9101));
      expect(AlamatPrinterLan.urai('printer-dapur.local'),
          const AlamatPrinterLan('printer-dapur.local', 9100));
      for (final salah in [
        '',
        '192.168.1',
        '192.168.1.256',
        '192.168.01.5',
        '10.0.0.7:0',
        '10.0.0.7:70000',
        '10.0.0.7:abc',
        'http://10.0.0.7',
        'printer dapur',
      ]) {
        expect(AlamatPrinterLan.urai(salah), isNull, reason: salah);
      }
    });

    test('disimpan di slot printer & dibedakan dari MAC Bluetooth', () {
      final a = AlamatPrinterLan.urai('192.168.1.50')!;
      expect(a.kunci, 'tcp:192.168.1.50:9100');
      expect(AlamatPrinterLan.dariKunci(a.kunci), a);
      expect(AlamatPrinterLan.dariKunci('DC:0D:30:12:34:56'), isNull);
      expect(AlamatPrinterLan.dariKunci(''), isNull);
      expect(a.label, '192.168.1.50');
      expect(const AlamatPrinterLan('10.0.0.7', 9101).label, '10.0.0.7:9101');
    });
  });

  group('kirim ke printer jaringan', () {
    test('byte ESC/POS sampai utuh lalu koneksi ditutup', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final diterima = Completer<List<int>>();
      server.listen((klien) async {
        final isi = <int>[];
        await for (final b in klien) {
          isi.addAll(b);
        }
        diterima.complete(isi); // stream selesai = klien menutup koneksi
      });
      final bytes = [0x1B, 0x40, ...'Halo'.codeUnits, 0x1D, 0x56, 0x00];
      final ok = await kirimKePrinterLan(
        AlamatPrinterLan('127.0.0.1', server.port),
        bytes,
      );
      expect(ok, isTrue);
      expect(await diterima.future.timeout(const Duration(seconds: 3)), bytes);
      await server.close();
    });

    test('printer mati → false, tidak melempar', () async {
      // Port yang baru dilepas: tak ada yang mendengarkan.
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = s.port;
      await s.close();
      final a = AlamatPrinterLan('127.0.0.1', port);
      expect(await kirimKePrinterLan(a, [1, 2, 3], batasWaktu: const Duration(seconds: 1)), isFalse);
      expect(await cekPrinterLan(a, batasWaktu: const Duration(seconds: 1)), isFalse);
    });
  });
}
