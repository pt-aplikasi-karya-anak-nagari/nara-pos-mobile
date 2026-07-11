import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../network/dio_client.dart';
import '../outlet_scope.dart';

/// Event realtime dari backend — disiarkan lewat NATS, didorong ke klien via
/// gateway Server-Sent Events. Payload spesifik domain ada di [data].
class RealtimeEvent {
  RealtimeEvent({
    required this.id,
    required this.type,
    required this.outletId,
    this.actorId,
    this.data = const {},
  });

  final String id;
  final String type; // mis. "order.paid", "transaction.created"
  final String outletId;
  final String? actorId;
  final Map<String, dynamic> data;

  factory RealtimeEvent.fromJson(Map<String, dynamic> j) => RealtimeEvent(
        id: (j['id'] ?? '') as String,
        type: (j['type'] ?? '') as String,
        outletId: (j['outlet_id'] ?? '') as String,
        actorId: j['actor_id'] as String?,
        data: (j['data'] as Map<String, dynamic>?) ?? const {},
      );

  bool get isOrder => type.startsWith('order.');
  bool get isTransaction => type.startsWith('transaction.');
}

/// Klien realtime: buka SSE ke gateway backend
///   GET /realtime/outlet/:outletId   (Authorization: Bearer token otomatis
///   ditambahkan oleh interceptor dioProvider)
/// dan yield tiap event. Reconnect otomatis dengan backoff saat koneksi putus.
class RealtimeService {
  RealtimeService(this._dio);
  final Dio _dio;

  /// [onStatus] dipanggil `true` saat stream tersambung, `false` saat putus —
  /// dipakai indikator "🟢 Live" di UI (stream event saja tak cukup: koneksi
  /// bisa sehat lama tanpa satu pun event).
  Stream<RealtimeEvent> connect(
    String outletId, {
    void Function(bool connected)? onStatus,
  }) async* {
    var backoff = const Duration(seconds: 1);
    while (true) {
      try {
        final resp = await _dio.get<ResponseBody>(
          '/realtime/outlet/$outletId',
          options: Options(
            responseType: ResponseType.stream,
            headers: const {'Accept': 'text/event-stream'},
            receiveTimeout: Duration.zero, // aliran panjang: tanpa timeout
          ),
        );
        final body = resp.data;
        if (body == null) throw Exception('stream kosong');
        backoff = const Duration(seconds: 1); // konek sukses → reset backoff
        onStatus?.call(true);

        final lines =
            utf8.decoder.bind(body.stream).transform(const LineSplitter());
        final buf = StringBuffer();
        await for (final line in lines) {
          if (line.isEmpty) {
            // baris kosong = akhir satu frame SSE
            if (buf.isNotEmpty) {
              try {
                yield RealtimeEvent.fromJson(
                  jsonDecode(buf.toString()) as Map<String, dynamic>,
                );
              } catch (_) {
                /* frame rusak → abaikan */
              }
              buf.clear();
            }
            continue;
          }
          if (line.startsWith(':')) continue; // komentar / heartbeat ": ping"
          if (line.startsWith('data:')) {
            buf.write(line.substring(5).trimLeft());
          }
          // baris "event:" diabaikan — type sudah ada di dalam data JSON
        }
      } catch (_) {
        /* koneksi gagal/putus → reconnect setelah jeda */
      }
      onStatus?.call(false);
      await Future<void>.delayed(backoff);
      backoff = Duration(seconds: (backoff.inSeconds * 2).clamp(1, 30));
    }
  }
}

final realtimeServiceProvider = Provider<RealtimeService>(
  (ref) => RealtimeService(ref.watch(dioProvider)),
);

/// Status koneksi realtime — true saat SSE tersambung. Dipakai indikator
/// "🟢 Live" di UI. Di-update oleh realtimeEventsProvider via onStatus.
class RealtimeConnected extends Notifier<bool> {
  @override
  bool build() => false;

  // ignore: use_setters_to_change_properties
  void set(bool v) => state = v;
}

final realtimeConnectedProvider =
    NotifierProvider<RealtimeConnected, bool>(RealtimeConnected.new);

/// Stream event realtime untuk outlet aktif. autoDispose: koneksi hidup selama
/// masih ada yang mendengarkan (mis. tab Pesanan terbuka), lalu ditutup
/// otomatis untuk menghemat koneksi.
final realtimeEventsProvider = StreamProvider.autoDispose<RealtimeEvent>((ref) {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null || outletId.isEmpty) {
    return const Stream<RealtimeEvent>.empty();
  }
  // Saat provider ini di-dispose (tak ada listener), tandai offline. Callback
  // onStatus juga bisa terpanggil SETELAH dispose (generator masih menutup) —
  // guard ref.mounted supaya tidak menyentuh ref yang sudah mati.
  final connected = ref.read(realtimeConnectedProvider.notifier);
  ref.onDispose(() => connected.set(false));
  return ref.watch(realtimeServiceProvider).connect(
        outletId,
        onStatus: (c) {
          if (ref.mounted) connected.set(c);
        },
      );
});
