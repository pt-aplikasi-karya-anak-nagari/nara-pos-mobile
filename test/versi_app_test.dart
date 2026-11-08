import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nara_pos_mobile/core/auth_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nara_pos_mobile/core/buka_url.dart';
import 'package:nara_pos_mobile/core/network/dio_client.dart';
import 'package:nara_pos_mobile/core/offline/sale_outbox.dart';
import 'package:nara_pos_mobile/core/versi_app.dart';

/// Adapter palsu: balas status & body tetap, catat header permintaan.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final Object body;
  Map<String, dynamic>? header;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    header = options.headers;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _tolak426 = {
  'success': false,
  'code': kodePerluUpdate,
  'message': 'Versi aplikasi kasir ini sudah tidak didukung.',
  'data': {'min_build': 7, 'update_url': 'https://play.example/nara'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('interceptor dio', () {
    late ProviderContainer c;
    late Dio dio;

    setUp(() async {
      VersiApp.build = 3;
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      c = ProviderContainer(
        overrides: [authStorageProvider.overrideWithValue(AuthStorage(prefs))],
      );
      dio = c.read(dioProvider);
    });
    tearDown(() {
      c.dispose();
      VersiApp.build = 0;
    });

    test('mengirim nomor build di X-App-Build', () async {
      final adapter = _Adapter(200, {'success': true});
      dio.httpClientAdapter = adapter;
      await dio.get<dynamic>('/products');
      expect(adapter.header?['X-App-Build'], '3');
    });

    // 426 harus diperlakukan seperti offline: antrian transaksi offline
    // MENAHAN kirimannya, bukan menandainya gagal / membuangnya.
    test('426 APP_PERLU_UPDATE → layar update + dianggap offline', () async {
      dio.httpClientAdapter = _Adapter(426, _tolak426);
      Object? galat;
      try {
        await dio.post<dynamic>('/transactions', data: {'x': 1});
      } catch (e) {
        galat = e;
      }
      expect(galat, isNotNull);
      expect(isOfflineError(galat!), isTrue);

      final info = c.read(perluUpdateProvider);
      expect(info, isNotNull);
      expect(info!.minBuild, 7);
      expect(info.updateUrl, 'https://play.example/nara');
    });

    test('galat lain tidak memicu layar update', () async {
      dio.httpClientAdapter = _Adapter(400, {'success': false, 'message': 'x'});
      try {
        await dio.get<dynamic>('/products');
      } catch (_) {}
      expect(c.read(perluUpdateProvider), isNull);
    });
  });

  group('cek saat mulai', () {
    tearDown(() => VersiApp.build = 0);

    Future<InfoPerluUpdate?> cek(int buildApp, int minServer) async {
      VersiApp.build = buildApp;
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final dio = Dio(BaseOptions(baseUrl: 'http://uji.invalid'))
        ..httpClientAdapter = _Adapter(200, {
          'success': true,
          'data': {'min_build': minServer, 'update_url': 'https://u.example'},
        });
      await cekVersiSaatMulai(dio, c.read(perluUpdateProvider.notifier));
      return c.read(perluUpdateProvider);
    }

    test('build di bawah minimum → wajib update', () async {
      final info = await cek(3, 5);
      expect(info?.updateUrl, 'https://u.example');
    });

    test('build cukup / batas mati → tidak', () async {
      expect(await cek(5, 5), isNull);
      expect(await cek(5, 0), isNull);
    });
  });

  testWidgets('layar update: tombol membuka alamat update', (tester) async {
    Uri? dibuka;
    final info = infoDariRespons(
      Response<dynamic>(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: 426,
        data: _tolak426,
      ),
    )!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pembukaUrlProvider.overrideWithValue((uri) async {
            dibuka = uri;
            return true;
          }),
        ],
        child: MaterialApp(home: LayarPerbaruiApp(info: info)),
      ),
    );
    expect(find.text('Perbarui aplikasi'), findsOneWidget);
    expect(find.textContaining('tetap aman'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tombol-perbarui-app')));
    await tester.pump();
    expect(dibuka.toString(), 'https://play.example/nara');
  });
}
