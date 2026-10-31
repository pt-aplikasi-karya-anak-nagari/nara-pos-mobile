import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/core/pantau.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

// Data yang tak boleh keluar ke Sentry: query string (token), header/cookie/
// body request, data pengguna selain id, dan isi debugPrint.
void main() {
  test('mati tanpa --dart-define=SENTRY_DSN', () async {
    expect(Pantau.dsn, isEmpty);
    await Pantau.mulai();
    expect(Pantau.aktif, isFalse);
    // Tak boleh melempar saat mati.
    await Pantau.lapor(Exception('x'), StackTrace.current);
  });

  test('URL tanpa query & fragmen', () {
    expect(
      Pantau.bersihkanUrl('https://api.nara.id/x?token=rahasia#a'),
      'https://api.nara.id/x',
    );
    expect(Pantau.bersihkanUrl('/menu'), '/menu');
    expect(Pantau.bersihkanUrl(null), isNull);
  });

  test('event dibersihkan', () {
    final ev = SentryEvent(
      request: SentryRequest(
        url: 'https://api.nara.id/transactions?token=rahasia',
        method: 'POST',
        headers: {'Authorization': 'Bearer xyz'},
        cookies: 'sesi=abc',
        data: {'pin': '123456'},
      ),
      user: SentryUser(id: 'U1', email: 'a@b.c', ipAddress: '1.2.3.4'),
      breadcrumbs: [
        Breadcrumb(
          category: 'http',
          message: 'https://api.nara.id/a?token=rahasia',
          data: {'url': 'https://api.nara.id/a?token=rahasia'},
        ),
      ],
    );
    final hasil = Pantau.bersihkan(ev);
    expect(hasil.request?.url, 'https://api.nara.id/transactions');
    expect(hasil.request?.headers, isEmpty);
    expect(hasil.request?.cookies, isNull);
    expect(hasil.request?.data, isNull);
    expect(hasil.user?.id, 'U1');
    expect(hasil.user?.email, isNull);
    expect(hasil.user?.ipAddress, isNull);
    expect(hasil.breadcrumbs!.single.message, 'https://api.nara.id/a');
    expect(hasil.breadcrumbs!.single.data!['url'], 'https://api.nara.id/a');
  });

  test('opsi: tanpa PII, print, screenshot, tracing', () {
    final o = SentryFlutterOptions();
    Pantau.aturOpsi(o);
    expect(o.sendDefaultPii, isFalse);
    expect(o.enablePrintBreadcrumbs, isFalse);
    expect(o.attachScreenshot, isFalse);
    expect(o.attachViewHierarchy, isFalse);
    expect(o.tracesSampleRate, 0);
    expect(o.beforeSend, isNotNull);
  });
}
