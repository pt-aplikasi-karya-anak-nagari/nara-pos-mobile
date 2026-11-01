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
import '../data/transaksi_offline.dart';
import '../domain/sale.dart';
import 'transaction_detail_page.dart';
import 'widgets/riwayat_komponen.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import '../../../core/offline/sale_outbox.dart';
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

    // Antrian offline berkurang = ada transaksi yang baru diterima server →
    // muat ulang riwayat supaya ia muncul di sini (dan hilang dari "Belum
    // terkirim") tanpa kasir harus menarik layar.
    ref.listen<int>(pendingSyncCountProvider, (prev, next) {
      if (prev != null && next < prev) pagingController.refresh();
    });

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
      // top: false — header putih riwayat sendiri yang mengisi area status
      // bar, supaya tak ada pita latar di atas judul.
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(top: false, child: list),
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
    final atasStatusBar = isTablet ? 0.0 : MediaQuery.paddingOf(context).top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: kCard,
          padding: EdgeInsets.fromLTRB(
            20,
            atasStatusBar + (isTablet ? 24 : 12),
            12,
            12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ref.t('history.title'),
                      style: TextStyle(
                        fontSize: isTablet ? 24 : 20,
                        fontWeight: FontWeight.w700,
                        color: kTextDark,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  // Filter tanggal: ikon ringkas di kanan judul; titik biru
                  // menandai rentang aktif (rentangnya tampil sebagai chip).
                  ValueListenableBuilder<DateTime?>(
                    valueListenable: dateFrom,
                    builder: (context, from, _) => IconButton(
                      tooltip: 'Pilih tanggal',
                      onPressed: () => _pickDateRange(context),
                      icon: Badge(
                        isLabelVisible: from != null,
                        smallSize: 8,
                        backgroundColor: kPrimary,
                        child: Icon(
                          Icons.calendar_month_outlined,
                          color: from != null ? kPrimary : kTextMid,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    onChanged: (v) => query.value = v,
                    style: TextStyle(fontSize: 14, color: kTextDark),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Cari invoice atau pelanggan',
                      hintStyle: TextStyle(color: kTextLight, fontSize: 14),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: kTextMid,
                      ),
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: kBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const Gap(10),
              // Filter status + chip rentang tanggal aktif, satu baris gulir.
              ValueListenableBuilder<String>(
                valueListenable: statusFilter,
                builder: (context, status, _) => ValueListenableBuilder<DateTime?>(
                  valueListenable: dateFrom,
                  builder: (context, from, _) {
                    final to = dateTo.value;
                    final rentang = from != null && to != null;
                    return SizedBox(
                      height: 32,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          if (rentang) ...[
                            _ChipFilter(
                              label:
                                  '${formatShortDate(from)} – ${formatShortDate(to)}',
                              aktif: true,
                              ikon: Icons.close_rounded,
                              onTap: () {
                                dateFrom.value = null;
                                dateTo.value = null;
                              },
                            ),
                            const Gap(8),
                          ],
                          for (final opt in _statusOptions) ...[
                            _ChipFilter(
                              label: opt.label,
                              aktif: status == opt.value,
                              onTap: () => statusFilter.value = opt.value,
                            ),
                            const Gap(8),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: kDivider.withValues(alpha: 0.7)),
        Expanded(
          child: RefreshIndicator(
            color: kPrimary,
            onRefresh: () async {
              ref.invalidate(ringkasanRiwayatProvider);
              await onRefresh();
            },
            // Satu gulungan: ringkasan, transaksi offline yang belum
            // terkirim, lalu riwayat dari server dikelompokkan per tanggal.
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _Ringkasan(dateFrom: dateFrom, dateTo: dateTo),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _BagianBelumTerkirim(
                      selectedId: selectedId,
                      onTap: onTap,
                    ),
                  ),
                ),
                PagingListener<int, Sale>(
                  controller: pagingController,
                  builder: (context, state, fetchNextPage) => SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: PagedSliverList<int, Sale>.separated(
                      state: state,
                      fetchNextPage: fetchNextPage,
                      separatorBuilder: (_, i) => const Gap(8),
                      builderDelegate: PagedChildBuilderDelegate<Sale>(
                        itemBuilder: (context, sale, index) {
                          final semua = state.items ?? const <Sale>[];
                          final awalHari =
                              index == 0 ||
                              index >= semua.length ||
                              !hariSama(
                                semua[index - 1].createdAt,
                                sale.createdAt,
                              );
                          final kartu = KartuTransaksi(
                            sale: sale,
                            selected: sale.id == selectedId,
                            onTap: () => onTap(sale),
                          );
                          if (!awalHari) return kartu;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              LabelTanggalRiwayat(
                                labelTanggalRiwayat(sale.createdAt),
                              ),
                              kartu,
                            ],
                          );
                        },
                        noItemsFoundIndicatorBuilder: (_) =>
                            _KosongRiwayat(teks: ref.t('history.empty')),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Chip filter berbentuk pil — aktif: biru penuh; pasif: garis tipis.
class _ChipFilter extends StatelessWidget {
  final String label;
  final bool aktif;
  final IconData? ikon;
  final VoidCallback onTap;
  const _ChipFilter({
    required this.label,
    required this.aktif,
    required this.onTap,
    this.ikon,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: aktif ? kPrimary : kCard,
      shape: StadiumBorder(
        side: BorderSide(color: aktif ? kPrimary : kDivider),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: aktif ? Colors.white : kTextMid,
                ),
              ),
              if (ikon != null) ...[
                const Gap(4),
                Icon(ikon, size: 14, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartu ringkasan omzet untuk rentang yang sedang dilihat (hari ini bila
/// tak ada filter tanggal). Disembunyikan saat offline/galat.
class _Ringkasan extends ConsumerWidget {
  final ValueNotifier<DateTime?> dateFrom;
  final ValueNotifier<DateTime?> dateTo;
  const _Ringkasan({required this.dateFrom, required this.dateTo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outletId = ref.watch(activeOutletIdProvider);
    if (outletId == null) return const SizedBox.shrink();
    return ValueListenableBuilder<DateTime?>(
      valueListenable: dateFrom,
      builder: (context, from, _) {
        final to = dateTo.value;
        final hariIni = DateTime.now();
        final dari = from ?? hariIni;
        final sampai = (from != null ? to : null) ?? hariIni;
        final periode = from == null
            ? 'hari ini'
            : hariSama(dari, sampai)
            ? formatShortDate(dari)
            : '${formatShortDate(dari)} – ${formatShortDate(sampai)}';
        final data = ref
            .watch(
              ringkasanRiwayatProvider((
                outletId: outletId,
                dari: formatIsoDate(dari),
                sampai: formatIsoDate(sampai),
              )),
            )
            .value;
        if (data == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: KartuRingkasanRiwayat(periode: periode, ringkasan: data),
        );
      },
    );
  }
}

class _KosongRiwayat extends StatelessWidget {
  final String teks;
  const _KosongRiwayat({required this.teks});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 40, color: kTextLight),
          const Gap(10),
          Text(
            teks,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: kTextDark,
            ),
          ),
          const Gap(2),
          Text(
            'Coba ubah filter atau rentang tanggal.',
            style: TextStyle(fontSize: 12, color: kTextMid),
          ),
        ],
      ),
    );
  }
}

/// Transaksi offline yang belum sampai ke server. Selalu di atas riwayat,
/// supaya kasir bisa menemukan dan mencetak ulang struknya walau internet
/// putus — riwayat dari server baru memuatnya setelah terkirim.
class _BagianBelumTerkirim extends ConsumerWidget {
  const _BagianBelumTerkirim({required this.selectedId, required this.onTap});

  final String? selectedId;
  final ValueChanged<Sale> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daftar = ref.watch(transaksiBelumTerkirimProvider).value ?? const [];
    if (daftar.isEmpty) return const SizedBox.shrink();
    final gagal = daftar.where((s) => s.gagalTerkirim).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                size: 16,
                color: gagal > 0 ? kDanger : kWarning,
              ),
              const Gap(6),
              Expanded(
                child: Text(
                  'Belum terkirim ke server (${daftar.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kTextDark,
                  ),
                ),
              ),
            ],
          ),
          const Gap(4),
          Text(
            'Tersimpan aman di perangkat dan dikirim otomatis saat online.'
            '${gagal > 0 ? ' $gagal ditolak server — buka untuk melihat alasannya.' : ''}',
            style: TextStyle(fontSize: 11, color: kTextMid, height: 1.3),
          ),
          const Gap(8),
          for (final sale in daftar) ...[
            KartuTransaksi(
              sale: sale,
              selected: sale.id == selectedId,
              onTap: () => onTap(sale),
            ),
            const Gap(10),
          ],
          Divider(height: 8, color: kDivider),
        ],
      ),
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
