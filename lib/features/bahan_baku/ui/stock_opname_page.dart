import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../app/theme.dart';
import '../data/bahan_baku_service.dart';

/// Halaman full-screen Stock Opname bahan baku (B1). Menampilkan SELURUH bahan
/// dengan stok sistem + input "Stok fisik" (prefilled = stok saat ini). Saat
/// submit, hanya baris yang diubah user yang dikirim (server juga melewati
/// baris tanpa perubahan). Mengembalikan `changed_count` lewat Navigator.pop.
class StockOpnamePage extends ConsumerStatefulWidget {
  final String outletId;
  final List<Ingredient> ingredients;
  const StockOpnamePage({
    super.key,
    required this.outletId,
    required this.ingredients,
  });

  @override
  ConsumerState<StockOpnamePage> createState() => _StockOpnamePageState();
}

/// Format kuantitas double tanpa trailing `.0` bila bulat (dan parse-safe:
/// tanpa pemisah ribuan berlokal supaya bisa di-parse balik).
String _qtyText(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class _StockOpnamePageState extends ConsumerState<StockOpnamePage> {
  final _noteCtrl = TextEditingController();
  late final Map<String, TextEditingController> _ctrls;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _ctrls = {
      for (final ing in widget.ingredients)
        ing.id: TextEditingController(text: _qtyText(ing.stock)),
    };
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    // Kumpulkan hanya baris yang benar-benar berubah (optimasi; server juga
    // melewati no-op). Field kosong dianggap tak diubah agar tidak sengaja
    // menol-kan stok.
    final items = <({String ingredientId, double actualQty})>[];
    for (final ing in widget.ingredients) {
      final raw = _ctrls[ing.id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final actual = double.tryParse(raw.replaceAll(',', '.'));
      if (actual == null || actual < 0) continue;
      if ((actual - ing.stock).abs() > 1e-9) {
        items.add((ingredientId: ing.id, actualQty: actual));
      }
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada perubahan stok.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final changed = await ref
          .read(bahanBakuServiceProvider)
          .bulkOpname(widget.outletId, items, note: _noteCtrl.text);
      ref.invalidate(ingredientsProvider);
      if (!mounted) return;
      Navigator.pop(context, changed);
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
      appBar: AppBar(title: const Text('Stock Opname')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: kCard,
            child: TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                hintText: 'mis. Opname akhir bulan',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: widget.ingredients.length,
              separatorBuilder: (_, _) => const Gap(8),
              itemBuilder: (_, i) {
                final ing = widget.ingredients[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kDivider),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ing.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const Gap(2),
                            Text(
                              'Stok sistem: ${_qtyText(ing.stock)} ${ing.unit}',
                              style: TextStyle(color: kTextMid, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const Gap(10),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _ctrls[ing.id],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.end,
                          decoration: InputDecoration(
                            labelText: 'Stok fisik',
                            suffixText: ing.unit,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
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
                      'Simpan Opname',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
