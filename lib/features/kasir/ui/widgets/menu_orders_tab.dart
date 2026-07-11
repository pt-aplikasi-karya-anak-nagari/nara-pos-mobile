import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/app_icons.dart';
import '../../../../core/format.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/realtime/realtime_service.dart';
import '../../../shifts/data/shift_repository.dart';
import '../../../transactions/data/transaction_repository.dart';
import '../../../transactions/domain/sale.dart';
import '../../../transactions/ui/widgets/mini_payment_sheet.dart';
import 'empty_states.dart';

/// Tab "Pesanan Meja" — antrean order dari QR menu (source=menu_qr) yang masih
/// aktif (belum selesai). Dua mode:
///   - Auto-pay QRIS  : pesanan SUDAH lunas → kasir tinggal "Konfirmasi Pesanan".
///   - Open-bill      : pesanan BELUM lunas tapi sudah otomatis dikonfirmasi →
///     tab jalan, ditutup & dibayar di kasir di akhir (badge "Buka tab").
/// Dipakai di cart_panel (tablet) dan cart_sheet (HP).
class MenuOrdersTab extends ConsumerWidget {
  const MenuOrdersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Realtime: begitu ada event pesanan/transaksi dari outlet ini (backend
    // NATS → gateway SSE), segarkan daftar → pesanan QR baru & perubahan
    // status muncul INSTAN. Pull-to-refresh tetap tersedia sebagai fallback.
    ref.listen(realtimeEventsProvider, (prev, next) {
      final ev = next.asData?.value;
      if (ev == null) return;
      if (ev.isOrder || ev.isTransaction) {
        ref.invalidate(menuOrdersProvider);
      }
    });
    // Saat koneksi realtime (re)connect: refetch sekali. Core NATS tak
    // menyimpan event, jadi yang terjadi selama koneksi putus tidak terkirim —
    // sinkron ulang di sini menutup celah data basi.
    ref.listen(realtimeConnectedProvider, (prev, next) {
      if (next && prev != true) ref.invalidate(menuOrdersProvider);
    });

    final ordersAsync = ref.watch(menuOrdersProvider);
    // 🟢 Live — true saat koneksi realtime tersambung (bukan sekadar "pernah
    // terima event"): status di-push oleh RealtimeService via onStatus.
    final rtLive = ref.watch(realtimeConnectedProvider);

    Future<void> refresh() async {
      ref.invalidate(menuOrdersProvider);
      await ref.read(menuOrdersProvider.future);
    }

    final body = ordersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Gagal memuat pesanan meja:\n$e',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kDanger),
                ),
              ),
            ),
          ],
        ),
      ),
      data: (orders) {
        if (orders.isEmpty) {
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              children: const [
                SizedBox(height: 60),
                EmptyState(
                  icon: AppIcons.storefront,
                  title: 'Belum ada pesanan meja',
                  subtitle:
                      'Pesanan QR aktif (belum selesai)\nakan muncul di sini.',
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            separatorBuilder: (_, _) => const Gap(10),
            itemBuilder: (_, i) => _MenuOrderCard(order: orders[i]),
          ),
        );
      },
    );

    if (!rtLive) return body;
    return Column(
      children: [
        const _LiveBadge(),
        Expanded(child: body),
      ],
    );
  }
}

