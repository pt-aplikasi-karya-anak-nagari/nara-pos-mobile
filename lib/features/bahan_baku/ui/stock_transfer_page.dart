import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../app/theme.dart';
import '../../../core/format.dart';
import '../../../core/outlet_scope.dart';
import '../../outlet/data/outlet_service.dart';
import '../data/bahan_baku_service.dart';

/// Format kuantitas double tanpa trailing `.0` bila bulat.
String _qtyText(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Transfer stok bahan baku antar-outlet (B2). Tab "Transfer Baru" untuk membuat
/// transfer dari outlet aktif (asal) ke outlet tujuan, dan tab "Riwayat" untuk
/// melihat transfer lampau + detailnya.
class StockTransferPage extends ConsumerStatefulWidget {
  const StockTransferPage({super.key});

  @override
  ConsumerState<StockTransferPage> createState() => _StockTransferPageState();
}

/// Draft satu baris transfer di form. [id] dipakai sebagai key stabil agar
/// state field ikut baris yang benar saat baris ditambah/dihapus.
class _LineDraft {
  static int _seq = 0;
  final int id = _seq++;
  String? fromId;
  String? toId;
  final TextEditingController qty = TextEditingController();
}

class _StockTransferPageState extends ConsumerState<StockTransferPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );
  String? _destOutletId;
  final _noteCtrl = TextEditingController();
  final List<_LineDraft> _lines = [_LineDraft()];
  bool _submitting = false;

  @override
  void dispose() {
    _tabController.dispose();
    _noteCtrl.dispose();
    for (final l in _lines) {
      l.qty.dispose();
    }
    super.dispose();
  }

  void _onDestChanged(String? id) {
    setState(() {
      _destOutletId = id;
      // Bahan tujuan sebelumnya tidak lagi valid untuk outlet baru.
      for (final l in _lines) {
        l.toId = null;
      }
    });
  }

  Future<void> _submit() async {
    final fromOutletId = ref.read(activeOutletIdProvider);
    if (fromOutletId == null) return;
    if (_destOutletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih outlet tujuan terlebih dahulu.')),
      );
      return;
    }

    final items = <({String fromIngredientId, String toIngredientId, double qty})>[];
    for (final l in _lines) {
      final qty = double.tryParse(l.qty.text.replaceAll(',', '.')) ?? 0;
      if (l.fromId == null || l.toId == null || qty <= 0) continue;
      items.add(
        (fromIngredientId: l.fromId!, toIngredientId: l.toId!, qty: qty),
      );
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lengkapi minimal satu baris transfer (bahan & qty).'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(bahanBakuServiceProvider).createStockTransfer(
            fromOutletId,
            toOutletId: _destOutletId!,
            note: _noteCtrl.text,
            items: items,
          );
      // Stok kedua outlet berubah → refresh sumber & tujuan + riwayat.
      ref.invalidate(ingredientsProvider);
      ref.invalidate(stockTransfersProvider);
      ref.invalidate(outletIngredientsProvider(_destOutletId!));
      if (!mounted) return;
      setState(() {
        _submitting = false;
        for (final l in _lines) {
          l.qty.dispose();
        }
        _lines
          ..clear()
          ..add(_LineDraft());
        _noteCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transfer stok berhasil')),
      );
      _tabController.animateTo(1);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: $e'), backgroundColor: kDanger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Transfer Stok'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Transfer Baru'),
            Tab(text: 'Riwayat'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCreateTab(),
          const _TransferHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildCreateTab() {
    final activeOutletId = ref.watch(activeOutletIdProvider);
    final outletsAsync = ref.watch(outletsProvider);
    final srcAsync = ref.watch(ingredientsProvider);

    final destOutlets = (outletsAsync.value ?? const [])
        .where((o) => o.remoteId != null && o.remoteId != activeOutletId)
        .toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Outlet Tujuan',
                      style: TextStyle(
                        color: kTextMid,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Gap(8),
                    DropdownButtonFormField<String>(
                      initialValue: _destOutletId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        hintText: 'Pilih outlet tujuan',
                      ),
                      items: [
                        for (final o in destOutlets)
                          DropdownMenuItem(
                            value: o.remoteId,
                            child: Text(o.name, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _onDestChanged,
                    ),
                    if (destOutlets.isEmpty) ...[
                      const Gap(8),
                      Text(
                        'Tidak ada outlet lain sebagai tujuan.',
                        style: TextStyle(color: kTextMid, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const Gap(10),
              if (_destOutletId != null)
                srcAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => _card(
                    child: Text(
                      'Gagal memuat bahan sumber: $e',
                      style: TextStyle(color: kDanger),
                    ),
                  ),
                  data: (srcIngredients) => _buildLinesSection(srcIngredients),
                ),
              const Gap(12),
              _card(
                child: TextField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                    hintText: 'mis. Kirim ke cabang',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Kirim Transfer',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLinesSection(List<Ingredient> srcIngredients) {
    final destIngredientsAsync = ref.watch(
      outletIngredientsProvider(_destOutletId!),
    );

    return destIngredientsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _card(
        child: Text(
          'Gagal memuat bahan tujuan: $e',
          style: TextStyle(color: kDanger),
        ),
      ),
      data: (destIngredients) {
        if (srcIngredients.isEmpty) {
          return _card(
            child: Text(
              'Outlet asal belum punya bahan baku untuk ditransfer.',
              style: TextStyle(color: kTextMid),
            ),
          );
        }
        if (destIngredients.isEmpty) {
          return _card(
            child: Text(
              'Outlet tujuan belum punya bahan baku. Buat bahan di outlet '
              'tujuan lebih dulu (tidak dibuat otomatis).',
              style: TextStyle(color: kTextMid),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < _lines.length; i++)
              Padding(
                key: ValueKey('line_${_lines[i].id}'),
                padding: const EdgeInsets.only(bottom: 8),
                child: _lineCard(i, srcIngredients, destIngredients),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _lines.add(_LineDraft())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Tambah baris'),
                style: TextButton.styleFrom(foregroundColor: kPrimary),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _lineCard(
    int index,
    List<Ingredient> srcIngredients,
    List<Ingredient> destIngredients,
  ) {
    final line = _lines[index];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Bahan #${index + 1}',
                style: TextStyle(
                  color: kTextMid,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (_lines.length > 1)
                InkWell(
                  onTap: () => setState(() {
                    _lines.removeAt(index).qty.dispose();
                  }),
                  child: Icon(Icons.close, size: 18, color: kDanger),
                ),
            ],
          ),
          const Gap(8),
          DropdownButtonFormField<String>(
            initialValue: line.fromId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Bahan sumber (outlet asal)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final ing in srcIngredients)
                DropdownMenuItem(
                  value: ing.id,
                  child: Text(
                    '${ing.name} · ${_qtyText(ing.stock)} ${ing.unit}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => line.fromId = v),
          ),
          const Gap(4),
          Center(child: Icon(Icons.south, size: 18, color: kTextMid)),
          const Gap(4),
          DropdownButtonFormField<String>(
            // Key mengikutkan outlet tujuan supaya pilihan ter-reset (kosong)
            // saat outlet tujuan diganti.
            key: ValueKey('to_${line.id}_$_destOutletId'),
            initialValue: line.toId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Bahan tujuan (outlet tujuan)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final ing in destIngredients)
                DropdownMenuItem(
                  value: ing.id,
                  child: Text(
                    '${ing.name} · ${_qtyText(ing.stock)} ${ing.unit}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => line.toId = v),
          ),
          const Gap(8),
          TextField(
            controller: line.qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Jumlah transfer',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kDivider),
    ),
    child: child,
  );
}

/// Tab riwayat transfer stok pada outlet aktif (asal maupun tujuan).
class _TransferHistoryTab extends ConsumerWidget {
  const _TransferHistoryTab();

  Future<void> _showDetail(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    // Buat future sekali di luar builder — DraggableScrollableSheet.builder
    // dipanggil berkali-kali saat di-drag, jadi jangan re-fetch tiap frame.
    final detailFuture = ref.read(bahanBakuServiceProvider).getStockTransfer(id);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: FutureBuilder<StockTransfer>(
            future: detailFuture,
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError || !snap.hasData) {
                return Center(
                  child: Text(
                    'Gagal memuat detail: ${snap.error}',
                    style: TextStyle(color: kDanger),
                  ),
                );
              }
              final t = snap.data!;
              return ListView(
                controller: scrollCtrl,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: kDivider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Detail Transfer',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: kTextDark,
                    ),
                  ),
                  const Gap(4),
                  Text(
                    '${t.fromOutletName.isEmpty ? t.fromOutletId : t.fromOutletName} '
                    '→ ${t.toOutletName.isEmpty ? t.toOutletId : t.toOutletName}',
                    style: TextStyle(color: kTextMid, fontSize: 13),
                  ),
                  if (t.createdAt != null) ...[
                    const Gap(2),
                    Text(
                      formatDateTime(t.createdAt!),
                      style: TextStyle(color: kTextMid, fontSize: 12),
                    ),
                  ],
                  if (t.note.isNotEmpty) ...[
                    const Gap(6),
                    Text(
                      'Catatan: ${t.note}',
                      style: TextStyle(color: kTextDark, fontSize: 13),
                    ),
                  ],
                  const Gap(12),
                  for (final it in t.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${it.fromIngredientName.isEmpty ? it.fromIngredientId : it.fromIngredientName}'
                              ' → '
                              '${it.toIngredientName.isEmpty ? it.toIngredientId : it.toIngredientName}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const Gap(8),
                          Text(
                            _qtyText(it.qty),
                            style: TextStyle(
                              color: kPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeOutletId = ref.watch(activeOutletIdProvider);
    final async = ref.watch(stockTransfersProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text('Gagal memuat: $e', style: TextStyle(color: kDanger))),
      data: (transfers) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(stockTransfersProvider);
          await ref.read(stockTransfersProvider.future);
        },
        child: transfers.isEmpty
            ? ListView(
                children: [
                  const Gap(80),
                  Center(
                    child: Text(
                      'Belum ada transfer stok.',
                      style: TextStyle(color: kTextMid),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: transfers.length,
                separatorBuilder: (_, _) => const Gap(8),
                itemBuilder: (_, i) {
                  final t = transfers[i];
                  final isOutgoing = t.fromOutletId == activeOutletId;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _showDetail(context, ref, t.id),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: kDivider),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: (isOutgoing ? kDanger : kSuccess)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isOutgoing ? 'Keluar' : 'Masuk',
                              style: TextStyle(
                                color: isOutgoing ? kDanger : kSuccess,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Gap(10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${t.fromOutletName.isEmpty ? t.fromOutletId : t.fromOutletName}'
                                  ' → '
                                  '${t.toOutletName.isEmpty ? t.toOutletId : t.toOutletName}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (t.createdAt != null) ...[
                                  const Gap(2),
                                  Text(
                                    formatDateTime(t.createdAt!),
                                    style: TextStyle(
                                      color: kTextMid,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: kTextMid, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
