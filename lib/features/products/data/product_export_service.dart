import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../kasir/providers.dart';
import '../../outlet/data/outlet_service.dart';
import '../../../core/outlet_scope.dart';

class ProductExportService {
  ProductExportService(this._ref);
  final Ref _ref;

  Future<void> exportToCsv(String outletId) async {
    final csv = await _generateCsv(outletId);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/products_outlet_$outletId.csv');
    await file.writeAsString(csv);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'Export Products CSV'),
    );
  }

  Future<void> saveToCsv(String outletId) async {
    final csv = await _generateCsv(outletId);
    final bytes = utf8.encode(csv);

    await FilePicker.saveFile(
      dialogTitle: 'Simpan Data Produk',
      fileName: 'products_outlet_$outletId.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: bytes,
    );
  }

  Future<String> _generateCsv(String outletId) async {
    final productsAsync = _ref.read(productsStreamProvider);
    final products = productsAsync.value ?? [];
    // The provider already filters by active outlet, but we filter again just in case
    final outletProducts = products
        .where((p) => p.outletRemoteId == outletId)
        .toList();

    List<List<dynamic>> rows = [];
    rows.add([
      'Name',
      'Category',
      'Price',
      'SKU',
      'Barcode',
      'Stock',
      'TrackStock',
      'DiscountType',
      'DiscountValue',
      'DiscountName',
    ]);

    for (var p in outletProducts) {
      rows.add([
        p.name,
        p.categoryName ?? '',
        p.price,
        p.sku ?? '',
        p.barcode ?? '',
        p.stock,
        p.trackStock ? 1 : 0,
        p.discountType,
        p.discountValue,
        p.discountName,
      ]);
    }

    return const ListToCsvConverter().convert(rows);
  }

  Future<({int imported, int skipped})> importFromCsv(String outletId) async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result == null || result.files.single.path == null) {
      return (imported: 0, skipped: 0);
    }

    final file = File(result.files.single.path!);
    final bytes = await file.readAsBytes();
    final csvString = utf8.decode(bytes);

    final fields = const CsvToListConverter().convert(csvString);

    int imported = 0;
    int skipped = 0;
    final List<Map<String, dynamic>> payload = [];

    for (int i = 1; i < fields.length; i++) {
      final row = fields[i];
      if (row.length < 3) {
        skipped++;
        continue;
      }

      try {
        payload.add({
          'name': row[0].toString(),
          'category_name': row.length > 1 ? row[1].toString() : 'Umum',
          'price': double.tryParse(row[2].toString()) ?? 0.0,
          'sku': row.length > 3 ? row[3].toString() : '',
          'barcode': row.length > 4 ? row[4].toString() : '',
          'stock': row.length > 5 ? int.tryParse(row[5].toString()) ?? 0 : 0,
        });
        imported++;
      } catch (_) {
        skipped++;
      }
    }

    if (payload.isNotEmpty) {
      final effectiveOutletId = _ref.read(activeOutletIdProvider);
      if (effectiveOutletId != null) {
        await _ref.read(outletServiceProvider).batchCreateProducts(effectiveOutletId, payload);
        _ref.invalidate(outletCategoriesProvider);
      }
    }

    return (imported: imported, skipped: skipped);
  }
}

final productExportServiceProvider = Provider<ProductExportService>((ref) {
  return ProductExportService(ref);
});
