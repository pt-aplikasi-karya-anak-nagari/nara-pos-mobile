import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:gap/gap.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/format.dart';
import '../../../core/responsive.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../../printer/data/printer_service.dart';
import '../../transactions/domain/sale.dart';
import '../data/shift_repository.dart';
import '../domain/shift.dart';
import 'cash_movement_sheet.dart';

class ShiftHistoryPage extends HookConsumerWidget {
  const ShiftHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // activeOutletId available via shiftsFutureProvider internally
    final shiftsAsync = ref.watch(shiftsFutureProvider);
    final isTablet = context.isTablet;
    final selectedId = useState<String?>(null);
    final selectedDate = useState<DateTime?>(null);
    final searchQuery = useTextEditingController();
    final search = useValueListenable(searchQuery);

    final filteredShifts = shiftsAsync.when(
      data: (list) {
        var result = list;
        if (selectedDate.value != null) {
          result = result
              .where((s) => isSameDay(s.startTime, selectedDate.value!))
              .toList();
        }
        if (search.text.isNotEmpty) {
          final q = search.text.toLowerCase();
          result = result
              .where((s) => s.cashierName.toLowerCase().contains(q))
              .toList();
        }
        return result;
      },
      loading: () => <Shift>[],
      error: (_, _) => <Shift>[],
    );

