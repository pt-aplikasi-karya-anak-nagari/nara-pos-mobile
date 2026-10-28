import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:nara_pos_mobile/core/connectivity_service.dart';
import 'package:nara_pos_mobile/core/offline/data_kasir_offline.dart';
import 'package:nara_pos_mobile/features/kasir/providers.dart';
import 'package:nara_pos_mobile/features/order_types/data/order_type_repository.dart';
import 'package:nara_pos_mobile/features/order_types/domain/order_type.dart';
import 'package:nara_pos_mobile/features/payments/data/payment_method_repository.dart';
import 'package:nara_pos_mobile/features/payments/domain/payment_method.dart';

// Laporan: saat offline, layar bayar hanya menampilkan "Bayar Nanti", tipe
// pesanan kosong, dan tombol "Konfirmasi Pembayaran" tak pernah aktif.
//
// Di tablet itu cache offline metode bayar & tipe pesanan memang kosong: cache
// baru terisi saat layar bayar dibuka sambil online, dan tablet yang baru
// di-install sudah offline sebelum itu terjadi.

ProviderContainer _wadah({
  Future<List<PaymentMethod>> Function()? metode,
  Future<List<OrderType>> Function()? tipe,
  bool offline = true,
}) {
  final c = ProviderContainer(
    overrides: [
      paymentMethodsFutureProvider.overrideWith(
        (ref) => (metode ?? () async => <PaymentMethod>[])(),
      ),
      orderTypesFutureProvider.overrideWith(
        (ref) => (tipe ?? () async => <OrderType>[])(),
      ),
      isOfflineProvider.overrideWithValue(offline),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _muat(ProviderContainer c) async {
  c.listen(paymentMethodsFutureProvider, (_, _) {});
  c.listen(orderTypesFutureProvider, (_, _) {});
  // Jangan menunggu `.future`: provider yang gagal diulang otomatis oleh
  // Riverpod, dan `.future`-nya baru selesai setelah semua percobaan habis.
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

void main() {
  group('metode bayar kasir', () {
    test('offline tanpa salinan → Tunai bawaan', () async {
      final c = _wadah();
      await _muat(c);
      final m = c.read(metodeBayarKasirProvider);
      expect(m.map((e) => e.name), ['Tunai']);
      expect(m.single.type, 'cash');
    });

    test('server gagal → Tunai bawaan', () async {
      final c = _wadah(
        metode: () async => throw 'Gagal terhubung ke server (500)',
        offline: false,
      );
      await _muat(c);
      expect(c.read(metodeBayarKasirProvider).map((e) => e.name), ['Tunai']);
    });

    test(
      'online dengan nol metode aktif → tetap kosong (keputusan pemilik)',
      () async {
        final c = _wadah(offline: false);
        await _muat(c);
        expect(c.read(metodeBayarKasirProvider), isEmpty);
      },
    );

    test('ada data → hanya metode aktif, tanpa bawaan', () async {
      final c = _wadah(
        metode: () async => [
          PaymentMethod(name: 'Tunai', type: 'cash'),
          PaymentMethod(name: 'QRIS', type: 'qris'),
          PaymentMethod(name: 'Lama', type: 'transfer', isActive: false),
        ],
      );
      await _muat(c);
      expect(c.read(metodeBayarKasirProvider).map((e) => e.name), [
        'Tunai',
        'QRIS',
      ]);
    });
  });

  group('tipe pesanan kasir', () {
    test('tanpa salinan → Take Away (bawaan) & Dine In', () async {
      final c = _wadah();
      await _muat(c);
      final t = c.read(tipePesananKasirProvider);
      expect(t.map((e) => e.name), ['Take Away', 'Dine In']);
      expect(t.first.isDefault, isTrue);
    });

    test(
      'tipe pesanan aktif otomatis terpilih → tombol bayar bisa aktif',
      () async {
        final c = _wadah();
        await _muat(c);
        // Take Away, bukan Dine In: Dine In mensyaratkan meja, yang pun bisa
        // belum tersimpan di tablet.
        expect(c.read(activeOrderTypeProvider)?.name, 'Take Away');
      },
    );

    test('ada data outlet → dipakai apa adanya', () async {
      final c = _wadah(
        tipe: () async => [
          OrderType(id: 'ot1', name: 'Dine In'),
          OrderType(id: 'ot2', name: 'Bungkus', isDefault: true),
        ],
      );
      await _muat(c);
      expect(c.read(tipePesananKasirProvider).map((e) => e.name), [
        'Dine In',
        'Bungkus',
      ]);
      expect(c.read(activeOrderTypeProvider)?.name, 'Bungkus');
    });
  });
}
