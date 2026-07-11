import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../app/theme.dart';
import '../../../core/outlet_scope.dart';
import '../data/inventory_service.dart';

/// Inventori produk di mobile (C1) — cek stok + restock/koreksi dari HP.
class InventoryPage extends ConsumerWidget {
  const InventoryPage({super.key});

  Future<void> _adjust(BuildContext context, WidgetRef ref, InventoryItem it) async {
    if (it.variantCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produk dengan varian: atur stok per varian di web.')),
      );
      return;
    }
    final ctrl = TextEditingController();
    final isReduce = ValueNotifier(false);
    final delta = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(it.productName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Stok saat ini: ${it.stock} ${it.stockUnit}', style: TextStyle(color: kTextMid)),
            const Gap(12),
            ValueListenableBuilder<bool>(
              valueListenable: isReduce,
              builder: (_, reduce, _) => Row(
                children: [
                  Expanded(child: ChoiceChip(label: const Text('Tambah'), selected: !reduce, onSelected: (_) => isReduce.value = false)),
                  const Gap(8),
                  Expanded(child: ChoiceChip(label: const Text('Kurangi'), selected: reduce, onSelected: (_) => isReduce.value = true)),
                ],
              ),
            ),
            const Gap(12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Jumlah (${it.stockUnit})', border: const OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text) ?? 0;
              if (v <= 0) return;
              Navigator.pop(ctx, isReduce.value ? -v : v);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (delta == null || delta == 0) return;
    final outletId = ref.read(activeOutletIdProvider);
    if (outletId == null) return;
    try {
      await ref.read(inventoryServiceProvider).adjust(outletId, it.productId, delta, reason: 'Penyesuaian dari HP');
      ref.invalidate(inventoryProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e'), backgroundColor: kDanger));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(inventoryProvider);
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: const Text('Inventori')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e', style: TextStyle(color: kDanger))),
        data: (items) {
          final tracked = items.where((i) => i.trackStock).toList();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(inventoryProvider);
              await ref.read(inventoryProvider.future);
            },
            child: tracked.isEmpty
                ? ListView(children: [
                    const Gap(80),
                    Center(child: Text('Belum ada produk yang mengelola stok.', style: TextStyle(color: kTextMid))),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: tracked.length,
                    separatorBuilder: (_, _) => const Gap(8),
                    itemBuilder: (_, i) {
                      final it = tracked[i];
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: kDivider),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(it.productName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                  const Gap(2),
                                  Row(
                                    children: [
                                      Text(
                                        '${it.stock} ${it.stockUnit}',
                                        style: TextStyle(
                                          color: it.isOutOfStock ? kDanger : (it.isLowStock ? kWarning : kTextDark),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (it.isOutOfStock) ...[
                                        const Gap(8),
                                        _badge('Habis', kDanger),
                                      ] else if (it.isLowStock) ...[
                                        const Gap(8),
                                        _badge('Rendah', kWarning),
                                      ],
                                      if (it.variantCount > 0) ...[
                                        const Gap(8),
                                        Text('${it.variantCount} varian', style: TextStyle(color: kTextMid, fontSize: 11)),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton(
                              onPressed: () => _adjust(context, ref, it),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: kPrimary,
                                side: BorderSide(color: kPrimary.withValues(alpha: 0.4)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Sesuaikan'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
  );
}
