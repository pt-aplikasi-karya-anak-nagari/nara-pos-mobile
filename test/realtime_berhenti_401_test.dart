import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/core/realtime/realtime_service.dart';

/// Adapter palsu: tiap permintaan dijawab [status] dan dihitung.
class _AdapterTetap implements HttpClientAdapter {
  _AdapterTetap(this.status);
  final int status;
  int dipanggil = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    dipanggil++;
    return ResponseBody.fromString(
      '{"success":false,"message":"token tidak valid"}',
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// Sesi kasir yang tak berlaku lagi dulu membuat koneksi realtime dicoba ulang
// tiap 30 detik SELAMANYA dengan token yang sama — log backend penuh
// "token tidak valid" dan toast berulang. 401/403 kini menghentikan stream;
// provider menyambung lagi sendiri setelah login baru.
void main() {
  for (final status in [401, 403]) {
    test('status $status → stream berhenti, tidak dicoba ulang', () async {
      final adapter = _AdapterTetap(status);
      final dio = Dio(BaseOptions(baseUrl: 'http://uji.invalid'))
        ..httpClientAdapter = adapter;
      final status_ = <bool>[];

      final events = await RealtimeService(dio)
          .connect('outlet-uji', onStatus: status_.add)
          .toList()
          .timeout(const Duration(seconds: 5));

      expect(events, isEmpty);
      expect(adapter.dipanggil, 1, reason: 'harus berhenti setelah satu tolakan');
      expect(status_, [false]);
    });
  }
}
