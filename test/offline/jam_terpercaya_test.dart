import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/core/offline/jam_offline.dart';
import 'package:nara_pos_mobile/core/offline/jam_terpercaya.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Deteksi jam perangkat yang diubah saat offline.
//
// Jam terpercaya = jam server saat terakhir tersambung + uptime sistem yang
// berlalu sejak itu. Uptime tak bisa diubah pengguna, jadi jam perangkat yang
// dimundurkan MAUPUN dimajukan terlihat dari selisihnya.

class _UptimeTiruan extends SumberUptime {
  int uptimeMs = 1000000;
  int? boot = 7;
  bool tersedia = true;
  @override
  Future<BacaanUptime?> baca() async =>
      tersedia ? (uptimeMs: uptimeMs, boot: boot) : null;
}

void main() {
  final server = DateTime.utc(2026, 11, 1, 7, 0);

  group('waktuTerpercaya', () {
    final titik = TitikJam(server: server, uptimeMs: 1000, boot: 3);

    test('server + uptime yang berlalu', () {
      expect(
        waktuTerpercaya(titik, (uptimeMs: 1000 + 3600000, boot: 3)),
        server.add(const Duration(hours: 1)),
      );
    });

    test('perangkat dinyalakan ulang → tak diketahui', () {
      expect(waktuTerpercaya(titik, (uptimeMs: 999999999, boot: 4)), isNull);
      expect(waktuTerpercaya(titik, (uptimeMs: 10, boot: null)), isNull);
    });

    test('tanpa titik / tanpa uptime → tak diketahui', () {
      expect(waktuTerpercaya(null, (uptimeMs: 5, boot: 3)), isNull);
      expect(waktuTerpercaya(titik, null), isNull);
    });
  });

  group('nilaiJam', () {
    test('dalam toleransi → wajar', () {
      final p = nilaiJam(
        perangkat: server.add(const Duration(minutes: 9)),
        terpercaya: server,
      );
      expect(p.wajar, isTrue);
    });

    test('dimundurkan dan dimajukan sama-sama terdeteksi', () {
      final mundur = nilaiJam(
        perangkat: server.subtract(const Duration(hours: 3)),
        terpercaya: server,
      );
      expect(mundur.status, StatusJam.dimundurkan);
      expect(mundur.selisih, const Duration(hours: -3));
      expect(mundur.seharusnya, server);

      final maju = nilaiJam(
        perangkat: server.add(const Duration(days: 1)),
        terpercaya: server,
      );
      expect(maju.status, StatusJam.dimajukan);
    });

    test(
      'tanpa jam terpercaya: hanya mundur dari jam terbesar yang dikenali',
      () {
        expect(
          nilaiJam(
            perangkat: server.subtract(const Duration(hours: 1)),
            terbesar: server,
          ).status,
          StatusJam.dimundurkan,
        );
        expect(
          nilaiJam(
            perangkat: server.add(const Duration(days: 2)),
            terbesar: server,
          ).wajar,
          isTrue,
        );
      },
    );

    test('pesan menyebut arah, besarnya, dan jam yang seharusnya', () {
      final p = nilaiJam(
        perangkat: DateTime(2026, 11, 1, 11, 0),
        terpercaya: DateTime(2026, 11, 1, 14, 5),
      );
      final pesan = pesanJamTidakWajar(p);
      expect(pesan, contains('dimundurkan 3 jam 5 menit'));
      expect(pesan, contains('14.05'));
      expect(pesan, contains('Tanggal & waktu otomatis'));
    });
  });

  group('JamOffline', () {
    late SharedPreferences prefs;
    late _UptimeTiruan uptime;
    late DateTime jamPerangkat;
    late JamOffline jam;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      uptime = _UptimeTiruan();
      jamPerangkat = server;
      jam = JamOffline(prefs, sekarang: () => jamPerangkat, uptime: uptime);
      await jam.catatKontakServer(server);
    });

    // Satu jam berlalu sungguhan (uptime ikut berjalan).
    void berlalu(Duration d) {
      uptime.uptimeMs += d.inMilliseconds;
      jamPerangkat = jamPerangkat.add(d);
    }

    test('jam normal setelah offline lama tetap wajar', () async {
      berlalu(const Duration(hours: 5));
      expect((await jam.periksa()).wajar, isTrue);
      expect(jam.pernahDiubah, isFalse);
    });

    test(
      'dimundurkan saat offline terdeteksi & tercatat sampai online lagi',
      () async {
        berlalu(const Duration(hours: 1));
        jamPerangkat = jamPerangkat.subtract(const Duration(days: 2));
        final p = await jam.periksa();
        expect(p.status, StatusJam.dimundurkan);
        expect(jam.pernahDiubah, isTrue);

        // Dibetulkan: wajar lagi, tapi jejaknya tetap ada untuk Pemilik.
        jamPerangkat = jamPerangkat.add(const Duration(days: 2));
        expect((await jam.periksa()).wajar, isTrue);
        expect(jam.pernahDiubah, isTrue);

        await jam.catatKontakServer(server.add(const Duration(hours: 2)));
        expect(jam.pernahDiubah, isFalse);
      },
    );

    test('dimajukan saat offline terdeteksi (dulu lolos)', () async {
      berlalu(const Duration(minutes: 30));
      jamPerangkat = jamPerangkat.add(const Duration(hours: 6));
      expect((await jam.periksa()).status, StatusJam.dimajukan);
    });

    test('jam sudah salah SEBELUM offline tetap tertangkap', () async {
      // Online dengan jam perangkat terlambat sehari — kontak server mencatat
      // jam SERVER, bukan jam perangkat.
      jamPerangkat = server.subtract(const Duration(days: 1));
      await jam.catatKontakServer(server.add(const Duration(minutes: 1)));
      expect(jam.selisihSaatOnline!.inHours, -24);
      expect((await jam.periksa()).status, StatusJam.dimundurkan);
    });

    test('langganan & batas offline memakai jam terpercaya', () async {
      berlalu(const Duration(hours: 30));
      jamPerangkat = jamPerangkat.subtract(const Duration(hours: 29)); // mundur
      await jam.periksa();
      expect(
        jam.waktuAcuan().isBefore(server.add(const Duration(hours: 30))),
        isFalse,
        reason: 'memundurkan jam tak boleh memundurkan acuan masa langganan',
      );
      expect(jam.lamaOffline()!.inHours, greaterThanOrEqualTo(30));
    });

    test('setelah nyala ulang jatuh ke penjagaan jam terbesar', () async {
      berlalu(const Duration(hours: 1));
      await jam.periksa(); // jam terbesar = server + 1 jam
      uptime
        ..boot = 8
        ..uptimeMs = 5000;
      jamPerangkat = server.subtract(const Duration(hours: 3));
      expect((await jam.periksa()).status, StatusJam.dimundurkan);
    });

    test('pastikanJamWajar menahan aksi offline', () async {
      jamPerangkat = jamPerangkat.add(const Duration(days: 3));
      await expectLater(
        pastikanJamWajar(jam),
        throwsA(isA<JamPerangkatDiubah>()),
      );
    });
  });
}
