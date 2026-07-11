import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/printer/domain/print_station.dart';

// Item uji ringkas: nama + kategori.
class _Item {
  final String name;
  final String? categoryId;
  const _Item(this.name, this.categoryId);
}

PrintStation _station(
  String name, {
  List<String> categories = const [],
  bool active = true,
}) => PrintStation(
  id: name,
  outletId: 'O1',
  name: name,
  categoryIds: categories,
  isActive: active,
);

void main() {
  const kopi = _Item('Kopi', 'CAT_MINUM');
  const teh = _Item('Teh', 'CAT_MINUM');
  const nasi = _Item('Nasi Goreng', 'CAT_MAKAN');
  const rokok = _Item('Rokok', 'CAT_LAIN');
  final items = [kopi, teh, nasi, rokok];

  String? catOf(_Item i) => i.categoryId;

  group('groupItemsByStation', () {
    test('tanpa stasiun → satu grup Lainnya berisi semua item', () {
      final groups = groupItemsByStation<_Item>(
        items: items,
        stations: const [],
        categoryOf: catOf,
      );
      expect(groups.length, 1);
      expect(groups.first.station, isNull);
      expect(groups.first.items.length, 4);
    });

    test('routing per kategori: Bar dapat minuman, Dapur dapat makanan', () {
      final bar = _station('Bar', categories: ['CAT_MINUM']);
      final dapur = _station('Dapur', categories: ['CAT_MAKAN']);
      final groups = groupItemsByStation<_Item>(
        items: items,
        stations: [bar, dapur],
        categoryOf: catOf,
      );
      // Bar (kopi, teh), Dapur (nasi), Lainnya (rokok — tak terutekan).
      expect(groups.length, 3);
      expect(groups[0].label, 'Bar');
      expect(groups[0].items.map((e) => e.name), ['Kopi', 'Teh']);
      expect(groups[1].label, 'Dapur');
      expect(groups[1].items.map((e) => e.name), ['Nasi Goreng']);
      expect(groups.last.station, isNull); // bucket Lainnya
      expect(groups.last.items.single.name, 'Rokok');
    });

    test('stasiun tanpa filter kategori menerima semua item', () {
      final semua = _station('Kasir', categories: const []);
      final groups = groupItemsByStation<_Item>(
        items: items,
        stations: [semua],
        categoryOf: catOf,
      );
      expect(groups.length, 1);
      expect(groups.single.items.length, 4);
      expect(groups.single.label, 'Kasir');
    });

    test('stasiun nonaktif diabaikan', () {
      final bar = _station('Bar', categories: ['CAT_MINUM'], active: false);
      final groups = groupItemsByStation<_Item>(
        items: [kopi],
        stations: [bar],
        categoryOf: catOf,
      );
      // Bar nonaktif → tak ada stasiun aktif → semua ke Lainnya.
      expect(groups.length, 1);
      expect(groups.single.station, isNull);
    });

    test('tidak ada item yang hilang: setiap item muncul di hasil', () {
      final bar = _station('Bar', categories: ['CAT_MINUM']);
      final groups = groupItemsByStation<_Item>(
        items: items,
        stations: [bar],
        categoryOf: catOf,
      );
      final flat = groups.expand((g) => g.items).map((e) => e.name).toSet();
      expect(flat, {'Kopi', 'Teh', 'Nasi Goreng', 'Rokok'});
    });
  });
}
