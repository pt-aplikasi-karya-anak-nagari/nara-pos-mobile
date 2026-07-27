import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/core/network/toast_throttle.dart';

void main() {
  // Kasus nyata yang memicu perbaikan ini: halaman kasir mem-polling kategori,
  // produk, shift aktif, dan konfigurasi printer. Saat langganan outlet habis,
  // keempatnya gagal dengan pesan yang sama, tiap beberapa detik — layar
  // tertutup tumpukan toast merah identik.
  group('ToastThrottle', () {
    const pesanLangganan =
        'Outlet belum memiliki langganan aktif. Silakan pilih paket untuk melanjutkan akses.';

    test(
      'empat request paralel yang gagal serupa hanya memunculkan satu toast',
      () {
        final peredam = ToastThrottle();
        final t0 = DateTime(2026, 7, 27, 23, 30);

        final tampil = [
          peredam.boleh(pesanLangganan, kondisiMenetap: true, sekarang: t0),
          peredam.boleh(
            pesanLangganan,
            kondisiMenetap: true,
            sekarang: t0.add(const Duration(milliseconds: 40)),
          ),
          peredam.boleh(
            pesanLangganan,
            kondisiMenetap: true,
            sekarang: t0.add(const Duration(milliseconds: 90)),
          ),
          peredam.boleh(
            pesanLangganan,
            kondisiMenetap: true,
            sekarang: t0.add(const Duration(milliseconds: 130)),
          ),
        ];

        expect(tampil, [true, false, false, false]);
      },
    );

    test('polling tiap 6 detik tidak mengulang toast kondisi menetap', () {
      final peredam = ToastThrottle();
      final t0 = DateTime(2026, 7, 27, 23, 30);
      var jumlahTampil = 0;

      // 10 putaran polling = 60 detik.
      for (var i = 0; i < 10; i++) {
        final ok = peredam.boleh(
          pesanLangganan,
          kondisiMenetap: true,
          sekarang: t0.add(Duration(seconds: i * 6)),
        );
        if (ok) jumlahTampil++;
      }

      expect(
        jumlahTampil,
        1,
        reason: 'kondisi menetap cukup diberitahukan sekali',
      );
    });

    test('kegagalan sesaat boleh muncul lagi setelah jeda umum lewat', () {
      final peredam = ToastThrottle();
      final t0 = DateTime(2026, 7, 27, 23, 30);
      const pesan = 'Terjadi kesalahan sistem';

      expect(peredam.boleh(pesan, sekarang: t0), isTrue);
      expect(
        peredam.boleh(pesan, sekarang: t0.add(const Duration(seconds: 5))),
        isFalse,
        reason: 'toast sebelumnya masih terlihat',
      );
      expect(
        peredam.boleh(pesan, sekarang: t0.add(const Duration(seconds: 9))),
        isTrue,
        reason: 'percobaan baru setelah jeda harus tetap terlihat',
      );
    });

    test('pesan berbeda tidak saling membungkam', () {
      final peredam = ToastThrottle();
      final t0 = DateTime(2026, 7, 27, 23, 30);

      expect(peredam.boleh('Gagal menyimpan produk', sekarang: t0), isTrue);
      expect(
        peredam.boleh('Stok tidak mencukupi', sekarang: t0),
        isTrue,
        reason: 'error yang berbeda membawa informasi berbeda',
      );
    });

    test('reset() mengembalikan toast untuk sesi berikutnya', () {
      final peredam = ToastThrottle();
      final t0 = DateTime(2026, 7, 27, 23, 30);

      expect(
        peredam.boleh(pesanLangganan, kondisiMenetap: true, sekarang: t0),
        isTrue,
      );
      expect(
        peredam.boleh(pesanLangganan, kondisiMenetap: true, sekarang: t0),
        isFalse,
      );

      // Kasir lain mulai bertugas di perangkat yang sama.
      peredam.reset();
      expect(
        peredam.boleh(pesanLangganan, kondisiMenetap: true, sekarang: t0),
        isTrue,
        reason: 'pengguna baru belum pernah melihat pesan ini',
      );
    });
  });

  group('kondisiMenetapDariRespons', () {
    test('402 langganan habis dianggap menetap', () {
      expect(
        kondisiMenetapDariRespons(402, {'code': 'subscription_expired'}),
        isTrue,
      );
    });

    test('403 outlet di-suspend & izin kurang dianggap menetap', () {
      expect(
        kondisiMenetapDariRespons(403, {'code': 'outlet_suspended'}),
        isTrue,
      );
      expect(
        kondisiMenetapDariRespons(403, {'code': 'permission_denied'}),
        isTrue,
      );
    });

    test('403 tanpa kode dikenal TIDAK diredam lama', () {
      expect(
        kondisiMenetapDariRespons(403, {'message': 'Akses ditolak'}),
        isFalse,
      );
    });

    test('error biasa bukan kondisi menetap', () {
      expect(kondisiMenetapDariRespons(500, {'message': 'boom'}), isFalse);
      expect(
        kondisiMenetapDariRespons(400, {'code': 'validation_error'}),
        isFalse,
      );
      expect(kondisiMenetapDariRespons(null, null), isFalse);
    });

    test('402 tetap dianggap menetap walau body tak berbentuk map', () {
      expect(kondisiMenetapDariRespons(402, 'Payment Required'), isTrue);
    });
  });
}
