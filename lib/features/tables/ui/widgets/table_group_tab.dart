import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../../app/theme.dart';
import '../../../outlet/data/outlet_service.dart';
import '../../data/table_repository.dart';
import '../../domain/pos_table.dart';
import '../../domain/table_group.dart';
import '../table_management_page.dart';
import 'table_qr_dialog.dart';
import 'table_status_dialog.dart';

/// Tab/halaman daftar area-meja dalam manajemen meja.
///
/// [isReadOnly] menentukan perilaku dasar:
///   - **false** (default — halaman manajemen di profil): tampilkan tombol
///     CRUD (edit area, tambah meja, edit meja). Tap meja → buka form edit
///     struktur.
///   - **true** (dialog di kasir): tombol CRUD disembunyikan. Tap meja →
///     buka [TableStatusDialog] berisi rincian pesanan + tombol pilih meja
///     / tambah pesanan baru, sesuai status meja.
class TableGroupTab extends ConsumerWidget {
  final bool isReadOnly;
  const TableGroupTab({super.key, this.isReadOnly = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(tableGroupsFutureProvider);

    return groupsAsync.when(
      data: (groups) {
        if (groups.isEmpty) {
          // Bungkus empty state dengan ListView (1 item) supaya
          // RefreshIndicator parent tetap bisa di-pull saat list kosong.
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(32),
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.5,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.grid_view, size: 48, color: kDivider),
                      Gap(12),
                      Text(
                        'Belum ada area meja',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: kTextDark,
                        ),
                      ),
                      Gap(4),
                      Text(
                        'Tambahkan area untuk mulai mengelola meja',
                        style: TextStyle(fontSize: 12, color: kTextMid),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        return ListView.builder(
          // AlwaysScrollable supaya RefreshIndicator parent tetap respond
          // walau konten lebih pendek dari layar.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            return _GroupCard(group: group, isReadOnly: isReadOnly);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }
}

class _GroupCard extends ConsumerWidget {
  final TableGroup group;
  final bool isReadOnly;
  const _GroupCard({required this.group, required this.isReadOnly});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.grid_view, color: kPrimary, size: 20),
                const Gap(12),
                Expanded(
                  child: Text(
                    group.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                // Tombol manajemen hanya muncul di mode non-read-only.
                // Di kasir, dialog ini bersifat informasi/pilih meja saja.
                if (!isReadOnly) ...[
                  // Bulk export QR semua meja di area ini → PDF (grid 2x2).
                  // Sembunyikan kalau group belum punya meja.
                  if (group.tables.isNotEmpty)
                    IconButton(
                      onPressed: () => _printAreaQr(context, ref, group),
                      icon: Icon(
                        Icons.qr_code_2,
                        color: kTextMid,
                        size: 20,
                      ),
                      tooltip: 'Cetak QR semua meja',
                    ),
                  IconButton(
                    onPressed: () => const TableManagementPage().showGroupForm(
                      context,
                      ref,
                      group.outletRemoteId,
                      group: group,
                    ),
                    icon: Icon(
                      Icons.edit_outlined,
                      color: kTextMid,
                      size: 20,
                    ),
                    tooltip: 'Edit Area',
                  ),
                  IconButton(
                    onPressed: () => const TableManagementPage().showTableForm(
                      context,
                      ref,
                      groupId: group.id,
                      outletId: group.outletRemoteId ?? '',
                    ),
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: kPrimary,
                    ),
                    tooltip: 'Tambah Meja',
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          if (group.tables.isEmpty)
            Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Belum ada meja di group ini',
                  style: TextStyle(color: kTextMid),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.5,
              ),
              itemCount: group.tables.length,
              itemBuilder: (context, index) {
                final table = group.tables[index];
                return GestureDetector(
                  // Mode kasir: tap meja → buka TableStatusDialog
                  //   - meja occupied → lihat rincian pesanan + lanjut order
                  //   - meja available → konfirmasi pilih meja
                  // Mode manajemen: tap meja → form edit struktur,
                  //   long-press → dialog generate QR menu (shortcut).
                  //   Tombol QR di tile = entry point utama (lebih discoverable
                  //   daripada long-press).
                  onTap: () {
                    if (isReadOnly) {
                      showDialog(
                        context: context,
                        builder: (_) => TableStatusDialog(table: table),
                      );
                    } else {
                      const TableManagementPage().showTableForm(
                        context,
                        ref,
                        groupId: table.groupId ?? '',
                        outletId: table.outletRemoteId ?? '',
                        table: table,
                      );
                    }
                  },
                  onLongPress: isReadOnly
                      ? null
                      : () => _showQrDialog(context, ref, table),
                  child: _TableTile(
                    table: table,
                    isReadOnly: isReadOnly,
                    onQrTap: isReadOnly
                        ? null
                        : () => _showQrDialog(context, ref, table),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _TableTile extends StatelessWidget {
  final PosTable table;
  final bool isReadOnly;
  /// Callback ketika user tap ikon QR di tile (mode manajemen).
  /// Null → ikon tidak muncul (mode kasir / disabled).
  final VoidCallback? onQrTap;
  const _TableTile({
    required this.table,
    this.isReadOnly = false,
    this.onQrTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOccupied = table.status == TableStatus.occupied;
    final statusColor = table.status == TableStatus.available
        ? kSuccess
        : (isOccupied ? kDanger : Colors.orange);

    // Affordance icon di trailing tile berbeda berdasarkan mode:
    //   - readOnly + occupied  → info_outline (lihat detail pesanan)
    //   - readOnly + available → arrow_forward (pilih meja)
    //   - manajemen            → edit_outlined (edit struktur)
    final trailingIcon = isReadOnly
        ? (isOccupied ? Icons.info_outline : Icons.arrow_forward_ios)
        : Icons.edit_outlined;

    return Container(
      decoration: BoxDecoration(
        color: isReadOnly && isOccupied
            ? kDanger.withValues(alpha: 0.04)
            : kBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isReadOnly && isOccupied
              ? kDanger.withValues(alpha: 0.25)
              : kDivider,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: double.infinity,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(12),
              ),
            ),
          ),
          const Gap(10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  table.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  isReadOnly && isOccupied
                      ? 'Terisi · Lihat pesanan'
                      : '${table.capacity} Kursi',
                  style: TextStyle(
                    fontSize: 10,
                    color: isReadOnly && isOccupied ? kDanger : kTextMid,
                    fontWeight: isReadOnly && isOccupied
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          // Trailing area: ikon-ikon action.
          // Mode manajemen → ikon QR tap-able (entry point primary fitur QR
          // menu) + ikon edit affordance untuk tap di body tile.
          // Mode kasir → cuma ikon affordance untuk tap.
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onQrTap != null)
                  // Inner GestureDetector mencegat tap supaya tidak bubble ke
                  // parent (yang trigger form edit). Pakai HitTestBehavior
                  // .opaque biar area icon penuh ter-deteksi.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onQrTap,
                    child: Tooltip(
                      message: 'Buat QR Menu',
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.qr_code_2,
                          size: 18,
                          color: kPrimary,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 8),
                  child: Icon(
                    trailingIcon,
                    size: 16,
                    color: isReadOnly && isOccupied ? kDanger : kTextMid,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolve nama outlet dari outletsProvider berdasarkan outletId. Tidak
/// pernah throw — kalau outlet provider belum loaded / tidak match, balik
/// string kosong. Dialog & PDF QR card sudah handle outletName kosong
/// (hanya tidak menampilkan baris brand-nya).
String _resolveOutletName(WidgetRef ref, String? outletId) {
  final outlets = ref.read(outletsProvider).value ?? [];
  if (outlets.isEmpty) return '';
  for (final o in outlets) {
    if (o.remoteId == outletId) return o.name;
  }
  return outlets.first.name;
}

/// Buka dialog QR untuk satu meja. Brand outlet tampil di QR card supaya
/// customer yang scan tahu mereka memesan dari mana.
Future<void> _showQrDialog(
  BuildContext context,
  WidgetRef ref,
  PosTable table,
) async {
  final outletName = _resolveOutletName(ref, table.outletRemoteId);
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => TableQrDialog(table: table, outletName: outletName),
  );
}

/// Print/preview semua QR meja di satu area sebagai PDF (grid 2x2 per halaman A4).
Future<void> _printAreaQr(
  BuildContext context,
  WidgetRef ref,
  TableGroup group,
) async {
  if (group.tables.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tidak ada meja di area ini')),
    );
    return;
  }
  final outletName = _resolveOutletName(ref, group.outletRemoteId);
  await printOutletQrSheet(tables: group.tables, outletName: outletName);
}
