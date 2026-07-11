import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../app/theme.dart';
import '../../../core/format.dart';
import '../data/bahan_baku_service.dart';

/// Halaman Bahan Baku & Resep (B1 di mobile). Staf/owner bisa cek stok bahan
/// + restock dari HP, dan lihat resep + HPP (read-only; kelola resep di web).
class BahanBakuPage extends ConsumerWidget {
  const BahanBakuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          title: const Text('Bahan Baku & Resep'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Bahan Baku'),
              Tab(text: 'Resep'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_IngredientsTab(), _RecipesTab()],
        ),
      ),
    );
  }
}

class _IngredientsTab extends ConsumerWidget {
  const _IngredientsTab();

  Future<void> _restock(BuildContext context, WidgetRef ref, Ingredient ing) async {
    final ctrl = TextEditingController();
    final isOut = ValueNotifier(false); // false = tambah, true = kurangi
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ing.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: isOut,
              builder: (_, out, _) => Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Tambah stok'),
                      selected: !out,
                      onSelected: (_) => isOut.value = false,
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Kurangi'),
                      selected: out,
                      onSelected: (_) => isOut.value = true,
                    ),
                  ),
                ],
              ),
            ),
            const Gap(12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Jumlah (${ing.unit})',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
              if (v <= 0) return;
              Navigator.pop(ctx, isOut.value ? -v : v);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (result == null || result == 0) return;
    try {
      await ref.read(bahanBakuServiceProvider).adjustStock(ing.id, result);
      ref.invalidate(ingredientsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e'), backgroundColor: kDanger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ingredientsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Gagal memuat: $e', style: TextStyle(color: kDanger))),
      data: (items) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(ingredientsProvider);
          await ref.read(ingredientsProvider.future);
        },
        child: items.isEmpty
            ? ListView(
                children: [
                  const Gap(80),
                  Center(
                    child: Text(
                      'Belum ada bahan baku.\nTambah & kelola di web.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kTextMid),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Gap(8),
                itemBuilder: (_, i) {
                  final ing = items[i];
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
                              Text(ing.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              const Gap(2),
                              Row(
                                children: [
                                  Text(
                                    '${ing.stock} ${ing.unit}',
                                    style: TextStyle(
                                      color: ing.isLowStock ? kDanger : kTextDark,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const Gap(8),
                                  Text('· ${formatRupiah(ing.costPerUnit)}/${ing.unit}', style: TextStyle(color: kTextMid, fontSize: 12)),
                                  if (ing.isLowStock) ...[
                                    const Gap(8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(color: kDanger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                                      child: Text('Rendah', style: TextStyle(color: kDanger, fontSize: 10, fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () => _restock(context, ref, ing),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kPrimary,
                            side: BorderSide(color: kPrimary.withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Restock'),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _RecipesTab extends ConsumerWidget {
  const _RecipesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recipesProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Gagal memuat: $e', style: TextStyle(color: kDanger))),
      data: (recipes) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(recipesProvider);
          await ref.read(recipesProvider.future);
        },
        child: recipes.isEmpty
            ? ListView(
                children: [
                  const Gap(80),
                  Center(
                    child: Text(
                      'Belum ada resep.\nBuat resep produk di web.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kTextMid),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: recipes.length,
                separatorBuilder: (_, _) => const Gap(8),
                itemBuilder: (_, i) {
                  final r = recipes[i];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kDivider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(r.productName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('HPP/porsi', style: TextStyle(color: kTextMid, fontSize: 10)),
                                Text(formatRupiah(r.hpp), style: TextStyle(color: kPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
                              ],
                            ),
                          ],
                        ),
                        const Gap(8),
                        ...r.items.map(
                          (it) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text('${it.ingredientName} · ${it.qty} ${it.ingredientUnit}', style: const TextStyle(fontSize: 12)),
                                ),
                                Text(formatRupiah(it.lineCost), style: TextStyle(color: kTextMid, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
