import 'package:flutter_riverpod/legacy.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../features/user/data/auth_service.dart';
import '../features/outlet/domain/outlet.dart';
import '../features/outlet/data/outlet_service.dart';

/// Outlet ID efektif (Remote ID) untuk kueri data (riwayat, laporan, dll.).
/// Selalu terkunci ke outlet pertama yang terdaftar untuk user tersebut.
/// State untuk menyimpan outlet yang dipilih secara manual oleh user (terutama owner).
final selectedOutletIdProvider = StateProvider<String?>((ref) => null);

/// Outlet ID efektif (Remote ID) untuk kueri data (riwayat, laporan, dll.).
/// Mengutamakan pilihan manual, jika tidak ada baru default ke outlet pertama.
final activeOutletIdProvider = Provider<String?>((ref) {
  final selectedId = ref.watch(selectedOutletIdProvider);
  if (selectedId != null) return selectedId;

  final user = ref.watch(authProvider).user;
  return user?.outletRemoteIds.firstOrNull;
});

/// Outlet penuh yang sedang aktif sebagai objek, atau `null` jika mode
/// "semua outlet" (owner) atau user belum terautentikasi.
final activeOutletProvider = Provider<Outlet?>((ref) {
  final id = ref.watch(activeOutletIdProvider);
  if (id == null) return null;

  final outletsAsync = ref.watch(outletsProvider);
  return outletsAsync.value?.where((o) => o.remoteId == id).firstOrNull;
});

/// Label teks untuk outlet aktif, ditampilkan di header/chip.
final activeOutletLabelProvider = Provider<String>((ref) {
  final outlet = ref.watch(activeOutletProvider);
  return outlet?.name ?? '';
});
