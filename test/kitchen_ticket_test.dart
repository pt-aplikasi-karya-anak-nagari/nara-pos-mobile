import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nara_pos_mobile/features/printer/data/printer_service.dart';

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
    // PrinterService butuh Ref, tapi buildKitchenTicket murni (tak baca provider).
    final container = ProviderContainer();
    addTearDown(container.dispose);
    service = container.read(printerServiceProvider);
  });

  group('buildKitchenTicket (golden byte-level)', () {
    test('memuat init/reset, judul, item, dan cut — TANPA harga/total', () {
      final bytes = service.buildKitchenTicket(
        gen,
        title: kKitchenTicketTitle,
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
      expect(
        _contains(bytes, _ascii(kKitchenTicketTitle)),
        isTrue,
        reason: 'judul tiket',
      );
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
      final bytes = service.buildKitchenTicket(
        gen,
        title: kKitchenTicketTitle,
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
}
