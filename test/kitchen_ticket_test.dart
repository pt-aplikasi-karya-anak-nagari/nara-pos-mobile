import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nara_pos_mobile/features/printer/data/printer_service.dart';
import 'package:nara_pos_mobile/features/printer/domain/print_station.dart';

// Cari [needle] sebagai sub-urutan kontigu dalam [hay] (pencocokan byte-level).
bool _contains(List<int> hay, List<int> needle) {
  if (needle.isEmpty) return true;
  for (var i = 0; i + needle.length <= hay.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

List<int> _ascii(String s) => s.codeUnits;

// Item uji ringkas untuk routing (nama + kategori).
class _RtItem {
  final String name;
  final String? category;
  const _RtItem(this.name, this.category);
}

void main() {
  // Diperlukan agar rootBundle bisa memuat capabilities.json milik
  // esc_pos_utils_plus saat CapabilityProfile.load().
  TestWidgetsFlutterBinding.ensureInitialized();

  late Generator gen;
  late PrinterService service;

  final meta = KitchenOrderMeta(
    orderNo: 'INV-001',
    tableLabel: 'A1',
    orderType: 'Dine In',
    time: DateTime(2026, 7, 11, 14, 30),
  );

  setUpAll(() async {
    // formatDateTime memakai locale id_ID (via intl) di header tiket.
    await initializeDateFormatting('id_ID', null);
    final profile = await CapabilityProfile.load();
    gen = Generator(PaperSize.mm58, profile);
    // PrinterService butuh Ref, tapi buildStationTicket murni (tak baca provider).
    final container = ProviderContainer();
    addTearDown(container.dispose);
    service = container.read(printerServiceProvider);
  });

  group('buildStationTicket (golden byte-level)', () {
    test('memuat init/reset, nama stasiun, item, dan cut — TANPA harga/total',
        () {
      final bytes = service.buildStationTicket(
        gen,
        stationName: 'BAR',
        orderMeta: meta,
        items: const [
          KitchenTicketItem(
            qty: 2,
            name: 'Kopi Susu',
            variant: 'Large',
            modifiers: ['Boba', 'Less Sugar'],
            note: 'tanpa gula',
          ),
          KitchenTicketItem(qty: 1, name: 'Teh'),
        ],
      );

      expect(bytes, isNotEmpty);

      // ESC @ (init printer) dari gen.reset().
      expect(_contains(bytes, [0x1B, 0x40]), isTrue, reason: 'init ESC @');
      // GS V (potong kertas) dari gen.cut().
      expect(_contains(bytes, [0x1D, 0x56]), isTrue, reason: 'cut GS V');

      // Konten kitchen.
      expect(_contains(bytes, _ascii('BAR')), isTrue, reason: 'nama stasiun');
      expect(_contains(bytes, _ascii('2 x Kopi Susu (Large)')), isTrue);
      expect(_contains(bytes, _ascii('1 x Teh')), isTrue);
      expect(_contains(bytes, _ascii('+ Boba')), isTrue, reason: 'modifier');
      expect(_contains(bytes, _ascii('+ Less Sugar')), isTrue);
      expect(_contains(bytes, _ascii('* tanpa gula')), isTrue, reason: 'note');
      // Meta pesanan.
      expect(_contains(bytes, _ascii('#INV-001')), isTrue);
      expect(_contains(bytes, _ascii('A1')), isTrue, reason: 'meja');
      expect(_contains(bytes, _ascii('Dine In')), isTrue);

      // TIDAK ada harga/total apa pun di tiket dapur.
      expect(_contains(bytes, _ascii('Rp')), isFalse, reason: 'no rupiah');
      expect(_contains(bytes, _ascii('TOTAL')), isFalse);
      expect(_contains(bytes, _ascii('Subtotal')), isFalse);
    });

    test('baris meja disembunyikan bila tableLabel null', () {
      final bytes = service.buildStationTicket(
        gen,
        stationName: 'DAPUR',
        orderMeta: KitchenOrderMeta(
          orderNo: 'INV-002',
          tableLabel: null,
          orderType: 'Take Away',
          time: DateTime(2026, 7, 11, 14, 30),
        ),
        items: const [KitchenTicketItem(qty: 1, name: 'Nasi Goreng')],
      );
      expect(_contains(bytes, _ascii('Take Away')), isTrue);
      // Label kolom "Meja" tidak muncul saat tak ada meja.
      expect(_contains(bytes, _ascii('Meja')), isFalse);
    });
  });

  group('routing → satu tiket per StationGroup', () {
    test('groupItemsByStation menghasilkan satu tiket per grup', () {
      const kopi = _RtItem('Kopi', 'MINUM');
      const teh = _RtItem('Teh', 'MINUM');
      const nasi = _RtItem('Nasi', 'MAKAN');
      final items = [kopi, teh, nasi];

      final bar = PrintStation(
        id: 'bar',
        outletId: 'o',
        name: 'BAR',
        categoryIds: const ['MINUM'],
      );
      final dapur = PrintStation(
        id: 'dapur',
        outletId: 'o',
        name: 'DAPUR',
        categoryIds: const ['MAKAN'],
      );

      final groups = groupItemsByStation<_RtItem>(
        items: items,
        stations: [bar, dapur],
        categoryOf: (i) => i.category,
      );
      expect(groups.length, 2);

      final tickets = groups
          .map(
            (g) => service.buildStationTicket(
              gen,
              stationName: g.label,
              orderMeta: meta,
              items: g.items
                  .map((i) => KitchenTicketItem(qty: 1, name: i.name))
                  .toList(),
            ),
          )
          .toList();

      // Satu tiket per grup.
      expect(tickets.length, groups.length);

      // Tiket BAR berisi minuman, bukan makanan.
      expect(_contains(tickets[0], _ascii('BAR')), isTrue);
      expect(_contains(tickets[0], _ascii('Kopi')), isTrue);
      expect(_contains(tickets[0], _ascii('Teh')), isTrue);
      expect(_contains(tickets[0], _ascii('Nasi')), isFalse);

      // Tiket DAPUR berisi makanan.
      expect(_contains(tickets[1], _ascii('DAPUR')), isTrue);
      expect(_contains(tickets[1], _ascii('Nasi')), isTrue);
      expect(_contains(tickets[1], _ascii('Kopi')), isFalse);
    });

    test('tanpa stasiun → satu grup catch-all "Lainnya" → satu tiket', () {
      const rokok = _RtItem('Rokok', 'LAIN');
      final groups = groupItemsByStation<_RtItem>(
        items: const [rokok],
        stations: const [],
        categoryOf: (i) => i.category,
      );
      expect(groups.length, 1);
      expect(groups.single.station, isNull);
      expect(groups.single.label, 'Lainnya');

      final bytes = service.buildStationTicket(
        gen,
        stationName: groups.single.label,
        orderMeta: meta,
        items: const [KitchenTicketItem(qty: 1, name: 'Rokok')],
      );
      expect(_contains(bytes, _ascii('Lainnya')), isTrue);
      expect(_contains(bytes, _ascii('Rokok')), isTrue);
    });
  });
}
