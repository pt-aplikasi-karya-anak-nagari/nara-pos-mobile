import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/offline/offline_sync_service.dart';
import '../../../core/offline/sale_outbox.dart';
import '../../../core/outlet_scope.dart';
import '../domain/sale.dart';
import '../domain/sale_item.dart';

/// Transaksi offline yang belum sampai ke server, dalam bentuk [Sale] supaya
/// bisa tampil di Riwayat dan dicetak ulang struknya.
///
/// Sumbernya baris antrian (pending_sales): payload checkout + `struk_lokal`,
/// yaitu data struk yang tak dikirim ke server (nama kasir, nama varian,
/// label add-on, dst.) dan disimpan saat transaksinya diantrekan. Transaksi
/// yang diantrekan sebelum `struk_lokal` ada tetap tampil, hanya rinciannya
/// lebih sedikit.
Sale saleDariAntrian(PendingSale ps, {bool gagal = false}) {
  final p = ps.payload;
  final struk = p['struk_lokal'] is Map
      ? Map<String, dynamic>.from(p['struk_lokal'] as Map)
      : const <String, dynamic>{};
  final itemStruk = struk['items'] is List ? struk['items'] as List : const [];

  double angka(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  int bulat(Object? v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  String teks(Object? v) => v?.toString() ?? '';

  final waktu =
      DateTime.tryParse(teks(p['occurred_at']))?.toLocal() ?? ps.createdAt;
  final subtotal = angka(p['subtotal_amount']);

  final sale = Sale(
    id: ps.localId,
    createdAt: waktu,
    subtotal: subtotal,
    originalSubtotal: struk.containsKey('original_subtotal')
        ? angka(struk['original_subtotal'])
        : subtotal,
    tax: angka(p['tax_amount']),
    discountTotal: angka(p['discount_amount']),
    serviceCharge: angka(p['service_charge']),
    total: angka(p['final_amount']),
    paymentMethod: teks(p['payment_method']),
    cashAmount: angka(p['cash_amount']),
    changeAmount: angka(p['change_amount']),
    customerName: teks(p['customer_name']),
    orderType: teks(p['order_type']).isEmpty
        ? 'Dine In'
        : teks(p['order_type']),
    invoiceId: teks(p['offline_ref']).isEmpty
        ? 'OFFLINE'
        : teks(p['offline_ref']),
    queueLabel: teks(p['queue_label']).isEmpty ? null : teks(p['queue_label']),
    isPaid: p['is_paid'] != false,
    paymentStatus: p['is_paid'] == false ? 'unpaid' : 'paid',
    cashierRemoteId: teks(p['cashier_id']),
    cashierName: teks(struk['cashier_name']),
    outletRemoteId: ps.outletId,
    outletName: teks(struk['outlet_name']),
    pointsEarned: bulat(struk['points_earned'] ?? p['points_earned']),
    pointsUsed: bulat(p['points_used']),
    tableId: teks(p['table_id']).isEmpty ? null : teks(p['table_id']),
    tableName: teks(struk['table_name']).isEmpty
        ? null
        : teks(struk['table_name']),
    pendingSync: true,
    gagalTerkirim: gagal,
    galatSinkron: ps.lastError,
  );

  final items = p['items'] is List ? p['items'] as List : const [];
  sale.items = [
    for (var i = 0; i < items.length; i++)
      if (items[i] is Map)
        () {
          final it = Map<String, dynamic>.from(items[i] as Map);
          final s = i < itemStruk.length && itemStruk[i] is Map
              ? Map<String, dynamic>.from(itemStruk[i] as Map)
              : const <String, dynamic>{};
          return SaleItem(
            productRemoteId: teks(it['product_id']),
            productName: teks(s['product_name']).isNotEmpty
                ? teks(s['product_name'])
                : teks(it['name']),
            productEmoji: teks(s['emoji']).isEmpty ? '📦' : teks(s['emoji']),
            variant: teks(s['variant']),
            price: angka(it['price']),
            originalPrice: s.containsKey('original_price')
                ? angka(s['original_price'])
                : angka(it['base_price']),
            qty: bulat(it['quantity']),
            note: teks(it['note']),
            modifiersLabel: teks(s['modifiers_label']),
          );
        }(),
  ];
  return sale;
}

/// Transaksi outlet aktif yang belum terkirim (menunggu + gagal), terbaru di
/// atas. Dihitung ulang setiap isi antrian berubah.
final transaksiBelumTerkirimProvider = FutureProvider.autoDispose<List<Sale>>((
  ref,
) async {
  ref.watch(pendingSyncCountProvider);
  ref.watch(deadLetterCountProvider);
  ref.watch(progresSinkronProvider.select((p) => p.diproses));
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null || outletId.isEmpty) return const [];

  final outbox = ref.read(saleOutboxProvider);
  final hasil = [
    for (final ps in await outbox.pending())
      if (ps.outletId == outletId) saleDariAntrian(ps),
    for (final ps in await outbox.deadLetters())
      if (ps.outletId == outletId) saleDariAntrian(ps, gagal: true),
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return hasil;
});

/// Cari satu transaksi offline berdasarkan ID lokalnya. Null bila sudah tak
/// ada di antrian — biasanya karena sudah terkirim ke server.
Future<Sale?> cariTransaksiOffline(SaleOutbox outbox, String localId) async {
  for (final ps in await outbox.pending()) {
    if (ps.localId == localId) return saleDariAntrian(ps);
  }
  for (final ps in await outbox.deadLetters()) {
    if (ps.localId == localId) return saleDariAntrian(ps, gagal: true);
  }
  return null;
}
