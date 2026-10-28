// C4: akses data modifier/add-on.
//  - KASIR (read): grup untuk sebuah produk saat menambah item.
//  - MANAJEMEN (read-write): CRUD grup per-outlet + attach ke produk.
// Di-cache per-produk / per-outlet lewat FutureProvider.family.

import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/offline/entity_cache.dart';
import '../../../core/offline/sale_outbox.dart' show isOfflineError;
import '../../outlet/data/outlet_service.dart';
import '../domain/modifier_group.dart';

/// Salinan JSON mentah grup modifier per produk, untuk kasir offline. Disimpan
/// apa adanya dari server (bukan lewat ModifierGroup.toJson, yang merupakan
/// payload simpan dan tidak memuat id), jadi dibaca kembali tanpa kehilangan
/// apa pun. Kunci baris: `outletId/productId`.
final _cacheGrupProduk = EntityCache<Map<String, dynamic>>(
  'modifier_groups_produk',
  toJson: (j) => j,
  fromJson: (j) => j,
);

/// Batas tunggu mengambil grup modifier saat MENAMBAH ITEM. Lebih lama dari
/// ini, kasir menunggu di depan pelanggan — lebih baik pakai salinan lokal.
const _batasTungguModifier = Duration(seconds: 4);

class ModifierRepository {
  final Ref _ref;
  ModifierRepository(this._ref);

  OutletService get _svc => _ref.read(outletServiceProvider);

  // ── Kasir (read) ──────────────────────────────────────────────────

  /// Grup modifier sebuah produk untuk KASIR.
  ///
  /// # SAAT OFFLINE
  ///
  /// Tidak menyentuh jaringan sama sekali: langsung salinan lokal. Dulu
  /// permintaan ini tetap dikirim dan baru menyerah setelah jaringan gagal —
  /// di Wi-Fi tanpa internet itu bisa 10 detik, ditambah percobaan ulang
  /// otomatis Riverpod. Selama itu tombol "+" tampak mati, jadi kasir tak bisa
  /// menambah item sama sekali.
  ///
  /// Saat online, hasil yang berhasil diambil disimpan untuk dipakai offline.
  /// Produk yang belum pernah dibuka saat online tak punya salinan → offline
  /// ia ditambahkan tanpa add-on (bukan diblokir).
  Future<List<ModifierGroup>> groupsForProduct(
    String outletId,
    String productId, {
    bool offline = false,
  }) async =>
      (await ambilGrupKasir(outletId, productId, offline: offline)).grup;

  /// Seperti [groupsForProduct], plus apakah hasilnya dari salinan lokal
  /// (offline / server tak menjawab tepat waktu) — hasil semacam itu jangan
  /// disimpan lama di memori, supaya ketukan berikutnya mencoba server lagi.
  Future<({List<ModifierGroup> grup, bool dariSalinan})> ambilGrupKasir(
    String outletId,
    String productId, {
    bool offline = false,
  }) async {
    final kunci = '$outletId/$productId';
    List<Map<String, dynamic>> mentah;
    var dariSalinan = false;
    if (offline) {
      mentah = await _bacaSalinan(kunci);
      dariSalinan = true;
    } else {
      try {
        mentah =
            (await _svc
                    .getProductModifierGroups(outletId, productId)
                    .timeout(_batasTungguModifier))
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
        unawaited(
          _cacheGrupProduk.replaceAll(kunci, mentah).catchError((_) {}),
        );
      } catch (e) {
        if (e is! TimeoutException && !isOfflineError(e)) rethrow;
        mentah = await _bacaSalinan(kunci);
        dariSalinan = true;
      }
    }
    final grup = mentah
        .map(ModifierGroup.fromJson)
        // Hanya grup yang punya opsi (aktif) relevan ditampilkan di kasir.
        .where((g) => g.options.isNotEmpty)
        .toList();
    return (grup: grup, dariSalinan: dariSalinan);
  }

  Future<List<Map<String, dynamic>>> _bacaSalinan(String kunci) async {
    try {
      return await _cacheGrupProduk.getAll(kunci);
    } catch (_) {
      return const [];
    }
  }

  /// ID grup yang saat ini melekat pada produk (tanpa filter opsi) — dipakai
  /// untuk inisialisasi dialog attach di form produk.
  Future<Set<String>> attachedGroupIds(
    String outletId,
    String productId,
  ) async {
    final list = await _svc.getProductModifierGroups(outletId, productId);
    return list
        .map((j) => j['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  // ── Manajemen (read-write) ────────────────────────────────────────

  Future<List<ModifierGroup>> listGroups(String outletId) async {
    final list = await _svc.listModifierGroups(outletId);
    return list.map(ModifierGroup.fromJson).toList();
  }

  Future<void> createGroup(String outletId, ModifierGroup group) =>
      _svc.createModifierGroup(outletId, group.toJson());

  Future<void> updateGroup(String outletId, String id, ModifierGroup group) =>
      _svc.updateModifierGroup(outletId, id, group.toJson());

  Future<void> deleteGroup(String outletId, String id) =>
      _svc.deleteModifierGroup(outletId, id);

  Future<void> setProductGroups(
    String outletId,
    String productId,
    List<String> groupIds,
  ) =>
      _svc.setProductModifierGroups(outletId, productId, groupIds);
}

final modifierRepositoryProvider = Provider<ModifierRepository>((ref) {
  return ModifierRepository(ref);
});

/// Grup modifier untuk (outletId, productId), dari server; disimpan di memori
/// per produk supaya ketukan berikutnya instan.
///
/// - Tanpa retry otomatis: percobaan ulang Riverpod hanya memperpanjang waktu
///   tunggu kasir di depan pelanggan.
/// - Hasil dari salinan lokal (server tak menjawab tepat waktu) dibuang dari
///   memori setelah dipakai, supaya ketukan berikutnya mencoba server lagi.
///
/// Saat OFFLINE jangan lewat provider ini — panggil
/// [ModifierRepository.groupsForProduct] dengan `offline: true`, yang tak
/// menyentuh jaringan (lihat ProductCard).
final productModifierGroupsProvider =
    FutureProvider.family<
      List<ModifierGroup>,
      ({String outletId, String productId})
    >((ref, arg) async {
      if (arg.outletId.isEmpty || arg.productId.isEmpty) return const [];
      final hasil = await ref
          .read(modifierRepositoryProvider)
          .ambilGrupKasir(arg.outletId, arg.productId);
      if (hasil.dariSalinan) Future.microtask(ref.invalidateSelf);
      return hasil.grup;
    }, retry: (_, _) => null);

/// Semua grup modifier milik outlet — halaman manajemen & dialog attach.
final modifierGroupsProvider =
    FutureProvider.family<List<ModifierGroup>, String>((ref, outletId) async {
  if (outletId.isEmpty) return const [];
  return ref.read(modifierRepositoryProvider).listGroups(outletId);
});
