import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/format.dart';
import '../../../products/domain/modifier_group.dart';
import '../../domain/cart_item.dart';

/// C4: sheet pemilihan modifier/add-on saat menambahkan produk ke keranjang.
/// Menghormati aturan per grup (wajib/opsional, single/multi, maks). Mengembalikan
/// daftar CartModifier terpilih via Navigator.pop, atau null bila dibatalkan.
class ModifierSheet extends StatefulWidget {
  final String productName;
  final double basePrice;
  final List<ModifierGroup> groups;

  const ModifierSheet({
    super.key,
    required this.productName,
    required this.basePrice,
    required this.groups,
  });

  @override
  State<ModifierSheet> createState() => _ModifierSheetState();
}

class _ModifierSheetState extends State<ModifierSheet> {
  // groupId -> set of selected optionId.
  final Map<String, Set<String>> _selected = {};

  @override
  void initState() {
    super.initState();
    for (final g in widget.groups) {
      _selected[g.id] = <String>{};
      // Grup wajib single-choice → preselect opsi pertama supaya default valid.
      if (g.required && g.singleChoice && g.options.isNotEmpty) {
        _selected[g.id]!.add(g.options.first.id);
      }
    }
  }

  void _toggle(ModifierGroup g, ModifierOption o) {
    setState(() {
      final sel = _selected[g.id]!;
      if (g.singleChoice) {
        sel
          ..clear()
          ..add(o.id);
        return;
      }
      if (sel.contains(o.id)) {
        sel.remove(o.id);
      } else {
        // Hormati maks (0 = tak terbatas).
        if (g.maxSelect > 0 && sel.length >= g.maxSelect) return;
        sel.add(o.id);
      }
    });
  }

  bool get _valid {
    for (final g in widget.groups) {
      final n = _selected[g.id]!.length;
      if (n < g.minSelect) return false;
      if (g.maxSelect > 0 && n > g.maxSelect) return false;
    }
    return true;
  }

  List<CartModifier> _build() {
    final out = <CartModifier>[];
    for (final g in widget.groups) {
      for (final o in g.options) {
        if (_selected[g.id]!.contains(o.id)) {
          out.add(CartModifier(
            groupId: g.id,
            groupName: g.name,
            optionId: o.id,
            name: o.name,
            price: o.price,
          ));
        }
      }
    }
    return out;
  }

  double get _addOnTotal =>
      _build().fold<double>(0, (s, m) => s + m.price);

  String _rule(ModifierGroup g) {
    if (g.singleChoice) return g.required ? 'Pilih 1 · wajib' : 'Pilih 1';
    final maxTxt = g.maxSelect == 0 ? 'bebas' : 'maks ${g.maxSelect}';
    return g.required ? 'Pilih ${g.minSelect}–$maxTxt · wajib' : 'Pilih s/d $maxTxt';
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: kDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.productName,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: kTextDark,
                      ),
                    ),
                  ),
                  Text(
                    formatRupiah(widget.basePrice),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: kTextMid,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                itemCount: widget.groups.length,
                itemBuilder: (_, gi) {
                  final g = widget.groups[gi];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 6),
                        child: Row(
                          children: [
                            Text(
                              g.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: kTextDark,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _rule(g),
                              style: TextStyle(
                                fontSize: 11,
                                color: g.required ? kDanger : kTextMid,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...g.options.map((o) {
                        final on = _selected[g.id]!.contains(o.id);
                        return InkWell(
                          onTap: () => _toggle(g, o),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: on ? kPrimary.withValues(alpha: 0.08) : kBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: on ? kPrimary : kDivider,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  g.singleChoice
                                      ? (on
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked)
                                      : (on
                                          ? Icons.check_box
                                          : Icons.check_box_outline_blank),
                                  size: 18,
                                  color: on ? kPrimary : kTextMid,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    o.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight:
                                          on ? FontWeight.w700 : FontWeight.w500,
                                      color: kTextDark,
                                    ),
                                  ),
                                ),
                                if (o.price > 0)
                                  Text(
                                    '+${formatRupiah(o.price)}',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: kPrimary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + viewInsets * 0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _valid
                      ? () => Navigator.pop(context, _build())
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    disabledBackgroundColor: kTextLight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _addOnTotal > 0
                        ? 'Tambah · ${formatRupiah(widget.basePrice + _addOnTotal)}'
                        : 'Tambah ke keranjang',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
