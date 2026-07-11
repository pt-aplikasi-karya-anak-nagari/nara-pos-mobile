import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:gap/gap.dart';

import '../../../app/theme.dart';
import '../../../core/format.dart';
import '../data/shift_api_service.dart';
import '../data/shift_repository.dart';

/// Bottom-sheet catat kas masuk/keluar (petty cash) untuk shift aktif (B7).
/// Setelah catat, expected balance shift ikut ter-update (invalidate
/// activeShiftProvider) sehingga selisih kas saat tutup bisa dijelaskan.
class CashMovementSheet extends HookConsumerWidget {
  final String shiftId;
  const CashMovementSheet({super.key, required this.shiftId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = useState('out'); // default kas keluar (paling sering dicatat)
    final amountCtrl = useTextEditingController();
    final noteCtrl = useTextEditingController();
    final saving = useState(false);
    final movementsAsync = ref.watch(cashMovementsProvider(shiftId));

    Future<void> submit() async {
      final amount = parseRupiahInput(amountCtrl.text).toDouble();
      if (amount <= 0 || saving.value) return;
      saving.value = true;
      try {
        await ref
            .read(shiftApiServiceProvider)
            .addCashMovement(
              shiftId,
              type: type.value,
              amount: amount,
              note: noteCtrl.text.trim(),
            );
        amountCtrl.clear();
        noteCtrl.clear();
        ref.invalidate(cashMovementsProvider(shiftId));
        ref.invalidate(activeShiftProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mencatat kas: $e'), backgroundColor: kDanger),
          );
        }
      } finally {
        saving.value = false;
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kas Masuk / Keluar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kTextDark),
              ),
              const Gap(4),
              Text(
                'Catat uang masuk/keluar laci di luar penjualan (beli galon, uang bensin, setor ke owner).',
                style: TextStyle(color: kTextMid, fontSize: 12),
              ),
              const Gap(16),
              Row(
                children: [
                  Expanded(
                    child: _TypeButton(
                      label: 'Kas Keluar',
                      active: type.value == 'out',
                      color: kDanger,
                      onTap: () => type.value = 'out',
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: _TypeButton(
                      label: 'Kas Masuk',
                      active: type.value == 'in',
                      color: kSuccess,
                      onTap: () => type.value = 'in',
                    ),
                  ),
                ],
              ),
              const Gap(12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: _dec('Nominal (Rp)'),
                onChanged: (v) {
                  final s = formatRupiah(parseRupiahInput(v));
                  amountCtrl.value = amountCtrl.value.copyWith(
                    text: s,
                    selection: TextSelection.collapsed(offset: s.length),
                  );
                },
              ),
              const Gap(8),
              TextField(controller: noteCtrl, decoration: _dec('Catatan (mis. beli galon)')),
              const Gap(12),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: saving.value ? null : submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(saving.value ? 'Menyimpan…' : 'Simpan'),
                ),
              ),
              const Gap(20),
              Text(
                'Riwayat kas shift ini',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kTextDark),
              ),
              const Gap(8),
              movementsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Gagal memuat: $e', style: TextStyle(color: kDanger, fontSize: 12)),
                data: (list) {
                  if (list.isEmpty) {
                    return Text('Belum ada catatan kas.', style: TextStyle(color: kTextMid, fontSize: 12));
                  }
                  return Column(
                    children: list.map((m) {
                      final isIn = (m['type']?.toString() ?? 'out') == 'in';
                      final amount = (m['amount'] as num?)?.toDouble() ?? 0;
                      final note = m['note']?.toString() ?? '';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              isIn ? Icons.south_west : Icons.north_east,
                              size: 16,
                              color: isIn ? kSuccess : kDanger,
                            ),
                            const Gap(8),
                            Expanded(
                              child: Text(
                                note.isEmpty ? (isIn ? 'Kas masuk' : 'Kas keluar') : note,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${isIn ? '+' : '−'} ${formatRupiah(amount)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: isIn ? kSuccess : kDanger,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: kBg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: kDivider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: kDivider),
    ),
  );
}

class _TypeButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _TypeButton({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : kBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? color : kDivider, width: active ? 1.5 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: active ? color : kTextMid,
          ),
        ),
      ),
    );
  }
}
