import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nara_pos_mobile/features/outlet/data/outlet_service.dart';
import 'package:nara_pos_mobile/features/products/data/modifier_repository.dart';
import 'package:nara_pos_mobile/features/products/domain/modifier_group.dart';

// Laporan: saat offline, sheet pilihan add-on (Ukuran, Topping) tak muncul.
// Salinan add-on hanya ada untuk produk yang pernah dibuka sambil online.
// Kini add-on SELURUH produk diunduh sekaligus dan disimpan per produk.

class _AdapterTetap implements HttpClientAdapter {
  _AdapterTetap(this.body);
  final Object body;
  String? path;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    path = options.path;
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _grup(String id, String nama, List<(String, num)> opsi) =>
    {
      'id': id,
      'name': nama,
      'min_select': 0,
      'max_select': 1,
      'sort_order': 0,
      'options': [
        for (final (n, h) in opsi) {'id': '$id-$n', 'name': n, 'price': h},
      ],
    };

void main() {
  test('jawaban server diurai per produk', () async {
    final adapter = _AdapterTetap({
      'success': true,
      'data': {
        'teh': [
          _grup('G1', 'Ukuran', [('Reguler', 5000), ('Large', 7000)]),
          _grup('G2', 'Topping', [('Boba', 3000)]),
        ],
      },
    });
    final dio = Dio()..httpClientAdapter = adapter;

    final semua = await OutletService(dio).getAllProductModifierGroups('o1');
    expect(adapter.path, '/outlets/o1/product-modifier-groups');
    expect(semua.keys, ['teh']);

    final grup = semua['teh']!.map(ModifierGroup.fromJson).toList();
    expect(grup.map((g) => g.name), ['Ukuran', 'Topping']);
    expect(grup.first.options.map((o) => o.name), ['Reguler', 'Large']);
  });

  test('disimpan dengan kunci yang dibaca kartu produk saat offline', () {
    final baris = ModifierRepository.susunSalinanAddOn(
      'o1',
      {
        'teh': [
          _grup('G1', 'Ukuran', [('Reguler', 5000)]),
        ],
      },
      idProdukLokal: ['teh', 'kopi'],
    );
    expect(baris.keys, unorderedEquals(['o1/teh', 'o1/kopi']));
    expect(baris['o1/teh'], hasLength(1));
  });

  test('add-on yang dilepas dari produk tidak tersisa di salinan', () {
    // Kopi dulu punya add-on; kini server tak mengirimnya lagi. Salinannya
    // harus ditimpa kosong, bukan dibiarkan dengan add-on lama.
    final baris = ModifierRepository.susunSalinanAddOn(
      'o1',
      const {},
      idProdukLokal: ['kopi'],
    );
    expect(baris, {'o1/kopi': isEmpty});
  });
}
