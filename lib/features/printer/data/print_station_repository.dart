// E11: fetch konfigurasi stasiun cetak per outlet dari backend.

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/outlet_scope.dart';
import '../../outlet/data/outlet_service.dart';
import '../domain/print_station.dart';

class PrintStationRepository {
  final Ref _ref;
  PrintStationRepository(this._ref);

  Future<List<PrintStation>> getAll(String outletId) async {
    final list =
        await _ref.read(outletServiceProvider).getPrintStations(outletId);
    return list.map(PrintStation.fromJson).toList();
  }
}

final printStationRepositoryProvider = Provider<PrintStationRepository>((ref) {
  return PrintStationRepository(ref);
});

/// Stasiun cetak outlet aktif. Kosong bila outlet belum dipilih / belum ada
/// stasiun — konsumen (print flow) harus fallback ke satu grup default.
final printStationsFutureProvider =
    FutureProvider<List<PrintStation>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return const [];
  return ref.watch(printStationRepositoryProvider).getAll(outletId);
});
