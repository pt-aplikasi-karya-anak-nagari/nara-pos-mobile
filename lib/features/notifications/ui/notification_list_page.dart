import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/app_routes.dart';
import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/responsive.dart';
import '../../transactions/ui/transaction_detail_page.dart';
import '../data/notification_history.dart';
import '../domain/app_notification.dart';

/// Halaman inbox notifikasi (FCM + lokal). Layout-nya **responsive**:
///
///   * **Mobile / phone**: full-width list standar. Tap item → push ke
///     halaman detail transaksi (kalau notif punya `orderId`).
///
///   * **Tablet / landscape lebar**: layout master-detail ala WhatsApp.
///     Kolom kiri (340–420 px) = list, kolom kanan = detail transaksi
///     embedded. Item yang sedang dipilih di-highlight. Tidak ada
///     navigasi push — tap di list cuma update selection state.
class NotificationListPage extends HookConsumerWidget {
  const NotificationListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationHistoryProvider);
    final isTablet = context.isTablet;
    // Selected ID untuk mode tablet. Mobile tidak pakai — selalu push detail.
    final selectedId = useState<String?>(null);

    // Auto-select notif pertama yang masih punya orderId di tablet supaya
    // panel kanan tidak kosong (better UX, sama seperti WhatsApp yang
    // tidak menampilkan blank right pane saat ada chat).
    useEffect(() {
      if (!isTablet) return null;
      if (selectedId.value != null) return null;
      final first = items.firstWhere(
        (e) => (e.orderId ?? '').isNotEmpty,
        orElse: () => const AppNotification(
          id: '',
          title: '',
          body: '',
          receivedAt: _epoch,
        ),
      );
      if (first.id.isNotEmpty) {
        selectedId.value = first.orderId;
      }
      return null;
    }, [isTablet, items.length]);

    final list = _ListPanel(
      items: items,
      isTablet: isTablet,
      selectedOrderId: selectedId.value,
      onTap: (item) {
        ref.read(notificationHistoryProvider.notifier).markRead(item.id);
        final orderId = item.orderId;
        if (orderId == null || orderId.isEmpty) return;
        if (isTablet) {
          selectedId.value = orderId;
        } else {
          context.pushNamed(
            AppRoutes.riwayatDetailName,
            pathParameters: {'id': orderId},
          );
        }
      },
      onRemove: (id) {
        // Kalau item yang dihapus sedang dipilih → reset selection.
        if (selectedId.value == _orderIdById(items, id)) {
          selectedId.value = null;
        }
        ref.read(notificationHistoryProvider.notifier).remove(id);
      },
    );

    if (!isTablet) {
      // Mobile: shell-less, sama dengan RiwayatPage — Scaffold transparent
      // supaya background gradient dari ShellPage tetap kelihatan.
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(child: list),
      );
    }

    // Tablet: master-detail dengan shell rounded persis seperti RiwayatPage
    // (white container, margin 16, ClipRRect 32) supaya konsisten antar
    // halaman utama.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
          ),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: context.responsive<double>(
                    compact: 340,
                    medium: 360,
                    expanded: 380,
                    large: 420,
                  ),
                  child: Container(color: kBg, child: list),
                ),
                VerticalDivider(width: 1, color: kDivider),
                Expanded(
                  child: selectedId.value == null
                      ? Container(color: Colors.white, child: const _EmptyDetailPane())
                      : TransactionDetailPage(
                          // Re-key supaya saat user pindah selection,
                          // halaman detail rebuild fresh (initState refetch).
                          key: ValueKey(selectedId.value),
                          saleId: selectedId.value!,
                          embedded: true,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sentinel `DateTime` untuk fallback `firstWhere.orElse` di useEffect.
/// Pakai const supaya identity-comparable & tidak alocate object baru
/// di setiap rebuild.
const _epoch = _ConstDateTime(0);

/// Wrapper untuk DateTime karena DateTime tidak punya const constructor.
class _ConstDateTime implements DateTime {
  final int _ms;
  const _ConstDateTime(this._ms);
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #millisecondsSinceEpoch) return _ms;
    return super.noSuchMethod(invocation);
  }
}

String? _orderIdById(List<AppNotification> items, String id) {
  for (final e in items) {
    if (e.id == id) return e.orderId;
  }
  return null;
}

/// Header + list scroll. Dipisah jadi widget supaya bisa dipakai sebagai
/// child di mobile (full-width) atau master pane di tablet (340–420 px).
class _ListPanel extends ConsumerWidget {
  final List<AppNotification> items;
  final bool isTablet;
  final String? selectedOrderId;
  final void Function(AppNotification) onTap;
  final void Function(String id) onRemove;

  const _ListPanel({
    required this.items,
    required this.isTablet,
    required this.selectedOrderId,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = items.where((e) => !e.read).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          isTablet: isTablet,
          unread: unread,
          hasItems: items.isNotEmpty,
          onMarkAllRead: () =>
              ref.read(notificationHistoryProvider.notifier).markAllRead(),
          onClearAll: () async {
            final ok = await _confirmClearAll(context);
            if (ok != true) return;
            ref.read(notificationHistoryProvider.notifier).clearAll();
          },
        ),
        if (isTablet) Divider(height: 1, color: kDivider) else const Gap(8),
        Expanded(
          child: items.isEmpty
              ? const _EmptyListState()
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Gap(10),
                  itemBuilder: (context, idx) {
                    final item = items[idx];
                    final isSelected =
                        isTablet &&
                        selectedOrderId != null &&
                        selectedOrderId == item.orderId;
                    return _NotifTile(
                      item: item,
                      selected: isSelected,
                      onTap: () => onTap(item),
                      onDelete: () => onRemove(item.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<bool?> _confirmClearAll(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus semua notifikasi?'),
        content: Text(
          'Riwayat inbox di perangkat ini akan dikosongkan. Data transaksi '
          'di server tidak ikut terhapus.',
          style: TextStyle(color: kTextMid),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: kDanger),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}

/// Header bar dengan title besar (ala RiwayatPage) + subtitle counter
/// unread + aksi global (mark all read, clear all). Padding & ukuran
/// font disinkronkan dengan riwayat supaya konsisten antar halaman utama.
class _Header extends StatelessWidget {
  final bool isTablet;
  final int unread;
  final bool hasItems;
  final VoidCallback onMarkAllRead;
  final VoidCallback onClearAll;
  const _Header({
    required this.isTablet,
    required this.unread,
    required this.hasItems,
    required this.onMarkAllRead,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(20, isTablet ? 24 : 16, 12, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifikasi',
                  style: TextStyle(
                    fontSize: isTablet ? 24 : 18,
                    fontWeight: isTablet ? FontWeight.w800 : FontWeight.w700,
                    color: kTextDark,
                  ),
                ),
                if (hasItems) ...[
                  const Gap(4),
                  Text(
                    unread == 0 ? 'Semua sudah dibaca' : '$unread belum dibaca',
                    style: TextStyle(fontSize: 12, color: kTextMid),
                  ),
                ],
              ],
            ),
          ),
          if (unread > 0)
            IconButton(
              tooltip: 'Tandai semua dibaca',
              icon: Icon(Icons.done_all, color: kPrimary),
              onPressed: onMarkAllRead,
            ),
          if (hasItems)
            PopupMenuButton<_HeaderAction>(
              tooltip: 'Lainnya',
              icon: Icon(Icons.more_vert, color: kTextMid),
              onSelected: (action) {
                switch (action) {
                  case _HeaderAction.clearAll:
                    onClearAll();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _HeaderAction.clearAll,
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep_outlined, color: kDanger),
                      Gap(8),
                      Text('Hapus semua'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

enum _HeaderAction { clearAll }

class _NotifTile extends StatelessWidget {
  final AppNotification item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotifTile({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isUnread = !item.read;
    final accent = _accentFor(item.type);

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: kDanger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.delete_outline, color: kDanger),
      ),
      onDismissed: (_) => onDelete(),
      // Pola kartu sama dengan _SaleTile di RiwayatPage: kCard background,
      // radius 14, padding 16, transparent border default → primary border
      // saat dipilih (tablet), dengan boxShadow halus.
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(14),
            border: selected
                ? Border.all(color: kPrimary, width: 1.5)
                : Border.all(color: Colors.transparent, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: selected ? 0.06 : 0.04),
                blurRadius: selected ? 12 : 8,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar bulat ala WhatsApp.
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(_iconFor(item.type), color: accent, size: 20),
              ),
              const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Baris atas: title (1 line, bold kalau unread) +
                      // time relative kanan-atas (ala WhatsApp).
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontWeight: isUnread
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: kTextDark,
                                fontSize: 14,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Gap(8),
                          Text(
                            _formatRelative(item.receivedAt),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isUnread ? accent : kTextMid,
                            ),
                          ),
                        ],
                      ),
                      const Gap(2),
                      // Baris bawah: body snippet + dot unread di kanan.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.body.isEmpty
                                  ? (item.invoiceNo ?? '')
                                  : item.body,
                              style: TextStyle(
                                color: isUnread ? kTextDark : kTextMid,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isUnread) ...[
                            const Gap(8),
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (item.invoiceNo != null &&
                          item.invoiceNo!.isNotEmpty &&
                          item.body.isNotEmpty) ...[
                        const Gap(4),
                        Text(
                          item.invoiceNo!,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: kTextLight,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }

  Color _accentFor(String? type) {
    switch (type) {
      case 'new_menu_order':
        return kPrimary;
      case 'order_updated':
        return kSuccess;
      case 'proof_uploaded':
        // Bukti pembayaran masuk — biru (kSecondary kalau ada, fallback
        // kPrimary). Beda visual dari new_menu_order supaya kasir tahu
        // ini *update* bukan order baru.
        return kAccent;
      default:
        return kTextMid;
    }
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'new_menu_order':
        return Icons.qr_code_scanner_rounded;
      case 'order_updated':
        return Icons.check_circle_rounded;
      case 'proof_uploaded':
        return Icons.receipt_long_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  /// Relative time singkat: hari ini → "HH:mm", < 7 hari → nama hari pendek,
  /// > 7 hari → "dd/MM". Match dengan format chat list WhatsApp.
  String _formatRelative(DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final whenDay = DateTime(when.year, when.month, when.day);
    final daysAgo = today.difference(whenDay).inDays;

    if (daysAgo == 0) {
      // Today → tampilkan jam, ala chat aplikasi.
      final hh = when.hour.toString().padLeft(2, '0');
      final mm = when.minute.toString().padLeft(2, '0');
      return '$hh.$mm';
    }
    if (daysAgo == 1) return 'Kemarin';
    if (daysAgo < 7) {
      const names = ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'];
      return names[when.weekday % 7];
    }
    final dd = when.day.toString().padLeft(2, '0');
    final mm = when.month.toString().padLeft(2, '0');
    return '$dd/$mm';
  }
}

class _EmptyListState extends StatelessWidget {
  const _EmptyListState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: HugeIcon(
                icon: AppIcons.notification,
                color: kPrimary,
                size: 44,
              ),
            ),
            const Gap(16),
            Text(
              'Belum ada notifikasi',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: kTextDark,
                fontSize: 16,
              ),
            ),
            const Gap(6),
            Text(
              'Pesanan baru dari QR menu akan muncul di sini.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: kTextMid, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Right pane untuk tablet saat belum ada notif yang dipilih. Ala
/// "Select a chat to start messaging" di WhatsApp Web/Desktop.
class _EmptyDetailPane extends StatelessWidget {
  const _EmptyDetailPane();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: HugeIcon(
                icon: AppIcons.notification,
                color: kPrimary.withValues(alpha: 0.7),
                size: 56,
              ),
            ),
            const Gap(20),
            Text(
              'Pilih notifikasi',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: kTextDark,
              ),
            ),
            const Gap(8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                'Tap salah satu notifikasi di kiri untuk lihat rincian transaksinya di sini.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextMid, fontSize: 13, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
