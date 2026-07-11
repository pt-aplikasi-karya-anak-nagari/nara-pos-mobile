import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../app/theme.dart';
import '../../../core/format.dart';
import '../../../core/outlet_scope.dart';
import '../data/expense_service.dart';

/// Pencatatan pengeluaran di mobile (C2) — total bulan ini + daftar + catat baru.
class ExpensesPage extends ConsumerWidget {
  const ExpensesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalAsync = ref.watch(expenseTotalProvider);
    final listAsync = ref.watch(expensesProvider);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: const Text('Pengeluaran')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Catat'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(expenseTotalProvider);
          ref.invalidate(expensesProvider);
          await ref.read(expensesProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: kPrimary,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total pengeluaran bulan ini', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                  const Gap(6),
                  totalAsync.when(
                    loading: () => const SizedBox(height: 30, width: 120, child: LinearProgressIndicator(color: Colors.white24)),
                    error: (_, _) => const Text('—', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                    data: (t) => Text(formatRupiah(t), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
            const Gap(16),
            listAsync.when(
              loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text('Gagal memuat: $e', style: TextStyle(color: kDanger))),
              data: (items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text('Belum ada pengeluaran bulan ini.', style: TextStyle(color: kTextMid))),
                  );
                }
                return Column(
                  children: items.map((e) => _ExpenseTile(expense: e)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ExpenseForm(),
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  final Expense expense;
  const _ExpenseTile({required this.expense});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
                Text(expense.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const Gap(2),
                Text(
                  '${expense.categoryName ?? 'Tanpa kategori'} · ${expense.paymentMethod}',
                  style: TextStyle(color: kTextMid, fontSize: 12),
                ),
              ],
            ),
          ),
          Text('- ${formatRupiah(expense.amount)}', style: TextStyle(color: kDanger, fontWeight: FontWeight.w800, fontSize: 14)),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 20, color: kTextMid),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Hapus pengeluaran?'),
                  content: Text(expense.title),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: kDanger), child: const Text('Hapus')),
                  ],
                ),
              );
              if (ok != true) return;
              try {
                await ref.read(expenseServiceProvider).deleteExpense(expense.id);
                ref.invalidate(expensesProvider);
                ref.invalidate(expenseTotalProvider);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e'), backgroundColor: kDanger));
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ExpenseForm extends ConsumerStatefulWidget {
  const _ExpenseForm();

  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  String? _categoryId;
  String _method = 'Tunai';
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final outletId = ref.read(activeOutletIdProvider);
    final amount = parseRupiahInput(_amount.text).toDouble();
    if (outletId == null || _title.text.trim().isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Judul & nominal wajib diisi.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(expenseServiceProvider).create(
            outletId,
            title: _title.text.trim(),
            amount: amount,
            categoryId: _categoryId,
            paymentMethod: _method,
            paidAt: DateTime.now(),
          );
      ref.invalidate(expensesProvider);
      ref.invalidate(expenseTotalProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e'), backgroundColor: kDanger));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(expenseCategoriesProvider);
    final categories = categoriesAsync.value ?? const <ExpenseCategory>[];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Catat Pengeluaran', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kTextDark)),
            const Gap(16),
            TextField(controller: _title, decoration: _dec('Judul (mis. Beli galon)')),
            const Gap(10),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: _dec('Nominal (Rp)'),
              onChanged: (v) {
                final s = formatRupiah(parseRupiahInput(v));
                _amount.value = _amount.value.copyWith(text: s, selection: TextSelection.collapsed(offset: s.length));
              },
            ),
            const Gap(10),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: _dec('Kategori'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tanpa kategori')),
                ...categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const Gap(10),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: _dec('Metode'),
              items: const [
                DropdownMenuItem(value: 'Tunai', child: Text('Tunai')),
                DropdownMenuItem(value: 'Transfer', child: Text('Transfer')),
                DropdownMenuItem(value: 'QRIS', child: Text('QRIS')),
              ],
              onChanged: (v) => setState(() => _method = v ?? 'Tunai'),
            ),
            const Gap(16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: kBg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kDivider)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kDivider)),
  );
}
