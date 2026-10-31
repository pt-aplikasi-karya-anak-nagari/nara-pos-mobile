import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nara_pos_mobile/core/offline/nomor_struk_offline.dart';
import 'package:nara_pos_mobile/features/printer/data/printer_service.dart';
import 'package:nara_pos_mobile/features/transactions/domain/sale.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _memuat(List<int> hay, String teks) {
  final n = teks.codeUnits;
  for (var i = 0; i + n.length <= hay.length; i++) {
    var cocok = true;
    for (var j = 0; j < n.length; j++) {
      if (hay[i + j] != n[j]) {
        cocok = false;
        break;
      }
    }
    if (cocok) return true;
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('nomor antrian offline', () {
    late SharedPreferences prefs;
    var kini = DateTime(2026, 10, 31, 9);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      kini = DateTime(2026, 10, 31, 9);
    });

    NomorAntrianOffline buat({String id = '3fa9c2d1-0000'}) =>
        NomorAntrianOffline(prefs, idPerangkat: () => id, jam: () => kini);

    test('berawalan kode perangkat & berurutan', () async {
      final n = buat();
      expect(await n.berikutnya(), '3FA-1');
      expect(await n.berikutnya(), '3FA-2');
      expect(await n.berikutnya(), '3FA-3');
    });

    test('kembali ke 1 di hari berikutnya', () async {
      final n = buat();
      await n.berikutnya();
      await n.berikutnya();
      kini = DateTime(2026, 11, 1, 0, 5);
      expect(await n.berikutnya(), '3FA-1');
    });

    test('perangkat tanpa ID tetap mendapat nomor', () async {
      expect(await buat(id: '').berikutnya(), 'OFF-1');
    });
  });

  group('nomor antrian pada transaksi', () {
    Sale jual(Map<String, dynamic> isi) =>
        Sale.fromJson({'id': 'TX', 'payment_status': 'paid', ...isi});

    test('nomor tablet (offline) didahulukan, lalu nomor server', () {
      expect(jual({'queue_no': 12}).nomorAntrian, '12');
      expect(jual({'queue_label': '3FA-4'}).nomorAntrian, '3FA-4');
      expect(
        jual({'queue_no': 12, 'queue_label': '3FA-4'}).nomorAntrian,
        '3FA-4',
      );
      expect(jual({}).nomorAntrian, isNull);
      expect(jual({'queue_label': '  '}).nomorAntrian, isNull);
    });

    test('dibaca dari JSON server', () {
      final s = Sale.fromJson({
        'id': 'TX1',
        'queue_no': 7,
        'payment_status': 'paid',
      });
      expect(s.nomorAntrian, '7');
      final o = Sale.fromJson({
        'id': 'TX2',
        'queue_label': '3FA-2',
        'payment_status': 'paid',
      });
      expect(o.nomorAntrian, '3FA-2');
    });
  });

  test('tiket dapur mencetak nomor antrian besar', () async {
    await initializeDateFormatting('id_ID', null);
    final gen = Generator(PaperSize.mm58, await CapabilityProfile.load());
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = container.read(printerServiceProvider);
    List<int> cetak(String? antrian) => service.buildKitchenTicket(
      gen,
      title: kKitchenTicketTitle,
      orderMeta: KitchenOrderMeta(
        orderNo: 'INV-001',
        nomorAntrian: antrian,
        orderType: 'Take Away',
        time: DateTime(2026, 10, 31, 9),
      ),
      items: const [KitchenTicketItem(qty: 1, name: 'Teh')],
    );
    expect(_memuat(cetak('12'), 'ANTRIAN 12'), isTrue);
    expect(_memuat(cetak(null), 'ANTRIAN'), isFalse);
  });
}
