import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nara_pos_mobile/core/outlet_scope.dart';
import 'package:nara_pos_mobile/features/kasir/domain/cart_item.dart';
import 'package:nara_pos_mobile/features/kasir/domain/pajak_multi_tarif.dart';
import 'package:nara_pos_mobile/features/kasir/providers.dart';
import 'package:nara_pos_mobile/features/outlet/domain/outlet.dart';
import 'package:nara_pos_mobile/features/products/domain/product.dart';
import 'package:nara_pos_mobile/features/settings/data/tarif_pajak.dart';
import 'package:nara_pos_mobile/features/user/data/auth_service.dart';

// Pajak multi-tarif sampai ke angka yang dibayar di kasir: keranjang dengan
// produk bertarif tambahan → taxProvider/totalProvider/rincianPajakProvider
// sama dengan hitungan server (lihat juga test/pajak_multi_tarif_test.dart).

class _FakeAuth extends AuthNotifier {
  @override
  AuthState build() => const AuthState();
}

const _ppn = TarifPajak(id: 'TAXR-PPN', nama: 'PPN', persen: 11);

ProviderContainer _wadah(Outlet outlet, Map<String, TarifPajak> tarif) {
  final c = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      activeOutletProvider.overrideWithValue(outlet),
      tarifPajakProvider.overrideWithValue(tarif),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Outlet _pb1({double sc = 0, bool inclusive = false, bool aktif = true}) => Outlet(
      name: 'Kafe Uji',
      taxEnabled: aktif,
      taxPercent: 10,
      taxName: 'PB1',
      serviceChargePercent: sc,
      taxInclusive: inclusive,
    );

Product _p(String id, double harga, {String? tarif, bool kena = true}) =>
    Product(remoteId: id, name: id, price: harga, isTaxable: kena, taxRateId: tarif);

void main() {
  test('PB1 + PPN + bebas pajak, service 5% (sama dengan server)', () {
    final c = _wadah(_pb1(sc: 5), {'TAXR-PPN': _ppn});
    c.read(cartProvider.notifier).replaceAll([
      CartItem(_p('Nasi', 50000), 2),
      CartItem(_p('Air', 20000, tarif: 'TAXR-PPN'), 1),
      CartItem(_p('Rokok', 30000, kena: false), 1),
    ]);
    expect(c.read(subtotalProvider), 150000);
    expect(c.read(serviceChargeProvider), 7500);
    expect(c.read(taxProvider), 12950);
    expect(c.read(totalProvider), 170450);

    final r = c.read(rincianPajakProvider);
    expect(r.map((b) => b.label), ['PB1 (10%)', 'PPN (11%)']);
    expect(r.map((b) => b.pajak), [10750, 2200]);
  });

  test('tanpa produk bertarif tambahan → jalur lama, tanpa rincian', () {
    final c = _wadah(_pb1(sc: 5), {'TAXR-PPN': _ppn});
    c.read(cartProvider.notifier).replaceAll([CartItem(_p('Nasi', 87500), 1)]);
    expect(c.read(rincianPajakProvider), isEmpty);
    expect(c.read(taxProvider), 9188); // (87.500 + 4.375) × 10%
    expect(c.read(totalProvider), 101063);
  });

  test('tarif belum termuat (offline tanpa salinan) → semua tarif default', () {
    final c = _wadah(_pb1(), const {});
    c.read(cartProvider.notifier).replaceAll([
      CartItem(_p('Air', 20000, tarif: 'TAXR-PPN'), 1),
    ]);
    expect(c.read(rincianPajakProvider), isEmpty);
    expect(c.read(taxProvider), 2000);
  });

  test('tarif nonaktif → produknya ditagih tarif default', () {
    final c = _wadah(_pb1(), {
      'TAXR-PPN': const TarifPajak(id: 'TAXR-PPN', nama: 'PPN', persen: 11, aktif: false),
    });
    c.read(cartProvider.notifier).replaceAll([
      CartItem(_p('Air', 20000, tarif: 'TAXR-PPN'), 1),
    ]);
    expect(c.read(rincianPajakProvider), isEmpty);
    expect(c.read(taxProvider), 2000);
  });

  test('pajak outlet nonaktif → tarif tambahan diabaikan', () {
    final c = _wadah(_pb1(sc: 5, aktif: false), {'TAXR-PPN': _ppn});
    c.read(cartProvider.notifier).replaceAll([
      CartItem(_p('Air', 20000, tarif: 'TAXR-PPN'), 1),
    ]);
    expect(c.read(rincianPajakProvider), isEmpty);
    expect(c.read(taxProvider), 0);
    // Service charge tetap ditagih walau pajak nonaktif (sama dengan server).
    expect(c.read(serviceChargeProvider), 1000);
    expect(c.read(totalProvider), 21000);
  });

  test('inclusive dua tarif: pajak dikeluarkan dari harga per tarif', () {
    final c = _wadah(_pb1(inclusive: true), {'TAXR-PPN': _ppn});
    c.read(cartProvider.notifier).replaceAll([
      CartItem(_p('Nasi', 110000), 1),
      CartItem(_p('Air', 111000, tarif: 'TAXR-PPN'), 1),
    ]);
    expect(c.read(taxProvider), 21000);
    expect(c.read(totalProvider), 221000);
    expect(c.read(rincianPajakProvider).map((b) => b.pajak), [10000, 11000]);
  });
}