    return Scaffold(
      backgroundColor: kBg,
      appBar: isTablet
          ? null
          : AppBar(
              backgroundColor: kCard,
              elevation: 0,
              title: Text(
                'Riwayat Shift',
                style: TextStyle(color: kTextDark, fontWeight: FontWeight.w700),
              ),
              iconTheme: IconThemeData(color: kTextDark),
              actions: [
                IconButton(
                  icon: const HugeIcon(icon: AppIcons.event, color: kPrimary),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: selectedDate.value ?? DateTime.now(),
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) selectedDate.value = d;
                  },
                ),
                if (selectedDate.value != null)
                  IconButton(
                    icon: const HugeIcon(icon: AppIcons.reset, color: kDanger),
                    onPressed: () => selectedDate.value = null,
                  ),
              ],
            ),
      body: SafeArea(
        child: shiftsAsync.when(
          loading: () => Skeletonizer(
            enabled: true,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: 5,
              separatorBuilder: (_, _) => const Gap(12),
              itemBuilder: (_, _) => _ShiftListCard(
                shift: Shift(
                  startTime: DateTime.now(),
                  startingCash: 100000,
                  cashierName: 'Nama Kasir',
                  cashierRemoteId: '',
                ),
              ),
            ),
          ),
          error: (e, _) => Center(child: Text('$e')),
          data: (list) {
            if (!isTablet) {
              return _PhoneList(items: filteredShifts);
            }

            return Row(
              children: [
                // ── Left: Master panel ──
                Expanded(
                  child: _TabletMasterPanel(
                    items: filteredShifts,
                    selectedId: selectedId.value,
                    selectedDate: selectedDate.value,
                    searchCtrl: searchQuery,
                    onSelectDate: (d) => selectedDate.value = d,
                    onSelect: (id) => selectedId.value = id,
                  ),
                ),
                VerticalDivider(width: 1, color: kDivider),
                // ── Right: Detail panel ──
                Expanded(
                  flex: 2,
                  child: _TabletDetailPanel(
                    shift: selectedId.value != null && filteredShifts.isNotEmpty
                        ? filteredShifts
                              .where((s) => s.remoteId == selectedId.value)
                              .firstOrNull
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

// ─── Phone layout ──────────────────────────────────────────────────────────

class _PhoneList extends ConsumerWidget {
  final List<Shift> items;
  const _PhoneList({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const Center(
        child: TabletDetailEmptyState(
          icon: AppIcons.time,
          title: 'Belum Ada Riwayat Shift',
          subtitle: 'Data buka/tutup kasir akan muncul di sini.',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(shiftsFutureProvider);
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Gap(12),
        itemBuilder: (context, index) {
          return _ShiftListCard(shift: items[index]);
        },
      ),
    );
  }
}

// ─── Tablet: Master Panel ──────────────────────────────────────────────────

class _TabletMasterPanel extends ConsumerWidget {
  final List<Shift> items;
  final String? selectedId;
  final DateTime? selectedDate;
  final TextEditingController searchCtrl;
  final ValueChanged<DateTime?> onSelectDate;
  final ValueChanged<String> onSelect;

  const _TabletMasterPanel({
    required this.items,
    required this.selectedId,
    required this.selectedDate,
    required this.searchCtrl,
    required this.onSelectDate,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: kBg,
      child: Column(
        children: [
          TabletPanelHeader(
            title: 'Riwayat Shift',
            subtitle: selectedDate != null
                ? formatShortDate(selectedDate!)
                : 'Semua Sesi',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selectedDate != null)
                  IconButton(
                    onPressed: () => onSelectDate(null),
                    icon: const HugeIcon(
                      icon: AppIcons.reset,
                      color: kDanger,
                      size: 20,
                    ),
                  ),
                IconButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: selectedDate ?? DateTime.now(),
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) onSelectDate(d);
                  },
                  icon: const HugeIcon(
                    icon: AppIcons.event,
                    color: kPrimary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: TabletStyledTextField(
              controller: searchCtrl,
              hint: 'Cari kasir...',
              icon: AppIcons.search,
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(shiftsFutureProvider);
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: items.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: const TabletMasterEmptyState(
                            icon: AppIcons.time,
                            message: 'Belum ada riwayat',
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Gap(4),
                      itemBuilder: (_, i) {
                        final s = items[i];
                        final selected = s.remoteId == selectedId;
                        return _MasterShiftTile(
                          shift: s,
                          isSelected: selected,
                          onTap: () => onSelect(s.remoteId ?? ''),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MasterShiftTile extends StatelessWidget {
  final Shift shift;
  final bool isSelected;
  final VoidCallback onTap;

  const _MasterShiftTile({
    required this.shift,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isNegative = (shift.difference ?? 0) < 0;
    final hasDifference = shift.difference != null && shift.difference != 0;

    return Material(
      color: isSelected ? kPrimary.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? kPrimary.withValues(alpha: 0.3)
                  : (hasDifference
                        ? (isNegative
                              ? kDanger.withValues(alpha: 0.1)
                              : kWarning.withValues(alpha: 0.1))
                        : Colors.transparent),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? kPrimary.withValues(alpha: 0.15)
                      : kPrimary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: HugeIcon(
                    icon: AppIcons.person,
                    color: isSelected ? kPrimary : kTextMid,
                    size: 18,
                  ),
                ),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${shift.cashierName} • ${shift.outletRemoteId ?? 'Unknown'}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isSelected ? kPrimary : kTextDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      formatDateTime(shift.startTime),
                      style: TextStyle(fontSize: 11, color: kTextMid),
                    ),
                  ],
                ),
              ),
              if (hasDifference)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isNegative ? kDanger : kWarning,
                    shape: BoxShape.circle,
                  ),
                )
              else if (isSelected)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: kPrimary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tablet: Detail Panel ──────────────────────────────────────────────────

class _TabletDetailPanel extends ConsumerWidget {
  final Shift? shift;
  const _TabletDetailPanel({required this.shift});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (shift == null) {
      return const TabletDetailEmptyState(
        icon: AppIcons.time,
        title: 'Detail Riwayat Shift',
        subtitle:
            'Pilih shift dari daftar di sebelah kiri untuk melihat detail lengkap arus kas.',
      );
    }

    final s = shift!;
    final isNegative = (s.difference ?? 0) < 0;
    final hasDifference = s.difference != null && s.difference != 0;

    // Non-cash sales will be loaded from API when shift detail endpoint is available
    final shiftSales = <Sale>[];

    double totalQris = 0;
    double totalCard = 0;
    double totalTransfer = 0;
    double totalRefund = 0;
    int refundCount = 0;

    for (final sale in shiftSales) {
      if (sale.isRefunded) {
        totalRefund += sale.total;
        refundCount++;
        continue;
      }
      if (sale.paymentMethod == 'QRIS') totalQris += sale.total;
      if (sale.paymentMethod == 'Kartu') totalCard += sale.total;
      if (sale.paymentMethod == 'Transfer') totalTransfer += sale.total;
    }

    String duration = '-';
    if (s.endTime != null) {
      final diff = s.endTime!.difference(s.startTime);
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      duration = h > 0 ? '${h}j ${m}m' : '${m}m';
    }

    return Container(
      color: kBg,
      child: Column(
        children: [
          TabletPanelHeader(
            leading: TabletHeaderBadge(
              icon: AppIcons.time,
              color: s.isOpen ? kPrimary : kTextMid,
            ),
            title: 'Detail Shift #${s.remoteId}',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!s.isOpen)
                  IconButton(
                    onPressed: () async {
                      final success = await ref
                          .read(printerServiceProvider)
                          .printShiftReport(s, shiftSales);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              success
                                  ? 'Laporan berhasil dicetak'
                                  : 'Gagal mencetak laporan. Cek koneksi printer.',
                            ),
                            backgroundColor: success ? kSuccess : kDanger,
                          ),
                        );
                      }
                    },
                    icon: const HugeIcon(
                      icon: AppIcons.printer,
                      color: kPrimary,
                      size: 20,
                    ),
                    tooltip: 'Cetak Laporan Shift',
                  ),
                const Gap(8),
                _StatusChip(isOpen: s.isOpen),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // User Info Card
                      _DetailHeader(shift: s),
                      const Gap(24),

                      // Time Info
                      const _SubHeader(label: 'WAKTU OPERASIONAL'),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: kDivider),
                        ),
                        child: Row(
                          children: [
                            _DetailInfoItem(
                              label: 'Mulai',
                              value: formatDateTime(s.startTime),
                              icon: AppIcons.login,
                            ),
                            const VerticalDivider(),
                            _DetailInfoItem(
                              label: 'Selesai',
                              value: s.endTime != null
                                  ? formatDateTime(s.endTime!)
                                  : '-',
                              icon: AppIcons.logout,
                            ),
                            const VerticalDivider(),
                            _DetailInfoItem(
                              label: 'Durasi',
                              value: duration,
                              icon: AppIcons.time,
                            ),
                          ],
                        ),
                      ),
                      const Gap(24),

                      // Cash Info
                      const _SubHeader(label: 'RINGKASAN ARUS KAS'),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: hasDifference
                                ? (isNegative ? kDanger : kWarning)
                                : kDivider,
                            width: hasDifference ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            _AmountRow(
                              label: 'Modal Awal',
                              value: s.startingCash,
                            ),
                            const Gap(12),
                            if (!s.isOpen) ...[
                              _AmountRow(
                                label: 'Total Penjualan Tunai',
                                value: (s.expectedCash ?? 0) - s.startingCash,
                              ),
                              const Divider(height: 32),
                              _AmountRow(
                                label: 'Ekspektasi Kas di Laci',
                                value: s.expectedCash ?? 0,
                                isPrimary: true,
                              ),
                              const Gap(12),
                              _AmountRow(
                                label: 'Uang Fisik Dihitung',
                                value: s.actualCash ?? 0,
                                isBold: true,
                              ),
                              const Divider(height: 32),
                              _AmountRow(
                                label: 'Selisih',
                                value: s.difference ?? 0,
                                valueColor: isNegative
                                    ? kDanger
                                    : (hasDifference ? kWarning : kSuccess),
                                isBold: true,
                              ),
                              const Gap(32),

                              // Non-Cash Summary
                              const _SubHeader(label: 'TRANSAKSI NON-TUNAI'),
                              _AmountRow(
                                label: 'Total QRIS',
                                value: totalQris,
                                icon: AppIcons.qrCode,
                              ),
                              const Gap(12),
                              _AmountRow(
                                label: 'Total Kartu',
                                value: totalCard,
                                icon: AppIcons.creditCard,
                              ),
                              const Gap(12),
                              _AmountRow(
                                label: 'Total Transfer',
                                value: totalTransfer,
                                icon: AppIcons.payment,
                              ),
                              const Divider(height: 32),
                              _AmountRow(
                                label: 'Total Non-Tunai',
                                value: totalQris + totalCard + totalTransfer,
                                isPrimary: true,
                              ),
                              const Divider(height: 32),

                              // Refund Summary
                              const _SubHeader(label: 'PENGEMBALIAN (REFUND)'),
                              _AmountRow(
                                label: 'Jumlah Refund ($refundCount)',
                                value: totalRefund,
                                icon: AppIcons.refund,
                                valueColor: refundCount > 0 ? kDanger : null,
                              ),
                            ] else ...[
                              Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Text(
                                    'Shift masih aktif. Data ekspektasi kas\nakan muncul setelah shift ditutup.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: kTextMid,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ),
                              if (s.remoteId != null)
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () => showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) =>
                                          CashMovementSheet(shiftId: s.remoteId!),
                                    ),
                                    icon: const Icon(
                                      Icons.account_balance_wallet_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Catat Kas Masuk / Keluar'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: kPrimary,
                                      side: BorderSide(
                                        color: kPrimary.withValues(alpha: 0.4),
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),

                      if (s.notes != null && s.notes!.isNotEmpty) ...[
                        const Gap(24),
                        const _SubHeader(label: 'CATATAN KASIR'),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: kBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: kDivider),
                          ),
                          child: Text(
                            s.notes!,
                            style: TextStyle(
                              color: kTextDark,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  final Shift shift;
  const _DetailHeader({required this.shift});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: kPrimary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: HugeIcon(
              icon: AppIcons.person,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
        const Gap(16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shift.cashierName,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: kTextDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Row(
                children: [
                  HugeIcon(
                    icon: AppIcons.storefront,
                    color: kTextMid,
                    size: 12,
                  ),
                  const Gap(4),
                  Expanded(
                    child: Text(
                      '${shift.outletRemoteId} • ID Kasir: #${shift.cashierRemoteId}',
                      style: TextStyle(color: kTextMid, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailInfoItem extends StatelessWidget {
  final String label;
  final String value;
  final IconAsset icon;

  const _DetailInfoItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HugeIcon(icon: icon, color: kTextMid, size: 14),
              const Gap(6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: kTextMid,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Gap(4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: kTextDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final double value;
  final bool isBold;
  final bool isPrimary;
  final Color? valueColor;
  final IconAsset? icon;

  const _AmountRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.isPrimary = false,
    this.valueColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              HugeIcon(icon: icon!, color: kTextMid, size: 14),
              const Gap(8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: isPrimary ? 15 : 14,
                fontWeight: isPrimary ? FontWeight.w700 : FontWeight.w500,
                color: isPrimary ? kTextDark : kTextMid,
              ),
            ),
          ],
        ),
        Text(
          formatRupiah(value),
          style: TextStyle(
            fontSize: isPrimary ? 16 : 14,
            fontWeight: (isBold || isPrimary)
                ? FontWeight.w800
                : FontWeight.w700,
            color: valueColor ?? kTextDark,
          ),
        ),
      ],
    );
  }
}

class _SubHeader extends StatelessWidget {
  final String label;
  const _SubHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: kTextMid,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

// ─── Shared Components ──────────────────────────────────────────────────────

class _ShiftListCard extends StatelessWidget {
  final Shift shift;
  const _ShiftListCard({required this.shift});

  @override
  Widget build(BuildContext context) {
    final isNegative = (shift.difference ?? 0) < 0;
    final hasDifference = shift.difference != null && shift.difference != 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasDifference ? (isNegative ? kDanger : kWarning) : kDivider,
          width: hasDifference ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const HugeIcon(
              icon: AppIcons.person,
              color: kPrimary,
              size: 20,
            ),
          ),
          const Gap(16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${shift.cashierName} (${shift.outletRemoteId ?? 'Unknown'})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Text(
                  formatDateTime(shift.startTime),
                  style: TextStyle(fontSize: 12, color: kTextMid),
                ),
              ],
            ),
          ),
          if (hasDifference)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatRupiah(shift.difference!),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isNegative ? kDanger : kWarning,
                    fontSize: 14,
                  ),
                ),
                Text(
                  isNegative ? 'Kurang' : 'Lebih',
                  style: TextStyle(
                    fontSize: 10,
                    color: isNegative ? kDanger : kWarning,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          else
            Icon(Icons.chevron_right, color: kTextMid),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool isOpen;
  const _StatusChip({required this.isOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isOpen
            ? kSuccess.withValues(alpha: 0.1)
            : kTextMid.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        isOpen ? 'SHIFT AKTIF' : 'SHIFT SELESAI',
        style: TextStyle(
          color: isOpen ? kSuccess : kTextMid,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
