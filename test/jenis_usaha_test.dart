import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/core/jenis_usaha.dart';
import 'package:nara_pos_mobile/features/outlet/domain/outlet.dart';

void main() {
  group('JenisUsaha.dari', () {
    test('nama tipe bawaan server', () {
      expect(JenisUsaha.dari(typeName: 'F&B'), JenisUsaha.fnb);
      expect(JenisUsaha.dari(typeName: 'Retail'), JenisUsaha.retail);
      expect(JenisUsaha.dari(typeName: 'Service'), JenisUsaha.jasa);
    });

    test('nama buatan SuperAdmin yang mirip', () {
      expect(JenisUsaha.dari(typeName: 'Kafe & Resto'), JenisUsaha.fnb);
      expect(JenisUsaha.dari(typeName: 'Toko Ritel'), JenisUsaha.retail);
      expect(JenisUsaha.dari(typeName: 'Jasa / Laundry'), JenisUsaha.jasa);
      expect(JenisUsaha.dari(typeName: 'Lainnya'), JenisUsaha.umum);
    });

    test('tanpa nama: cadangan id seed', () {
      expect(JenisUsaha.dari(typeId: 1), JenisUsaha.retail);
      expect(JenisUsaha.dari(typeId: 2), JenisUsaha.fnb);
      expect(JenisUsaha.dari(typeId: 3), JenisUsaha.jasa);
      expect(JenisUsaha.dari(), JenisUsaha.umum);
    });
  });

  group('relevansi fitur', () {
    test('F&B: meja, dapur, resep, topping; tanpa batasan stok', () {
      for (final k in [
        'table_management',
        'qr_self_order',
        'kitchen_display',
        'recipe_bom',
        'modifiers',
        'order_types',
        'stock_transfer',
        'scan',
      ]) {
        expect(JenisUsaha.fnb.relevan(k), isTrue, reason: k);
      }
    });

    test('Retail: tanpa meja, dapur, resep, modifier, tipe pesanan', () {
      for (final k in [
        'table_management',
        'qr_self_order',
        'kitchen_display',
        'recipe_bom',
        'modifiers',
        'order_types',
      ]) {
        expect(JenisUsaha.retail.relevan(k), isFalse, reason: k);
      }
      for (final k in [
        'inventory_tracking',
        'stock_transfer',
        'supplier_po',
        'scan',
        'product_variants',
      ]) {
        expect(JenisUsaha.retail.relevan(k), isTrue, reason: k);
      }
    });

    test('Jasa: tanpa meja & stok gudang, tetap punya layanan tambahan', () {
      for (final k in [
        'table_management',
        'recipe_bom',
        'stock_transfer',
        'supplier_po',
        'scan',
      ]) {
        expect(JenisUsaha.jasa.relevan(k), isFalse, reason: k);
      }
      for (final k in [
        'modifiers',
        'order_types',
        'customer_crm',
        'loyalty_program',
      ]) {
        expect(JenisUsaha.jasa.relevan(k), isTrue, reason: k);
      }
    });

    test('Umum (tipe tak dikenal): semua tampil', () {
      expect(JenisUsaha.umum.relevan('table_management'), isTrue);
      expect(JenisUsaha.umum.relevan('stock_transfer'), isTrue);
    });

    test('sebutan katalog per jenis', () {
      expect(JenisUsaha.fnb.sebutanKatalog, 'Menu');
      expect(JenisUsaha.jasa.sebutanKatalog, 'Layanan');
      expect(JenisUsaha.retail.sebutanKatalog, 'Produk');
    });
  });

  test('outlet membaca & meng-cache jenis outlet', () {
    final o = Outlet.fromJson({
      'id': 'o1',
      'name': 'Kopi',
      'type_id': 2,
      'type_name': 'F&B',
    });
    expect(o.typeName, 'F&B');
    final lagi = Outlet.fromJson(o.toCacheJson());
    expect(lagi.typeId, 2);
    expect(
      JenisUsaha.dari(typeId: lagi.typeId, typeName: lagi.typeName),
      JenisUsaha.fnb,
    );
  });
}
