import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/transactions/data/transaction_repository.dart';
import 'package:nara_pos_mobile/features/transactions/domain/sale.dart';

// Antrean "Pesanan dari Scan Meja": apa yang layak disebut PEKERJAAN kasir.
//
// # KEJADIANNYA
//
// Pelanggan membatalkan pesanannya dari halaman menu QR — sah, sebelum dibayar
// dan sebelum masuk dapur. Backend menyetel payment_status='cancelled' dan
// mengembalikan stoknya.
//
// Tapi pesanan itu tetap nongkrong di antrean kasir. Kasir menekan "Tandai
// Lunas", dan barulah backend menolak: "transaksi sudah cancelled — tidak bisa
// ditandai lunas". Penjaga terakhirnya bekerja; yang bocor adalah daftar yang
// menampilkannya sebagai pekerjaan yang belum selesai.
//
// # KENAPA BOCORNYA HALUS
//
// Cabang ketiga saringan ini — "belum bayar, belum dikonfirmasi, tanpa
// paymentRef" — dirancang untuk pesanan "bayar di kasir". Pesanan yang sudah
// DIBATALKAN memenuhi ketiganya juga. Tak ada satu pun syarat yang tampak
// salah kalau dibaca sendiri-sendiri.
//
// Ongkosnya bukan cuma pesan merah: di kafe ramai, pesanan yang benar-benar
// perlu ditangani tenggelam di antara pesanan hantu yang tak bisa diapa-apakan.

Sale pesanan({
  String status = 'unpaid',
  bool lunas = false,
  DateTime? dikonfirmasi,
  String fulfillment = 'pending',
  bool diretur = false,
  String? paymentRef,
}) {
  return Sale(
    id: 'TRX-1',
    createdAt: DateTime(2026, 8, 3),
    subtotal: 11000,
    tax: 0,
    total: 11000,
    paymentMethod: 'QRIS',
    paymentStatus: status,
    isPaid: lunas,
    confirmedAt: dikonfirmasi,
    fulfillmentStatus: fulfillment,
    isRefunded: diretur,
    paymentRef: paymentRef,
    source: 'menu_qr',
  );
}

void main() {
  group('pesanan MATI tidak muncul sebagai pekerjaan', () {
    test('DIBATALKAN pelanggan — bug yang dilaporkan', () {
      expect(
        pesananMejaPerluDitangani(pesanan(status: 'cancelled')),
        isFalse,
        reason:
            'pesanan yang dibatalkan pelanggan masih masuk antrean — kasir '
            'menekan "Tandai Lunas" lalu ditolak backend, dan pesanan yang '
            'sungguh perlu ditangani tenggelam di antaranya',
      );
    });

    test('dibatalkan TAPI sempat dikonfirmasi kasir juga tak muncul', () {
      // Perlombaan nyata: kasir mengonfirmasi hampir bersamaan dengan
      // pelanggan membatalkan. Status akhir yang menentukan, bukan jejaknya.
      expect(
        pesananMejaPerluDitangani(
          pesanan(status: 'cancelled', dikonfirmasi: DateTime(2026, 8, 3)),
        ),
        isFalse,
      );
    });

    test('sudah selesai', () {
      expect(
        pesananMejaPerluDitangani(pesanan(fulfillment: 'completed')),
        isFalse,
      );
    });

    test('sudah diretur', () {
      expect(
        pesananMejaPerluDitangani(pesanan(status: 'refunded', diretur: true)),
        isFalse,
      );
    });
  });

  group('pesanan HIDUP tetap muncul', () {
    test('bayar di kasir: belum lunas, tanpa paymentRef', () {
      // Sisi yang membuat saringan ini ada. Ikut menyaringnya berarti pesanan
      // "bayar di kasir" tak pernah sampai ke kasir sama sekali.
      expect(pesananMejaPerluDitangani(pesanan()), isTrue);
    });

    test('sudah lunas lewat QRIS, menunggu dikonfirmasi', () {
      expect(
        pesananMejaPerluDitangani(pesanan(status: 'paid', lunas: true)),
        isTrue,
      );
    });

    test('open-bill: belum lunas tapi sudah dikonfirmasi & masuk dapur', () {
      expect(
        pesananMejaPerluDitangani(
          pesanan(dikonfirmasi: DateTime(2026, 8, 3), fulfillment: 'preparing'),
        ),
        isTrue,
      );
    });

    test('lunas tapi belum selesai tetap dikerjakan', () {
      expect(
        pesananMejaPerluDitangani(
          pesanan(status: 'paid', lunas: true, fulfillment: 'delivering'),
        ),
        isTrue,
      );
    });
  });

  test('menunggu QRIS (punya paymentRef) disembunyikan', () {
    // Belum ada yang perlu dikerjakan kasir; pelanggan masih di halaman bayar.
    expect(pesananMejaPerluDitangani(pesanan(paymentRef: 'CHG-123')), isFalse);
  });
}
