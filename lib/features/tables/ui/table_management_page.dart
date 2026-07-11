import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:gap/gap.dart';
import '../../transactions/data/transaction_repository.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../../core/app_icons.dart';
import '../../../../app/theme.dart';
import '../../../../core/responsive.dart';
import '../../outlet/data/outlet_service.dart';
import '../data/table_repository.dart';
import '../domain/pos_table.dart';
import '../domain/table_group.dart';
import 'widgets/table_group_tab.dart';
import 'widgets/table_status_dialog.dart';
// TableStatusDialog dipakai dalam mode read-only (dialog manajemen meja
// yang dibuka dari halaman kasir) untuk menampilkan rincian pesanan +
// kontrol pilih/lanjut order. Mode non-read-only (manajemen di profil)
// tap meja → form edit struktur.
import '../../../../shared/widgets/tablet_components.dart';
import '../../../../core/outlet_scope.dart';
import '../../../../core/i18n.dart';

class TableManagementPage extends HookConsumerWidget {
  final bool isReadOnly;
  const TableManagementPage({super.key, this.isReadOnly = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTablet = context.isTablet;
    final outletsAsync = ref.watch(outletsProvider);
    final outlets = outletsAsync.value ?? [];
    final effectiveId = ref.watch(activeOutletIdProvider);

    final groupsAsync = ref.watch(tableGroupsFutureProvider);
    final selectedGroupId = useState<String?>(null);

    // Auto-select first outlet if none selected

    final masterWidth = useState<double>(350.0);

    if (isTablet) {
      return Scaffold(
        backgroundColor: kBg,
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(tableGroupsFutureProvider);
            if (selectedGroupId.value != null) {
              ref.invalidate(tablesFutureProvider);
            }
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: Row(
            children: [
              // Left Panel: Area List
              SizedBox(
                width: masterWidth.value,
                child: Column(
                  children: [
                    TabletPanelHeader(
                      title: ref.t('profile.tables'),
                      subtitle: groupsAsync.when(
                        data: (groups) => '${groups.length} area',
                        loading: () => '...',
                        error: (_, _) => null,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Tombol refresh manual di tablet — analog dengan
                          // IconButton refresh di AppBar mobile.
                          IconButton(
                            tooltip: 'Refresh',
                            icon: Icon(Icons.refresh, color: kTextMid),
                            onPressed: () {
                              ref.invalidate(tableGroupsFutureProvider);
                              ref.invalidate(tablesFutureProvider);
                            },
                          ),
                          if (!isReadOnly)
                            TabletAddButton(
                              label: 'Tambah',
                              onTap: () =>
                                  showGroupForm(context, ref, effectiveId),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: groupsAsync.when(
                        data: (groups) {
                          if (groups.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.grid_view,
                                      size: 48,
                                      color: kDivider,
                                    ),
                                    Gap(16),
                                    Text(
                                      ref.t('table.empty_hint'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: kTextMid),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          if (selectedGroupId.value == null) {
                            Future.microtask(() {
                              selectedGroupId.value = groups.first.id;
                            });
                          }
                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            itemCount: groups.length,
                            itemBuilder: (context, index) {
                              final g = groups[index];
                              final active = g.id == selectedGroupId.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Material(
                                  color: active
                                      ? kPrimary.withValues(alpha: 0.08)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    onTap: () => selectedGroupId.value = g.id,
                                    borderRadius: BorderRadius.circular(12),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: active
                                              ? kPrimary.withValues(alpha: 0.3)
                                              : Colors.transparent,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: active
                                                  ? kPrimary.withValues(
                                                      alpha: 0.15,
                                                    )
                                                  : kPrimary.withValues(
                                                      alpha: 0.08,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(11),
                                            ),
                                            child: Center(
                                              child: HugeIcon(
                                                icon: AppIcons.gridView,
                                                color: active
                                                    ? kPrimary
                                                    : kTextMid,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                          const Gap(12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  g.name,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: active
                                                        ? FontWeight.w700
                                                        : FontWeight.w500,
                                                    color: active
                                                        ? kPrimary
                                                        : kTextDark,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  '${g.tables.length} Meja',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: kTextMid,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (active && !isReadOnly)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 18,
                                              ),
                                              onPressed: () => showGroupForm(
                                                context,
                                                ref,
                                                effectiveId,
                                                group: g,
                                              ),
                                            ),
                                          if (active)
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
                                ),
                              );
                            },
                          );
                        },
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(child: Text('$e')),
                      ),
                    ),
                  ],
                ),
              ),
              // Right Panel: Details
              TabletResizableDivider(
                onResize: (delta) {
                  final newWidth = masterWidth.value + delta;
                  if (newWidth >= 280 && newWidth <= 500) {
                    masterWidth.value = newWidth;
                  }
                },
              ),
              Expanded(
                child: groupsAsync.when(
                  data: (groups) {
                    if (groups.isEmpty) {
                      return Center(child: Text(ref.t('table.select_area')));
                    }
                    final selectedGroup = groups.firstWhere(
                      (g) => g.id == selectedGroupId.value,
                      orElse: () => groups.first,
                    );
                    return Column(
                      children: [
                        TabletPanelHeader(
                          leading: TabletHeaderBadge(
                            icon: AppIcons.gridView,
                            color: kPrimary,
                          ),
                          title: selectedGroup.name,
                          subtitle:
                              'Area ${selectedGroup.name} — ${selectedGroup.tables.length} Meja terdaftar',
                          trailing: isReadOnly
                              ? null
                              : TabletAddButton(
                                  label: 'Tambah Meja',
                                  onTap: () => showTableForm(
                                    context,
                                    ref,
                                    groupId: selectedGroup.id,
                                    outletId: effectiveId!,
                                  ),
                                ),
                        ),
                        Expanded(
                          child: _TableGridView(
                            groupId: selectedGroup.id,
                            isReadOnly: isReadOnly,
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Mobile Layout — simplified ke single panel (CRUD area & meja).
    // Sebelumnya page ini punya 2 tab (Grup Meja & Laporan), tapi konteks
    // halaman ini adalah MANAJEMEN (struktur), jadi laporan dipindahkan
    // sebagai concern terpisah dan UI difokuskan ke CRUD saja.
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        leading: isReadOnly
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text(
          ref.t('profile.tables'),
          style: TextStyle(color: kTextDark, fontWeight: FontWeight.w700),
        ),
        actions: [
          // Tombol refresh manual untuk fetch ulang area & meja terbaru.
          // Pelengkap pull-to-refresh — user tetap bisa refresh meski sedang
          // tidak punya konten untuk di-pull.
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh, color: kTextDark),
            onPressed: () {
              ref.invalidate(tableGroupsFutureProvider);
              ref.invalidate(tablesFutureProvider);
            },
          ),
          if (effectiveId != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  // firstWhereOrNull: cegah StateError crash bila effectiveId
                  // stale / outlet sudah dihapus & tak ada di list.
                  outlets
                          .firstWhereOrNull((o) => o.remoteId == effectiveId)
                          ?.name ??
                      '',
                  style: const TextStyle(
                    color: kPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
        backgroundColor: kCard,
        elevation: 0,
        centerTitle: false,
      ),
      floatingActionButton: isTablet || isReadOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showGroupForm(context, ref, effectiveId),
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Tambah Area'),
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(tableGroupsFutureProvider);
          ref.invalidate(tablesFutureProvider);
          await Future.delayed(const Duration(milliseconds: 500));
        },
        // Saat dipanggil dari kasir (TableManagementPage(isReadOnly: true)),
        // tab area meneruskan flag-nya ke TableGroupTab supaya tap meja
        // membuka dialog detail (rincian pesanan) bukan form edit.
        child: TableGroupTab(isReadOnly: isReadOnly),
      ),
    );
  }

  void showGroupForm(
    BuildContext context,
    WidgetRef ref,
    String? outletId, {
    TableGroup? group,
  }) {
    final nameCtrl = TextEditingController(text: group?.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(group == null ? 'Tambah Area' : 'Edit Area'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nama Area/Grup'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          if (group != null)
            TextButton(
              onPressed: () async {
                try {
                  await ref
                      .read(tableRepositoryProvider)
                      .removeGroup(group.id.toString());
                  // Invalidate cache supaya list area langsung mencerminkan
                  // penghapusan tanpa harus restart / pull-to-refresh manual.
                  ref.invalidate(tableGroupsFutureProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('Gagal menghapus area: $e'),
                        backgroundColor: kDanger,
                      ),
                    );
                  }
                }
              },
              child: const Text('Hapus', style: TextStyle(color: kDanger)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final g = group ?? TableGroup(name: name);
              g.name = name;
              if (outletId != null) {
                g.outletRemoteId = outletId;
              }
              try {
                await ref.read(tableRepositoryProvider).saveGroup(g);
                // Invalidate cache supaya area baru / hasil edit langsung
                // muncul di list. Tanpa ini, response 200 dari backend tidak
                // tercermin di UI sampai user pull-to-refresh atau restart.
                ref.invalidate(tableGroupsFutureProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Gagal menyimpan area: $e'),
                      backgroundColor: kDanger,
                    ),
                  );
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void showTableForm(
    BuildContext context,
    WidgetRef ref, {
    required String groupId,
    required String outletId,
    PosTable? table,
  }) {
    final nameCtrl = TextEditingController(text: table?.name);
    final capCtrl = TextEditingController(
      text: table?.capacity.toString() ?? '4',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(table == null ? 'Tambah Meja' : 'Edit Meja'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nama/Nomor Meja',
                hintText: 'Contoh: Meja 1',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const Gap(12),
            TextField(
              controller: capCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Kapasitas (Kursi)'),
            ),
          ],
        ),
        actions: [
          if (table != null)
            TextButton(
              onPressed: () async {
                try {
                  await ref
                      .read(tableRepositoryProvider)
                      .removeTable(table.id.toString());
                  // Invalidate keduanya: list area memuat meja lewat join,
                  // list meja independen di tablet detail panel.
                  ref.invalidate(tableGroupsFutureProvider);
                  ref.invalidate(tablesFutureProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  // Backend memvalidasi status meja sebelum delete
                  // (occupied/reserved → ditolak). Tampilkan pesan error
                  // yang sebenarnya supaya user tahu kenapa gagal.
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('Gagal menghapus meja: $e'),
                        backgroundColor: kDanger,
                      ),
                    );
                  }
                }
              },
              child: const Text('Hapus', style: TextStyle(color: kDanger)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final cap = int.tryParse(capCtrl.text) ?? 4;
              if (name.isEmpty) return;
              final t = table ?? PosTable(name: name, capacity: cap);
              t.name = name;
              t.capacity = cap;
              t.groupId = groupId;
              t.outletRemoteId = outletId;
              try {
                await ref.read(tableRepositoryProvider).saveTable(t);
                ref.invalidate(tableGroupsFutureProvider);
                ref.invalidate(tablesFutureProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                // Backend memvalidasi nama unik per area; pesan errornya
                // (mis. "meja dengan nama ini sudah ada di area ini")
                // diteruskan ke user.
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Gagal menyimpan meja: $e'),
                      backgroundColor: kDanger,
                    ),
                  );
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}

class _TableGridView extends ConsumerWidget {
  final String groupId;
  final bool isReadOnly;
  const _TableGridView({required this.groupId, required this.isReadOnly});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablesAsync = ref.watch(tablesFutureProvider);

    return tablesAsync.when(
      data: (tables) {
        if (tables.isEmpty) {
          return const Center(child: Text('Belum ada meja di area ini.'));
        }
        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.0,
          ),
          itemCount: tables.length,
          itemBuilder: (context, index) {
            final t = tables[index];
            final isOccupied = t.status == TableStatus.occupied;
            final color = isOccupied ? kDanger : kSuccess;

            return GestureDetector(
              // Mode kasir (read-only) → tap meja buka TableStatusDialog
              // (rincian pesanan + tombol pilih meja / lanjut order).
              // Mode manajemen → tap meja buka form edit struktur.
              onTap: () {
                if (isReadOnly) {
                  showDialog(
                    context: context,
                    builder: (_) => TableStatusDialog(table: t),
                  );
                  return;
                }
                const TableManagementPage().showTableForm(
                  context,
                  ref,
                  groupId: groupId,
                  outletId: t.outletRemoteId ?? '',
                  table: t,
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: color.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.table_restaurant, color: color, size: 28),
                    const SizedBox(height: 4),
                    Text(
                      t.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${t.capacity} Kursi',
                      style: TextStyle(fontSize: 11, color: kTextMid),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isOccupied
                                ? ref.t('table.occupied')
                                : ref.t('table.available'),
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (isOccupied) ...[
                            const SizedBox(width: 6),
                            _TableDurationLabel(tableId: t.id),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }
}

class _TableDurationLabel extends ConsumerWidget {
  final String tableId;
  const _TableDurationLabel({required this.tableId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // activeTableTransactionsProvider sudah cache hasilnya (Riverpod) — tile
    // tidak akan re-fetch berulang walau dialog di-open/close. Tampilkan
    // hanya kalau data sudah tersedia dan ada transaksi aktif.
    final salesAsync = ref.watch(activeTableTransactionsProvider(tableId));
    return salesAsync.maybeWhen(
      data: (sales) {
        if (sales.isEmpty) return const SizedBox.shrink();
        final firstOrder = sales.first.createdAt;
        final diff = DateTime.now().difference(firstOrder);
        final hours = diff.inHours;
        final minutes = diff.inMinutes % 60;

        String dur = '';
        if (hours > 0) dur += '${hours}j ';
        dur += '${minutes}m';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: kDanger,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            dur,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
