import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../tables/data/table_repository.dart';
import '../../../tables/domain/pos_table.dart';
import '../../../tables/ui/widgets/table_status_dialog.dart';
import '../../../transactions/data/transaction_repository.dart';
import '../../providers.dart';

class TableSelectorSheet extends ConsumerWidget {
  const TableSelectorSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(tableGroupsFutureProvider);
    final activeTable = ref.watch(activeTableProvider);

    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: kDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Gap(16),
          Row(
            children: [
              const Icon(Icons.table_restaurant, color: kPrimary),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pilih Meja',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Khusus untuk pesanan Makan di Tempat (Dine In)',
                      style: TextStyle(fontSize: 12, color: kTextMid),
                    ),
                  ],
                ),
              ),
              if (activeTable != null)
                TextButton(
                  onPressed: () {
                    ref.read(activeTableProvider.notifier).set(null);
                    Navigator.pop(context);
                  },
                  child: const Text('Hapus', style: TextStyle(color: kDanger)),
                ),
            ],
          ),
          const Gap(16),
          groupsAsync.when(
            data: (groups) => Flexible(
              child: DefaultTabController(
                length: groups.length,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TabBar(
                      isScrollable: false,
                      labelColor: kPrimary,
                      unselectedLabelColor: kTextMid,
                      indicatorColor: kPrimary,
                      dividerColor: Colors.transparent,
                      tabs: groups.map((g) => Tab(text: g.name)).toList(),
                    ),
                    const Gap(16),
                    SizedBox(
                      height: 300,
                      child: TabBarView(
                        children: groups
                            .map((g) => _TableGrid(groupId: g.id))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
          ),
        ],
      ),
    );
  }
}

class _TableGrid extends ConsumerWidget {
  final String groupId;
  const _TableGrid({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablesAsync = ref.watch(tablesFutureProvider);
    final activeTable = ref.watch(activeTableProvider);

    return tablesAsync.when(
      data: (tables) {
        // Filter tables milik area ini (groupId match) supaya tab benar-benar
        // berisi meja area-nya, bukan semua meja di outlet.
        final groupTables = tables.where((t) => t.groupId == groupId).toList();
        if (groupTables.isEmpty) {
          return Center(
            child: Text(
              'Belum ada meja di area ini',
              style: TextStyle(color: kTextMid, fontSize: 12),
            ),
          );
        }
        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.6,
          ),
          itemCount: groupTables.length,
          itemBuilder: (context, index) {
            final table = groupTables[index];
            final isSelected = activeTable?.id == table.id;
            final isOccupied = table.status == TableStatus.occupied;

            return GestureDetector(
              // Tap perilaku berbeda berdasarkan status meja:
              //   - Tersedia → set as active table, pop sheet
              //   - Terisi  → buka TableStatusDialog supaya kasir lihat
              //               rincian pesanan yang sedang berjalan
              onTap: () {
                if (isOccupied) {
                  showDialog(
                    context: context,
                    builder: (_) => TableStatusDialog(table: table),
                  );
                  return;
                }
                ref.read(activeTableProvider.notifier).set(table);
                Navigator.pop(context, table);
              },
              child: _TableTile(
                table: table,
                isSelected: isSelected,
                isOccupied: isOccupied,
              ),
            );
          },
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, st) => const SizedBox.shrink(),
    );
  }
}

/// Tile meja di selector. Untuk meja occupied, tampilkan badge durasi live
/// (sejak order pertama) supaya kasir tahu meja mana yang sudah lama
/// menunggu. Tap tile occupied buka dialog detail (handled di parent).
class _TableTile extends ConsumerWidget {
  final PosTable table;
  final bool isSelected;
  final bool isOccupied;
  const _TableTile({
    required this.table,
    required this.isSelected,
    required this.isOccupied,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? kPrimary
            : (isOccupied ? kDanger.withValues(alpha: 0.05) : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? kPrimary
              : (isOccupied
                    ? kDanger.withValues(alpha: 0.3)
                    : kDivider),
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  table.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? Colors.white
                        : (isOccupied ? kDanger : kTextDark),
                  ),
                ),
                Text(
                  isOccupied ? 'Terisi · Tap detail' : '${table.capacity} Kursi',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isOccupied ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.8)
                        : (isOccupied ? kDanger : kTextMid),
                  ),
                ),
              ],
            ),
          ),
          // Badge durasi (pojok kanan atas) hanya untuk meja occupied —
          // memuat data dari provider yang sama dengan dialog detail.
          if (isOccupied)
            Positioned(
              top: 0,
              right: 0,
              child: _DurationBadge(tableId: table.id),
            ),
        ],
      ),
    );
  }
}

class _DurationBadge extends ConsumerWidget {
  final String tableId;
  const _DurationBadge({required this.tableId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(activeTableTransactionsProvider(tableId));
    return salesAsync.maybeWhen(
      data: (sales) {
        if (sales.isEmpty) return const SizedBox.shrink();
        final diff = DateTime.now().difference(sales.first.createdAt);
        final hours = diff.inHours;
        final minutes = diff.inMinutes % 60;
        String label;
        if (hours > 0) {
          label = '${hours}j${minutes}m';
        } else {
          label = '${minutes}m';
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: kDanger,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