/// Chip "🟢 Live" — tampil hanya saat SSE realtime tersambung. Memberi tahu
/// kasir bahwa pesanan baru akan muncul instan tanpa pull-to-refresh.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 12),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: kSuccess.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: kSuccess.withValues(alpha: 0.4)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: kSuccess),
              Gap(6),
              Text(
                'Live',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kSuccess,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuOrderCard extends ConsumerWidget {
  final Sale order;
  const _MenuOrderCard({required this.order});

  // Pesanan QR sudah lunas (bayar QRIS di depan) → kasir cukup MENGKONFIRMASI.
  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(transactionRepositoryProvider)
          .confirmMenuOrder(order.id);
      ref.invalidate(menuOrdersProvider);
      ref.invalidate(salesFutureProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pesanan ${order.invoiceId} dikonfirmasi'),
            backgroundColor: kSuccess,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal konfirmasi: $e'),
            backgroundColor: kDanger,
          ),
        );
      }
    }
  }

  // Open-bill (bayar di kasir): tutup tab. Buka MiniPaymentSheet yang sama dengan
  // pelunasan transaksi biasa (pilih metode, tunai + kembalian, bukti opsional),
  // lalu markAsPaid. Backend menolak double-settle & butuh shift aktif; poin
  // loyalti diberikan lewat jalur QR yang benar (idempoten).
  Future<void> _settle(BuildContext context, WidgetRef ref) async {
    // Metode & jumlah yang akan dikirim ke markAsPaid.
    String method;
    double cashAmount = 0;
    double changeAmount = 0;
    String? proofUrl;

    final hasProof = (order.paymentProofUrl ?? '').isNotEmpty;
    if (hasProof) {
      // Bukti sudah dilampirkan customer (metode dipilih saat checkout) → kasir
      // cukup MENERIMA. Jangan buka sheet baru yang mengganti metode & membuang
      // bukti aslinya. Konfirmasi ringan supaya tap tak langsung commit.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Terima & Lunaskan?',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Metode: ${order.paymentMethod}\nTotal: ${formatRupiah(order.total)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: kSuccess,
                foregroundColor: Colors.white,
              ),
              child: const Text('Terima & Lunaskan'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      method = order.paymentMethod;
      proofUrl = order.paymentProofUrl;
    } else {
      // Open-bill / tanpa bukti → sheet untuk pilih metode & input tunai.
      final result =
          await showModalBottomSheet<({String method, double cash, String proofUrl})>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => MiniPaymentSheet(total: order.total),
      );
      if (result == null) return;
      method = result.method;
      cashAmount = result.method == 'Tunai' ? result.cash : 0.0;
      changeAmount = (result.method == 'Tunai' && result.cash > order.total)
          ? result.cash - order.total
          : 0.0;
      proofUrl = result.proofUrl.isEmpty ? null : result.proofUrl;
    }
    try {
      await ref.read(transactionRepositoryProvider).markAsPaid(
            order.id,
            paymentMethod: method,
            cashAmount: cashAmount,
            changeAmount: changeAmount,
            paymentProofUrl: proofUrl,
          );
      ref.invalidate(menuOrdersProvider);
      ref.invalidate(salesFutureProvider);
      ref.invalidate(activeShiftProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tab ${order.invoiceId} lunas'),
            backgroundColor: kSuccess,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal melunasi: $e'),
            backgroundColor: kDanger,
          ),
        );
      }
    }
  }

  // Majukan tahap penyelesaian pesanan (received→preparing→delivering→completed).
  Future<void> _advance(
    BuildContext context,
    WidgetRef ref,
    String status,
  ) async {
    try {
      await ref
          .read(transactionRepositoryProvider)
          .setOrderStatus(order.id, status);
      ref.invalidate(menuOrdersProvider);
      ref.invalidate(salesFutureProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status: ${_fulfillmentLabel(status)}'),
            backgroundColor: kSuccess,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal ubah status: $e'),
            backgroundColor: kDanger,
          ),
        );
      }
    }
  }

  void _viewProof(BuildContext context) {
    final url = resolveAssetUrl(order.paymentProofUrl);
    if (url.isEmpty) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          child: Image.network(
            url,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Gagal memuat gambar bukti'),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProof = (order.paymentProofUrl ?? '').isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (order.queueNo != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: kPrimary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#${order.queueNo}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                const Gap(10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.tableDisplay ?? 'Tanpa meja',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${order.customerName.isEmpty ? 'Umum' : order.customerName} · ${order.invoiceId}',
                      style: TextStyle(color: kTextMid, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                formatRupiah(order.total),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: kPrimary,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          // Belum lunas → penanda supaya kasir tak mengira sudah lunas:
          //  - sudah dikonfirmasi = open-bill (tab jalan, tutup di akhir);
          //  - belum dikonfirmasi = pilihan "bayar di kasir" (tagih dulu,
          //    lunasi, baru konfirmasi ke dapur).
          if (!order.isPaid) ...[
            const Gap(8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: kWarning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                order.isConfirmed
                    ? '🧾 Buka tab · bayar di kasir'
                    : '💵 Bayar di kasir · tagih & lunasi dulu',
                style: TextStyle(
                  color: kWarning,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
          // Catatan level-pesanan pelanggan — menonjol (sering berisi alergi).
          if ((order.note ?? '').trim().isNotEmpty) ...[
            const Gap(8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: kWarning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '📝 ${order.note}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
          const Gap(8),
          ...order.items
              .take(4)
              .map(
                (it) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Text(
                        '${it.qty}x ',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          it.productName,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          if (order.items.length > 4)
            Text(
              '+${order.items.length - 4} item lainnya',
              style: TextStyle(color: kTextMid, fontSize: 11),
            ),
          const Gap(10),
          if (hasProof)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.receipt_long, size: 14, color: kSuccess),
                  const Gap(6),
                  Text(
                    'Bukti bayar terlampir',
                    style: TextStyle(
                      color: kSuccess,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _viewProof(context),
                    child: const Text('Lihat'),
                  ),
                ],
              ),
            ),
          if (!order.isConfirmed && !order.isPaid)
            // Pilihan "bayar di kasir": lunasi dulu (backend menolak konfirmasi
            // pesanan yang belum lunas). Setelah lunas → tombol Konfirmasi muncul.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _settle(context, ref),
                icon: const Icon(Icons.payments_outlined, size: 16),
                label: const Text(
                  'Tandai Lunas',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kSuccess,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            )
          else if (!order.isConfirmed)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _confirm(context, ref),
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text(
                  'Konfirmasi Pesanan',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kSuccess,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            )
          else ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _fulfillmentLabel(order.fulfillmentStatus),
                    style: const TextStyle(
                      color: kPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                if (_nextFulfillment(order.fulfillmentStatus) != null)
                  ElevatedButton(
                    onPressed: () => _advance(
                      context,
                      ref,
                      _nextFulfillment(order.fulfillmentStatus)!.status,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      '${_nextFulfillment(order.fulfillmentStatus)!.label} →',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            // Open-bill: tombol tutup tab (bayar di kasir). Hanya untuk pesanan
            // yang belum lunas; pesanan auto-pay QRIS sudah lunas jadi tak tampil.
            if (!order.isPaid) ...[
              const Gap(8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _settle(context, ref),
                  icon: const Icon(Icons.payments_outlined, size: 16),
                  label: const Text(
                    'Tandai Lunas',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kSuccess,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// Label + tahap berikutnya untuk kontrol status kasir (pesanan QR).
String _fulfillmentLabel(String s) {
  switch (s) {
    case 'received':
      return 'Diterima';
    case 'preparing':
      return 'Dipersiapkan';
    case 'delivering':
      return 'Diantar ke meja';
    case 'completed':
      return 'Selesai';
    default:
      return 'Belum dikonfirmasi';
  }
}

({String status, String label})? _nextFulfillment(String s) {
  switch (s) {
    case 'received':
      return (status: 'preparing', label: 'Mulai persiapan');
    case 'preparing':
      return (status: 'delivering', label: 'Antar ke meja');
    case 'delivering':
      return (status: 'completed', label: 'Selesaikan');
    default:
      return null;
  }
}
