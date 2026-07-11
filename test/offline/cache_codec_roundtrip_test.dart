import 'package:flutter_test/flutter_test.dart';

import 'package:nara_pos_mobile/features/outlet/domain/outlet.dart';
import 'package:nara_pos_mobile/features/products/domain/category.dart';
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
    final back = Outlet.fromJson(o.toCacheJson());
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
    final back = Category.fromJson(c.toCacheJson());
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
    final back = Customer.fromJson(c.toJson());
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
    final back = PaymentMethod.fromJson(m.toCacheJson());
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
    final back = OrderType.fromJson(t.toCacheJson());
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
    final back = PosTable.fromJson(p.toCacheJson());
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
    final back = TableGroup.fromJson(g.toCacheJson());
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
    final back = Shift.fromJson(s.toCacheJson());
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
}
