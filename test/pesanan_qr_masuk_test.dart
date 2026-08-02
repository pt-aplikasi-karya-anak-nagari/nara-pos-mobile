import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/core/notifications.dart';
import 'package:nara_pos_mobile/core/realtime/realtime_service.dart';

// Pesanan lewat QR meja → kasir dibunyikan dan struk tercetak sendiri.
//
// # JALURNYA ADA DUA, DAN ITU DISENGAJA
//
// FCM sendirian tidak cukup andal untuk kasir:
//
//   * Penghemat baterai Android — Doze, ditambah "optimasi baterai" bawaan
//     Xiaomi/Oppo/Vivo yang jauh lebih agresif — menunda atau membuang pesan
//     FCM untuk aplikasi yang dianggapnya tidak penting. Tundaannya menit.
//   * Banyak tablet POS murah tidak punya Google Play Services sama sekali.
//     Di perangkat itu FCM tak pernah sampai, sekali pun.
//
// Backend sudah menyiarkan `order.created` lewat SSE sejak awal, dan
// RealtimeService untuk membacanya sudah ada di aplikasi — tapi tak ada yang
// berlangganan, jadi providernya (autoDispose) bahkan tak pernah dibuat.
// Menyambungkannya memberi jalur kedua yang justru lebih cepat pada keadaan
// normal: tablet menyala di meja dengan aplikasi terbuka.
//
// # HARGA DARI DUA JALUR
//
// Satu pesanan kini tiba DUA KALI. Yang tak boleh dobel bukan pesannya,
// melainkan akibatnya: dua banner, dua baris inbox, dan — yang paling terlihat
// pelanggan — dua struk keluar dari printer untuk satu pesanan.

RealtimeEvent ev(String type, Map<String, dynamic> data) =>
    RealtimeEvent(id: 'e1', type: type, outletId: 'OUT', data: data);

Map<String, dynamic> pesananQr({
  String id = 'TRX-1',
  String invoice = 'INV-1',
  num nominal = 50000,
  String source = 'menu_qr',
}) => {
  'id': id,
  'invoice_no': invoice,
  'final_amount': nominal,
  'source': source,
};

void main() {
  group('menyaring event realtime', () {
    test('pesanan QR baru dikenali beserta angkanya', () {
      final p = bacaPesananQrBaru(ev('order.created', pesananQr()));
      expect(p, isNotNull);
      expect(p!.orderId, 'TRX-1');
      expect(p.invoiceNo, 'INV-1');
      expect(p.nominal, 50000);
    });

    test('transaksi buatan KASIR SENDIRI tidak ikut tercetak', () {
      // Kanal ini juga membawa transaksi yang dibuat kasir di aplikasi. Tanpa
      // saringan source, tiap kali kasir menyelesaikan transaksi ia akan
      // mendapat struk KEDUA yang tercetak sendiri — untuk pesanan yang baru
      // saja ia cetak.
      expect(
        bacaPesananQrBaru(ev('order.created', pesananQr(source: 'kasir'))),
        isNull,
      );
    });

    test('kejadian lain di outlet tidak menyalakan printer', () {
      // Kanal yang sama membawa pembayaran, retur, perubahan status, stok
      // menipis. Tanpa saringan type, printer menyala untuk hampir setiap
      // kejadian di outlet sepanjang hari.
      for (final t in [
        'order.paid',
        'transaction.created',
        'inventory.low_stock',
        'order.updated',
      ]) {
        expect(
          bacaPesananQrBaru(ev(t, pesananQr())),
          isNull,
          reason: '$t ikut memicu cetak',
        );
      }
    });

    test('event tanpa id diabaikan', () {
      // Tanpa id, detail pesanan tak bisa diambil DAN kembarannya lewat FCM
      // tak bisa dikenali — jadi justru berakhir dua struk.
      expect(bacaPesananQrBaru(ev('order.created', pesananQr(id: ''))), isNull);
    });

    test('nominal yang hilang tidak menggagalkan pesanannya', () {
      final p = bacaPesananQrBaru(
        ev('order.created', {'id': 'TRX-9', 'source': 'menu_qr'}),
      );
      expect(p, isNotNull);
      expect(p!.nominal, 0);
      expect(p.invoiceNo, '');
    });
  });

  group('kembaran FCM & realtime', () {
    test('pesanan yang sama hanya ditangani SEKALI', () {
      final sudah = <String>{};
      final data = {'type': 'new_menu_order', 'order_id': 'TRX-1'};

      expect(klaimPesananBaru(sudah, data), isTrue, reason: 'yang pertama');
      expect(
        klaimPesananBaru(sudah, data),
        isFalse,
        reason:
            'kembarannya lolos — dua banner, dua baris inbox, dan dua '
            'struk keluar untuk satu pesanan',
      );
    });

    test('pesanan BERBEDA tetap masing-masing ditangani', () {
      // Sisi yang membuat dedup ini tidak berubah jadi bencana: dedup yang
      // terlalu rakus akan membungkam pesanan kedua pelanggan berikutnya.
      final sudah = <String>{};
      expect(
        klaimPesananBaru(sudah, {
          'type': 'new_menu_order',
          'order_id': 'TRX-1',
        }),
        isTrue,
      );
      expect(
        klaimPesananBaru(sudah, {
          'type': 'new_menu_order',
          'order_id': 'TRX-2',
        }),
        isTrue,
      );
    });

    test('order_updated BOLEH berulang untuk pesanan yang sama', () {
      // Status satu pesanan berubah beberapa kali — dikonfirmasi, disiapkan,
      // selesai — dan tiap perubahan layak diberitahukan. Dedup yang tak
      // dibatasi tipe akan membungkam semuanya kecuali yang pertama.
      final sudah = <String>{};
      final data = {'type': 'order_updated', 'order_id': 'TRX-1'};
      expect(klaimPesananBaru(sudah, data), isTrue);
      expect(
        klaimPesananBaru(sudah, data),
        isTrue,
        reason: 'pemberitahuan perubahan status kedua ikut terbungkam',
      );
    });

    test('tanpa order_id tetap diloloskan', () {
      // Tak ada yang bisa dibandingkan. Membungkamnya berarti membuang
      // pemberitahuan yang mungkin sah.
      final sudah = <String>{};
      final data = {'type': 'new_menu_order'};
      expect(klaimPesananBaru(sudah, data), isTrue);
      expect(klaimPesananBaru(sudah, data), isTrue);
    });
  });
}
