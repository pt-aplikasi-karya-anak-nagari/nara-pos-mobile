// E11: stasiun cetak per outlet + logika routing item → stasiun berdasarkan
// kategori produk. Model & helper ini SENGAJA murni (tanpa I/O) supaya bisa
// diuji dan dipakai ulang saat print-flow (ESC/POS) di-wire ke printer fisik.

class PrintStation {
  final String id;
  final String outletId;
  final String name;

  /// Target printer: "IP:PORT" untuk printer jaringan, atau label device
  /// bluetooth/USB. Kosong = belum diatur (fallback ke printer default app).
  final String target;

  /// Kategori produk yang dirutekan ke stasiun ini. Kosong = menerima SEMUA
  /// kategori (stasiun catch-all).
  final List<String> categoryIds;

  final bool isActive;

  const PrintStation({
    required this.id,
    required this.outletId,
    required this.name,
    this.target = '',
    this.categoryIds = const [],
    this.isActive = true,
  });

  /// Apakah stasiun ini menerima [categoryId]. Stasiun tanpa filter kategori
  /// menerima semua (mirror entity.PrintStation.RoutesCategory di backend).
  bool routesCategory(String? categoryId) {
    if (categoryIds.isEmpty) return true;
    if (categoryId == null) return false;
    return categoryIds.contains(categoryId);
  }

  factory PrintStation.fromJson(Map<String, dynamic> j) {
    final rawCats = j['category_ids'];
    return PrintStation(
      id: j['id']?.toString() ?? '',
      outletId: j['outlet_id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      target: j['target']?.toString() ?? '',
      categoryIds: rawCats is List
          ? rawCats.map((e) => e.toString()).toList()
          : const [],
      isActive: j['is_active'] as bool? ?? true,
    );
  }
}

/// Satu grup hasil routing: stasiun + item yang dirutekan ke sana.
class StationGroup<T> {
  final PrintStation? station; // null = bucket "tak terutekan" (Lainnya)
  final List<T> items;
  const StationGroup(this.station, this.items);

  String get label => station?.name ?? 'Lainnya';
}

/// Routing item pesanan ke stasiun cetak berdasarkan kategori.
///
/// Aturan:
///   - Hanya stasiun aktif yang dipertimbangkan.
///   - Sebuah item masuk ke SEMUA stasiun yang menerima kategorinya (satu item
///     bisa muncul di >1 stasiun bila konfigurasinya begitu — mis. dua stasiun
///     yang keduanya filter kategori yang sama). Umumnya kategori dipetakan ke
///     satu stasiun, jadi 1 item → 1 stasiun.
///   - Item yang tak cocok stasiun mana pun masuk bucket "Lainnya" (station=null)
///     supaya TIDAK PERNAH hilang dari struk.
///
/// Urutan grup mengikuti urutan [stations]; bucket "Lainnya" (bila ada) terakhir.
List<StationGroup<T>> groupItemsByStation<T>({
  required List<T> items,
  required List<PrintStation> stations,
  required String? Function(T item) categoryOf,
}) {
  final active = stations.where((s) => s.isActive).toList();
  if (active.isEmpty) {
    // Tanpa konfigurasi stasiun → semua item satu grup "Lainnya".
    return items.isEmpty ? const [] : [StationGroup<T>(null, List.of(items))];
  }

  final groups = <StationGroup<T>>[];
  final routedIndexes = <int>{};

  for (final station in active) {
    final matched = <T>[];
    for (var i = 0; i < items.length; i++) {
      if (station.routesCategory(categoryOf(items[i]))) {
        matched.add(items[i]);
        routedIndexes.add(i);
      }
    }
    if (matched.isNotEmpty) groups.add(StationGroup<T>(station, matched));
  }

  // Item yang tak masuk stasiun mana pun → bucket Lainnya (jangan hilang).
  final leftover = <T>[];
  for (var i = 0; i < items.length; i++) {
    if (!routedIndexes.contains(i)) leftover.add(items[i]);
  }
  if (leftover.isNotEmpty) groups.add(StationGroup<T>(null, leftover));

  return groups;
}
