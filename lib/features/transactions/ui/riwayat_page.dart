import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';
import '../../../app/app_routes.dart';
import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../../core/responsive.dart';
import '../../access_rights/data/access_rights_repository.dart';
import '../../access_rights/domain/permission.dart';
import '../data/transaction_repository.dart';
import '../domain/sale.dart';
import 'transaction_detail_page.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import '../../../core/outlet_scope.dart';

class RiwayatPage extends HookConsumerWidget {
  const RiwayatPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ── Permission gate ──
    if (!ref.hasPermission(Permission.viewHistory)) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: kDanger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: HugeIcon(
                      icon: AppIcons.accessRights,
                      color: kDanger,
                      size: 32,
                    ),
                  ),
                ),
                const Gap(16),
                Text(
                  ref.t('access_rights.no_access'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: kTextDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final query = useState('');
    // '' = semua, atau 'paid' | 'unpaid' | 'refunded' sesuai status backend.
    final statusFilter = useState('');
    final dateFrom = useState<DateTime?>(null);
    final dateTo = useState<DateTime?>(null);
    final selectedId = useState<String?>(null);
    final isTablet = context.isTablet;

    // Format YYYY-MM-DD untuk param date_from/date_to backend (inclusive).
    String? fmtDate(DateTime? d) => d == null ? null : formatIsoDate(d);

    final pagingController = useMemoized(
      () => PagingController<int, Sale>(
        fetchPage: (pageKey) async {
          final outletId = ref.read(activeOutletIdProvider);
          if (outletId == null) return [];
          return await ref
              .read(transactionRepositoryProvider)
              .getPaginatedHistory(
                outletId,
                page: pageKey,
                limit: 10,
                search: query.value,
                status: statusFilter.value,
                dateFrom: fmtDate(dateFrom.value),
                dateTo: fmtDate(dateTo.value),
              );
        },
        getNextPageKey: (state) {
          final lastPage = state.pages?.lastOrNull;
          if (lastPage != null && lastPage.length < 10) {
            return null;
          }
          return (state.keys?.lastOrNull ?? 0) + 1;
        },
      ),
    );

    useEffect(() {
      pagingController.refresh();
      return null;
    }, [query.value, statusFilter.value, dateFrom.value, dateTo.value]);

    final list = _TransactionList(
      pagingController: pagingController,
      selectedId: isTablet ? selectedId.value : null,
      query: query,
      statusFilter: statusFilter,
      dateFrom: dateFrom,
      dateTo: dateTo,
      isTablet: isTablet,
      onTap: (sale) {
        if (isTablet) {
          selectedId.value = sale.id;
        } else {
          context.push(
            AppRoutes.riwayatDetail.replaceAll(':id', sale.id.toString()),
          );
        }
      },
      onRefresh: () async {
        pagingController.refresh();
      },
    );

    if (!isTablet) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(child: list),
      );
    }

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
                      ? Container(
                          color: Colors.white,
                          child: _DetailEmptyPlaceholder(
                            text: ref.t('history.empty'),
                          ),
                        )
                      : TransactionDetailPage(
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

class _TransactionList extends ConsumerWidget {
  final PagingController<int, Sale> pagingController;
  final String? selectedId;
  final ValueNotifier<String> query;
  final ValueNotifier<String> statusFilter;
  final ValueNotifier<DateTime?> dateFrom;
  final ValueNotifier<DateTime?> dateTo;
  final bool isTablet;
  final ValueChanged<Sale> onTap;
  final Future<void> Function() onRefresh;
  const _TransactionList({
    required this.pagingController,
    required this.selectedId,
    required this.query,
    required this.statusFilter,
    required this.dateFrom,
    required this.dateTo,
    required this.isTablet,
    required this.onTap,
    required this.onRefresh,
  });

  static const _statusOptions = <({String value, String label})>[
    (value: '', label: 'Semua'),
    (value: 'paid', label: 'Lunas'),
    (value: 'unpaid', label: 'Belum Bayar'),
    (value: 'refunded', label: 'Refund'),
  ];

  Future<void> _pickDateRange(BuildContext context) async {
    final now = DateTime.now();
    final initial = dateFrom.value != null && dateTo.value != null
        ? DateTimeRange(start: dateFrom.value!, end: dateTo.value!)
        : null;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
      helpText: 'Pilih rentang tanggal',
      saveText: 'Terapkan',
    );
    if (range != null) {
      dateFrom.value = range.start;
      dateTo.value = range.end;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(20, isTablet ? 24 : 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ref.t('history.title'),
                style: TextStyle(
                  fontSize: isTablet ? 24 : 18,
                  fontWeight: isTablet ? FontWeight.w800 : FontWeight.w700,
                  color: kTextDark,
                ),
              ),
              const Gap(8),
              TextField(
                onChanged: (v) => query.value = v,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Cari invoice atau pelanggan...',
                  hintStyle: TextStyle(color: kTextLight),
                  prefixIcon: Icon(Icons.search, size: 20, color: kTextMid),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  filled: true,
                  fillColor: kBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const Gap(10),
              // Filter status transaksi.
              ValueListenableBuilder<String>(
                valueListenable: statusFilter,
                builder: (context, status, _) => SizedBox(
                  height: 34,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _statusOptions.length,
                    separatorBuilder: (_, _) => const Gap(8),
                    itemBuilder: (context, i) {
                      final opt = _statusOptions[i];
                      final selected = status == opt.value;
                      return ChoiceChip(
                        label: Text(opt.label),
                        selected: selected,
                        onSelected: (_) => statusFilter.value = opt.value,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : kTextMid,
                        ),
                        selectedColor: kPrimary,
                        backgroundColor: kBg,
                        showCheckmark: false,
                        side: BorderSide(
                          color: selected ? kPrimary : kDivider,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const Gap(8),
              // Filter rentang tanggal.
              ValueListenableBuilder<DateTime?>(
                valueListenable: dateFrom,
                builder: (context, from, _) => ValueListenableBuilder<DateTime?>(
                  valueListenable: dateTo,
                  builder: (context, to, _) {
                    final hasRange = from != null && to != null;
                    return Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickDateRange(context),
                            icon: Icon(
                              Icons.calendar_today_rounded,
                              size: 16,
                              color: kTextMid,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kTextDark,
                              side: BorderSide(color: kDivider),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.centerLeft,
                            ),
                            label: Text(
                              hasRange
                                  ? '${formatShortDate(from)} — ${formatShortDate(to)}'
                                  : 'Semua tanggal',
                              style: TextStyle(
                                fontSize: 12,
                                color: hasRange ? kTextDark : kTextMid,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (hasRange) ...[
                          const Gap(4),
                          IconButton(
                            onPressed: () {
                              dateFrom.value = null;
                              dateTo.value = null;
                            },
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: kTextMid,
                            ),
                            tooltip: 'Hapus filter tanggal',
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (isTablet) Divider(height: 1, color: kDivider) else const Gap(8),
        Expanded(
          child: RefreshIndicator(
            color: kPrimary,
            onRefresh: onRefresh,
            child: PagingListener<int, Sale>(
              controller: pagingController,
              builder: (context, state, fetchNextPage) =>
                  PagedListView<int, Sale>.separated(
                    state: state,
                    fetchNextPage: fetchNextPage,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    separatorBuilder: (_, i) => const Gap(10),
                    builderDelegate: PagedChildBuilderDelegate<Sale>(
                      itemBuilder: (context, sale, index) {
                        return _SaleTile(
                          sale: sale,
                          selected: sale.id == selectedId,
                          onTap: () => onTap(sale),
                        );
                      },
                      noItemsFoundIndicatorBuilder: (_) => Center(
                        child: Text(
                          ref.t('history.empty'),
                          style: TextStyle(color: kTextMid),
                        ),
                      ),
                    ),
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailEmptyPlaceholder extends StatelessWidget {
  final String text;
  const _DetailEmptyPlaceholder({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: kBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: HugeIcon(
                icon: AppIcons.receiptLong,
                color: kTextLight,
                size: 32,
              ),
            ),
          ),
          const Gap(12),
          Text(text, style: TextStyle(color: kTextMid, fontSize: 13)),
        ],
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  final Sale sale;
  final bool selected;
  final VoidCallback onTap;
  const _SaleTile({
    required this.sale,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: sale.isRefunded
                    ? kDanger.withValues(alpha: 0.1)
                    : kSuccess.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: HugeIcon(
                  icon: sale.isRefunded
                      ? AppIcons.refund
                      : AppIcons.checkCircle,
                  color: sale.isRefunded ? kDanger : kSuccess,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sale.customerName.isNotEmpty
                              ? sale.customerName
                              : 'Transaksi #${sale.invoiceId.isNotEmpty ? sale.invoiceId : sale.id}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: kTextDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (sale.isFromMenuQr)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: kPrimary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.qr_code_2,
                                size: 10,
                                color: Colors.white,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'MENU QR',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (!sale.isPaid)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: kWarning,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'BELUM BAYAR',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Gap(2),
                  // Subtitle = invoice/time + tipe + meja (kalau dine-in) +
                  // metode bayar. Bagian `tableDisplay` hanya disisipkan
                  // untuk dine-in dengan meja terisi supaya tidak ada
                  // " · null" untuk takeaway.
                  Text(
                    () {
                      final parts = <String>[];
                      if (sale.customerName.isNotEmpty &&
                          sale.invoiceId.isNotEmpty) {
                        parts.add('#${sale.invoiceId}');
                      } else if (sale.customerName.isNotEmpty) {
                        parts.add('#${sale.id}');
                      }
                      parts.add(formatTime(sale.createdAt));
                      parts.add(sale.orderType);
                      if (sale.isDineIn && sale.tableDisplay != null) {
                        // tableDisplay umumnya sudah berbentuk "Meja 1 ·
                        // Lantai 2" — jangan tambah prefix lagi.
                        parts.add(sale.tableDisplay!);
                      }
                      parts.add(sale.paymentMethod);
                      return parts.join(' · ');
                    }(),
                    style: TextStyle(fontSize: 11, color: kTextMid),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              formatRupiah(sale.total),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: kPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
