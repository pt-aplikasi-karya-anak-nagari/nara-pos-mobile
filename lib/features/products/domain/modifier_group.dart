// C4: model modifier/add-on. Dipakai di dua sisi:
//   - KASIR (read): pilih add-on saat menambah item ke keranjang.
//   - MANAJEMEN (read-write): CRUD grup + opsi, padanan menu
//     "Modifier & Add-on" di dashboard web.
// Aturan pilih (encoded di grup, sama seperti backend & web):
//   - minSelect > 0  → wajib
//   - maxSelect == 0 → tak terbatas (multi bebas)
//   - maxSelect == 1 → single-choice
//   - maxSelect > 1  → multi, dibatasi maks.

class ModifierOption {
  final String id;
  final String name;
  final double price;
  final int sortOrder;
  final bool isActive;

  const ModifierOption({
    required this.id,
    required this.name,
    this.price = 0,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory ModifierOption.fromJson(Map<String, dynamic> j) => ModifierOption(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        isActive: j['is_active'] as bool? ?? true,
      );

  /// Payload untuk create/update grup. `id` disertakan bila mengedit opsi
  /// existing (backend mempertahankan ID); kosong = opsi baru.
  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'name': name,
        'price': price,
        'sort_order': sortOrder,
        'is_active': isActive,
      };
}

class ModifierGroup {
  final String id;
  final String name;
  final int minSelect;
  final int maxSelect;
  final int sortOrder;
  final List<ModifierOption> options;

  const ModifierGroup({
    required this.id,
    required this.name,
    this.minSelect = 0,
    this.maxSelect = 1,
    this.sortOrder = 0,
    this.options = const [],
  });

  bool get required => minSelect > 0;
  bool get singleChoice => maxSelect == 1;
  bool get unlimited => maxSelect == 0;

  factory ModifierGroup.fromJson(Map<String, dynamic> j) {
    final rawOpts = j['options'];
    return ModifierGroup(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      minSelect: (j['min_select'] as num?)?.toInt() ?? 0,
      maxSelect: (j['max_select'] as num?)?.toInt() ?? 1,
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      // Tidak memfilter is_active di sini: endpoint list/produk sudah
      // mengembalikan opsi aktif saja, sedangkan sisi manajemen butuh set
      // apa adanya. Kasir memfilter aktif secara eksplisit bila perlu.
      options: rawOpts is List
          ? rawOpts
              .map((e) => ModifierOption.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  /// Payload untuk POST/PUT grup. Opsi dikirim penuh (full-replace di backend).
  Map<String, dynamic> toJson() => {
        'name': name,
        'min_select': minSelect,
        'max_select': maxSelect,
        'sort_order': sortOrder,
        'options': [
          for (var i = 0; i < options.length; i++)
            {
              ...options[i].toJson(),
              // sort_order fallback ke urutan array bila belum di-set.
              'sort_order':
                  options[i].sortOrder != 0 ? options[i].sortOrder : i,
            },
        ],
      };
}

/// Label aturan pilih yang mudah dibaca — mirror `selectRuleLabel` di web.
String modifierRuleLabel(ModifierGroup g) {
  if (g.maxSelect == 1 && g.minSelect == 1) return 'Pilih 1 · wajib';
  if (g.maxSelect == 1) return 'Pilih 1 · opsional';
  final maxTxt = g.maxSelect == 0 ? 'bebas' : 'maks ${g.maxSelect}';
  return g.minSelect > 0
      ? 'Pilih ${g.minSelect}–$maxTxt · wajib'
      : 'Pilih s/d $maxTxt';
}
