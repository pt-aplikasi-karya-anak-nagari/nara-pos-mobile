import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:nara_pos_mobile/features/outlet/domain/outlet.dart';
import 'package:nara_pos_mobile/features/products/domain/category.dart';
import 'package:nara_pos_mobile/features/products/domain/product.dart';
import 'package:nara_pos_mobile/features/customers/domain/customer.dart';
import 'package:nara_pos_mobile/features/payments/domain/payment_method.dart';
import 'package:nara_pos_mobile/features/order_types/domain/order_type.dart';
import 'package:nara_pos_mobile/features/tables/domain/pos_table.dart';
import 'package:nara_pos_mobile/features/tables/domain/table_group.dart';
import 'package:nara_pos_mobile/features/shifts/domain/shift.dart';

/// Offline read-cache (EntityCache) menyimpan model via `toCacheJson()` lalu
/// memulihkannya via `fromJson`. Test ini mengunci round-trip itu: field yang
/// dipakai kasir saat offline TIDAK boleh hilang/berubah saat melewati cache.
/// (Payload API `toJson` sengaja lossy — itulah kenapa toCacheJson terpisah.)
/// Lewatkan peta melalui jsonEncode/jsonDecode SUNGGUHAN, persis seperti yang
/// dilakukan penyimpanannya (EntityCache.save → jsonEncode; ProductCache →
/// jsonEncode). Tanpa ini, tes round-trip melompati batas yang paling mungkin
/// gagal: nilai yang tak bisa di-encode (DateTime, Set, objek) lolos saat peta
/// diteruskan langsung, lalu meledak di perangkat pengguna saat benar-benar
/// disimpan. Batasnya juga menormalkan tipe angka — sesuatu yang ditulis int
/// dan dibaca `as double` baru ketahuan di sini.
Map<String, dynamic> _kawat(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

void main() {
  test('Outlet round-trips through toCacheJson (incl tax config)', () {
    final o = Outlet(
      remoteId: 'OUTLET123',
      name: 'Kopi Senja',
      address: 'Jl. Mawar 1',
      phone: '0811',
      isActive: true,
      taxEnabled: true,
      taxPercent: 11,
      serviceChargePercent: 5,
      taxInclusive: true,
      taxName: 'PB1',
      serviceChargeName: 'Service',
      showSoldCount: true,
    );
    final back = Outlet.fromJson(_kawat(o.toCacheJson()));
    expect(back.remoteId, o.remoteId);
    expect(back.name, o.name);
    expect(back.taxEnabled, o.taxEnabled);
    expect(back.taxPercent, o.taxPercent);
    expect(back.serviceChargePercent, o.serviceChargePercent);
    expect(back.taxInclusive, o.taxInclusive);
    expect(back.taxName, o.taxName);
    expect(back.serviceChargeName, o.serviceChargeName);
    expect(back.showSoldCount, o.showSoldCount);
  });

  test('Category round-trips through toCacheJson', () {
    final c = Category(
      remoteId: 'CAT1',
      outletRemoteId: 'OUTLET123',
      name: 'Minuman',
      description: 'desc',
    );
    final back = Category.fromJson(_kawat(c.toCacheJson()));
    expect(back.remoteId, c.remoteId);
    expect(back.outletRemoteId, c.outletRemoteId);
    expect(back.name, c.name);
    expect(back.description, c.description);
  });

  test('Customer round-trips through toJson (cache codec)', () {
    final c = Customer(
      id: 'CUS1',
      name: 'Budi',
      phone: '0822',
      email: 'b@x.id',
      address: 'Jl. A',
      points: 150,
      membershipLevel: 'Gold',
      createdBy: 'owner',
    );
    final back = Customer.fromJson(_kawat(c.toJson()));
    expect(back.id, c.id);
    expect(back.name, c.name);
    expect(back.phone, c.phone);
    expect(back.points, c.points);
    expect(back.membershipLevel, c.membershipLevel);
  });

  test('PaymentMethod round-trips through toCacheJson (incl isSystem)', () {
    final m = PaymentMethod(
      id: 'PM1',
      name: 'QRIS',
      type: 'qris',
      code: 'QRIS',
      isActive: true,
      isDefault: true,
      isSystem: true,
      outletRemoteId: 'OUTLET123',
    );
    final back = PaymentMethod.fromJson(_kawat(m.toCacheJson()));
    expect(back.id, m.id);
    expect(back.name, m.name);
    expect(back.type, m.type);
    expect(back.code, m.code);
    expect(back.isActive, m.isActive);
    expect(back.isDefault, m.isDefault);
    expect(back.isSystem, m.isSystem); // dropped by API toJson, kept by cache
    expect(back.outletRemoteId, m.outletRemoteId);
  });

  test('OrderType round-trips through toCacheJson (incl outletRemoteId)', () {
    final t = OrderType(
      id: 'OT1',
      name: 'Dine In',
      isDefault: true,
      iconName: 'restaurant',
      showInSelection: false,
      isSystem: true,
      outletRemoteId: 'OUTLET123',
    );
    final back = OrderType.fromJson(_kawat(t.toCacheJson()));
    expect(back.id, t.id);
    expect(back.name, t.name);
    expect(back.isDefault, t.isDefault);
    expect(back.iconName, t.iconName);
    expect(back.showInSelection, t.showInSelection);
    expect(back.isSystem, t.isSystem);
    expect(back.outletRemoteId, t.outletRemoteId);
  });

  test('PosTable round-trips through toCacheJson (incl id/outlet/group_name)', () {
    final p = PosTable(
      id: 'TBL1',
      name: 'A1',
      capacity: 4,
      statusIndex: 1,
      groupId: 'GRP1',
      outletRemoteId: 'OUTLET123',
      description: 'dekat jendela',
      sortOrder: 3,
      groupName: 'Indoor',
    );
    final back = PosTable.fromJson(_kawat(p.toCacheJson()));
    expect(back.id, p.id);
    expect(back.name, p.name);
    expect(back.capacity, p.capacity);
    expect(back.statusIndex, p.statusIndex);
    expect(back.groupId, p.groupId);
    expect(back.outletRemoteId, p.outletRemoteId);
    expect(back.description, p.description);
    expect(back.sortOrder, p.sortOrder);
    expect(back.groupName, p.groupName);
  });

  test('TableGroup round-trips through toCacheJson', () {
    final g = TableGroup(
      id: 'GRP1',
      name: 'Indoor',
      order: 2,
      outletRemoteId: 'OUTLET123',
    );
    final back = TableGroup.fromJson(_kawat(g.toCacheJson()));
    expect(back.id, g.id);
    expect(back.name, g.name);
    expect(back.order, g.order);
    expect(back.outletRemoteId, g.outletRemoteId);
  });

  test('Shift round-trips through toCacheJson (full, not the 3-field toJson)', () {
    final s = Shift(
      remoteId: 'SH1',
      startTime: DateTime.parse('2026-06-21T01:00:00.000Z'),
      startingCash: 500000,
      totalSales: 1250000,
      cashierName: 'Budi',
      cashierRemoteId: 'USER1',
      outletRemoteId: 'OUTLET123',
      openingNotes: 'buka pagi',
      isOpen: true,
    );
    final back = Shift.fromJson(_kawat(s.toCacheJson()));
    expect(back.remoteId, s.remoteId);
    expect(back.startTime, s.startTime);
    expect(back.startingCash, s.startingCash);
    expect(back.totalSales, s.totalSales);
    expect(back.cashierName, s.cashierName);
    expect(back.cashierRemoteId, s.cashierRemoteId);
    expect(back.outletRemoteId, s.outletRemoteId);
    expect(back.openingNotes, s.openingNotes);
    expect(back.isOpen, s.isOpen); // would be false if status weren't cached
  });

  // ── Product ────────────────────────────────────────────────────────────────
  //
  // Product tak pernah ikut diuji di berkas ini padahal ia isi cache yang
  // paling sering dibaca: tiap ketukan di layar kasir. Ia juga yang paling
  // rawan, karena Product.fromJson sengaja FAIL-OPEN — dua puluh field punya
  // nilai cadangan (`?? true`, `?? ''`, `?? 0`).
  //
  // Akibatnya ada syarat keras untuk fixture di bawah: nilainya harus BUKAN
  // nilai default. Produk dengan isTaxable:true, isInStock:true, oosReason:''
  // akan tetap lulus walaupun ketiga kunci itu hilang sama sekali dari
  // toJson — tesnya hijau sambil menjaga apa pun. Dibuktikan: menghapus
  // 'is_taxable' dari peta membuat isTaxable false berubah jadi true, dan itu
  // hanya terlihat karena fixture-nya memakai false.
  group('Product lewat cache', () {
    Product produkPenuh() => Product(
          remoteId: 'P1',
          name: 'Kopi Susu',
          description: 'gula aren',
          price: 25000,
          stock: 7,
          lowStockThreshold: 3,
          stockUnit: 'gelas',
          sold: 12,
          categoryName: 'Minuman',
          categoryId: 'C1',
          sku: 'SKU-1',
          barcode: 'BAR-1',
          emoji: '☕',
          imageUrl: 'https://contoh/x.png',
          isAvailable: false,
          trackStock: false,
          availablePortions: 5,
          isInStock: false,
          isLowStock: true,
          manualOutOfStock: true,
          oosReason: 'manual',
          isTaxable: false,
          discountType: 'percent',
          discountValue: 15,
          discountName: 'Promo Sore',
          outletRemoteId: 'O1',
          isFavorite: true,
          variants: [
            ProductVariant(
              remoteId: 'V1',
              productId: 'P1',
              name: 'Large',
              sku: 'SKU-V1',
              price: 30000,
              stock: 4,
              discountType: 'fixed',
              discountValue: 2000,
              discountName: 'Promo Varian',
            ),
          ],
        );

    test('seluruh field bertahan melewati jsonEncode/jsonDecode', () {
      final asli = produkPenuh();
      final back = Product.fromJson(_kawat(asli.toJson()));

      expect(back.remoteId, asli.remoteId);
      expect(back.name, asli.name);
      expect(back.description, asli.description);
      expect(back.price, asli.price);
      expect(back.stock, asli.stock);
      expect(back.lowStockThreshold, asli.lowStockThreshold);
      expect(back.stockUnit, asli.stockUnit);
      expect(back.sold, asli.sold);
      expect(back.categoryName, asli.categoryName);
      expect(back.sku, asli.sku);
      expect(back.barcode, asli.barcode);
      expect(back.emoji, asli.emoji);
      expect(back.imageUrl, asli.imageUrl);
      expect(back.isFavorite, asli.isFavorite);
    });

    test('bendera ketersediaan bertahan pada nilai NON-default', () {
      // Justru yang false/true-nya terbalik dari default. Kalau salah satu
      // kunci hilang dari toJson, cadangan fail-open akan mengembalikannya ke
      // nilai default dan produk yang HABIS muncul lagi sebagai tersedia di
      // layar kasir saat offline.
      final back = Product.fromJson(_kawat(produkPenuh().toJson()));

      expect(back.isAvailable, isFalse);
      expect(back.trackStock, isFalse);
      expect(back.isInStock, isFalse);
      expect(back.isLowStock, isTrue);
      expect(back.manualOutOfStock, isTrue);
      expect(back.oosReason, 'manual');
      expect(back.availablePortions, 5);
    });

    test('status pajak & diskon bertahan — keduanya menyentuh uang', () {
      final back = Product.fromJson(_kawat(produkPenuh().toJson()));

      // isTaxable false adalah nilai yang mahal kalau hilang: produk bebas
      // pajak yang kembali jadi kena pajak akan memungut PPN dari pelanggan
      // untuk barang yang semestinya tidak dipungut.
      expect(back.isTaxable, isFalse);
      expect(back.discountType, 'percent');
      expect(back.discountValue, 15);
      expect(back.discountName, 'Promo Sore');
      expect(back.discountedPrice, 21250); // 25.000 − 15%
    });

    test('varian bersarang bertahan lengkap dengan diskonnya', () {
      final back = Product.fromJson(_kawat(produkPenuh().toJson()));

      expect(back.variants, hasLength(1));
      final v = back.variants.first;
      expect(v.remoteId, 'V1');
      expect(v.name, 'Large');
      expect(v.price, 30000);
      expect(v.stock, 4);
      expect(v.discountType, 'fixed');
      expect(v.discountValue, 2000);
      expect(v.discountName, 'Promo Varian');
    });

    test('produk tanpa varian kembali sebagai daftar kosong, bukan null', () {
      final back = Product.fromJson(
        _kawat(Product(name: 'Polos', price: 1000).toJson()),
      );
      expect(back.variants, isEmpty);
    });

    test('kunci yang tak dikenal diabaikan, kunci hilang jatuh ke default', () {
      // Sifat fail-open itu sendiri, dikunci dengan sengaja: cache lama dari
      // versi aplikasi terdahulu harus tetap bisa dibaca, bukan membuat kasir
      // gagal membuka daftar produk. Yang penting defaultnya AMAN — produk
      // dianggap ada dan kena pajak, bukan sebaliknya.
      final back = Product.fromJson(
        _kawat({'id': 'P9', 'name': 'Dari versi lama', 'price': 5000, 'entah': 1}),
      );

      expect(back.remoteId, 'P9');
      expect(back.name, 'Dari versi lama');
      expect(back.price, 5000);
      expect(back.isTaxable, isTrue);
      expect(back.isInStock, isTrue);
      expect(back.discountType, 'none');
      expect(back.variants, isEmpty);
    });
  });
}
