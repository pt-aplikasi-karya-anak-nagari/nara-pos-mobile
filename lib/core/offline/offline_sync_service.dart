import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../connectivity_service.dart';
import '../../features/transactions/data/transaction_repository.dart';
import '../../features/shifts/data/shift_api_service.dart';
import '../../features/shifts/domain/shift.dart';
import '../../features/shifts/data/shift_repository.dart';
import 'sale_outbox.dart';
import 'shift_outbox.dart';

/// Hasil satu kali drain antrian offline.
class SyncResult {
  final int synced; // berhasil terkirim & dihapus dari antrian
  final int failed; // ditolak server (4xx/5xx), tetap di antrian + di-flag
  final bool stoppedOffline; // berhenti karena masih offline
  const SyncResult({
    this.synced = 0,
    this.failed = 0,
    this.stoppedOffline = false,
  });
}

/// Service yang mengirim ulang transaksi yang tertahan di outbox saat
/// koneksi kembali. Aman dipanggil berkali-kali (guard re-entrancy).
class OfflineSyncService {
  final Ref _ref;
  bool _syncing = false;
  OfflineSyncService(this._ref);

  Future<SyncResult> sync() async {
    if (_syncing) return const SyncResult();
    _syncing = true;
    int synced = 0;
    int failed = 0;
    int shiftTerkirim = 0;
    bool stoppedOffline = false;
    bool shiftChanged = false;
    final progres = _ref.read(progresSinkronProvider.notifier);
    try {
      final shiftOutbox = _ref.read(shiftOutboxProvider);
      final shiftApi = _ref.read(shiftApiServiceProvider);

      // Progres untuk tampilan floating: berapa yang akan dikirim di
      // panggilan ini. Antrian kosong → tak ada progres yang ditampilkan.
      final total =
          await _ref.read(saleOutboxProvider).count() +
          await shiftOutbox.count();
      if (total > 0) progres.mulai(total);

      // Op yang SUDAH ditolak di panggilan sync ini. Putaran berikutnya
      // melewatinya: tanpa ini, satu op yang memang rusak akan menaikkan
      // attempts sekali per putaran, dan batas 5 percobaan habis dalam satu
      // kali sambung ulang.
      final ditolakDiPanggilanIni = <String>{};

      // Ulang siklus A→B→C selama masih ada kemajuan.
      //
      // # KENAPA SEKALI SAJA TIDAK CUKUP
      //
      // Urutannya: SELURUH buka, lalu SELURUH sale, lalu SELURUH tutup. Untuk
      // kasir yang berjualan offline melewati dua shift, urutan itu tak bisa
      // selesai dalam satu lintasan:
      //
      //   FASE A  buka hari-1 → sukses
      //           buka hari-2 → DITOLAK, "masih ada shift yang belum ditutup"
      //                         — sebab tutup hari-1 baru jalan di Fase C
      //   FASE B  sale hari-2 → ditolak, shift-nya belum lahir
      //   FASE C  tutup hari-1 → sukses
      //
      // Setelah lintasan itu, prasyarat buka hari-2 SUDAH terpenuhi — tapi
      // sync-nya sudah selesai. Lintasan berikutnya baru terjadi saat koneksi
      // putus lalu tersambung lagi, yang bisa berhari-hari, sementara attempts
      // buka hari-2 sudah naik satu. Lima kali sambung-ulang tanpa sempat
      // ter-drain, dan seluruh omzet hari-2 jadi dead-letter.
      //
      // Putaran kedua di sini menyelesaikannya di panggilan yang sama: buka
      // hari-2 lolos, sale-nya menyusul, tutupnya menyusul. Putaran ketiga tak
      // menemukan kemajuan dan loop berhenti — jadi kasus normal (satu shift)
      // tetap membayar satu putaran saja.
      const maksPutaran = 4;
      for (var putaran = 0; putaran < maksPutaran; putaran++) {
        var adaKemajuan = false;

        // Outlet yang masih punya op TUTUP di antrian. Hanya untuk outlet
        // inilah penolakan "belum ditutup" pada buka shift layak ditunggu —
        // sebab Fase C di bawah memang akan menutupnya.
        //
        // Sengaja TIDAK menyaring server_shift_id di sini. Op tutup hari-1
        // baru mendapat server_shift_id-nya beberapa baris di bawah, saat op
        // BUKA hari-1 sukses di putaran ini juga; menilainya lebih awal berarti
        // syaratnya tak pernah terpenuhi dan seluruh mekanisme ini mati.
        //
        // Yang menjaga dari menunggu selamanya bukan syarat itu, melainkan
        // markDeadCascade: begitu sebuah op buka menembus batas percobaan, op
        // tutup turunannya ikut ditandai 'dead' dan keluar dari closesPending()
        // — jadi tak ada lagi yang bisa dinantikan, dan buka berikutnya kembali
        // menghitung attempts seperti biasa.
        final outletMenungguTutup = <String>{
          for (final op in await shiftOutbox.closesPending()) op.outletId,
        };

        // ── FASE A: drain BUKA shift dulu ──────────────────────────────────
        // Wajib urut: open harus ter-ACK sebelum sales/close, supaya server
        // punya shift aktif saat sale & close menyusul. Saat sukses, catat
        // server_shift_id ke op (dipakai close). Reject permanen → dead-letter
        // + cascade close turunannya.
        for (final op in await shiftOutbox.opensPending()) {
          if (ditolakDiPanggilanIni.contains('shift:${op.localId}')) continue;
          try {
            final shift = await shiftApi.openShift(
              op.outletId,
              (op.payload['start_balance'] as num?)?.toDouble() ?? 0,
              op.payload['notes']?.toString() ?? '',
              clientRef: op.clientRef,
              occurredAt: DateTime.tryParse(op.occurredAt ?? ''),
              cashierId: op.payload['cashier_id']?.toString(),
            );
            if (op.localShiftId != null && (shift.remoteId ?? '').isNotEmpty) {
              await shiftOutbox.setServerShiftId(
                op.localShiftId!,
                shift.remoteId!,
              );
            }
            await shiftOutbox.remove(op.localId);
            shiftChanged = true;
            adaKemajuan = true;
            shiftTerkirim++;
            progres.maju();
          } catch (e) {
            if (isOfflineError(e)) {
              stoppedOffline = true;
              break;
            }
            // "masih ada shift yang belum ditutup" BUKAN cacat op ini — ia
            // prasyarat yang justru dipenuhi Fase C beberapa baris di bawah.
            // Menaruhnya di daftar-lewati akan membuat putaran kedua
            // melompatinya, dan seluruh perbaikan urutan ini sia-sia. Attempts
            // pun tak dinaikkan: yang salah bukan datanya, hanya gilirannya.
            //
            // Tapi HANYA bila tutup yang dinantikan itu benar-benar ada dan
            // siap kirim. Tanpa syarat itu, op buka yang prasyaratnya tak akan
            // pernah datang akan lolos dari hitungan attempts SELAMANYA: tak
            // pernah berhasil, tak pernah mati, tak pernah muncul di daftar
            // "Perlu dipulihkan" — persis kegagalan diam yang sedang kita
            // singkirkan, hanya berpindah tempat.
            if (_isShiftOrderingError(e) &&
                outletMenungguTutup.contains(op.outletId)) {
              continue;
            }
            ditolakDiPanggilanIni.add('shift:${op.localId}');
            await shiftOutbox.markError(op.localId, e.toString());
            progres.maju(gagal: true);
            if (op.attempts + 1 >= ShiftOutbox.maxSyncAttempts &&
                op.localShiftId != null) {
              await shiftOutbox.markDeadCascade(op.localShiftId!, e.toString());
            }
          }
        }

        // ── FASE B: drain SALES ────────────────────────────────────────────
        if (!stoppedOffline) {
          final outbox = _ref.read(saleOutboxProvider);
          final api = _ref.read(transactionApiServiceProvider);
          // Outlet yang MASIH punya shift-open tertahan di antrian setelah Fase A.
          // Sebuah sale yang ditolak "harus buka shift" hanya layak ditunggu
          // (retryable-ordering) bila open-nya memang masih akan menyusul untuk
          // outlet itu. Kalau open-nya sudah dead-letter / tidak ada lagi, error
          // itu TIDAK akan pernah teratasi → jangan skip attempts selamanya.
          final outletsWithPendingOpen = <String>{
            for (final op in await shiftOutbox.opensPending()) op.outletId,
          };
          for (final ps in await outbox.pending()) {
            if (ditolakDiPanggilanIni.contains('sale:${ps.localId}')) continue;
            try {
              progres.sedangMengirim(ps.localId);
              // jam_kirim: jam tablet SAAT MENGIRIM. Server membandingkannya
              // dengan jamnya sendiri untuk mendeteksi jam tablet yang
              // diatur ulang. Tak disimpan di antrian — selalu jam terkini.
              final hasil = await api.checkout(ps.outletId, {
                ...ps.payload,
                'jam_kirim': DateTime.now().toUtc().toIso8601String(),
              });
              // Pelunasan offline yang menunggu penjualan ini kini bisa
              // merujuk ID server-nya.
              await shiftOutbox.petakanIdPenjualan(
                ps.localId,
                hasil['id']?.toString() ?? '',
              );
              await outbox.remove(ps.localId);
              synced++;
              adaKemajuan = true;
              progres.maju();
            } catch (e) {
              if (isOfflineError(e)) {
                stoppedOffline = true;
                break;
              }
              // Sale balapan di depan open shift-nya yang belum sync →
              // RETRYABLE-ORDERING: jangan increment attempts (kalau tidak,
              // seluruh revenue satu shift bisa false-dead-letter). Akan sukses
              // di pass berikut setelah open ter-drain (FIFO).
              //
              // TAPI hanya bila open-nya memang masih pending untuk outlet ini.
              // Kalau open-nya sudah mati (dead-letter cascade di Fase A) atau
              // tak ada, error ordering ini permanen — biarkan jatuh ke markError
              // supaya attempts naik & sale akhirnya jadi dead-letter yang
              // TERLIHAT di UI recovery, bukan loop tak-hingga (omzet hilang).
              if (_isShiftOrderingError(e) &&
                  outletsWithPendingOpen.contains(ps.outletId)) {
                continue;
              }
              ditolakDiPanggilanIni.add('sale:${ps.localId}');
              await outbox.markError(ps.localId, e.toString());
              failed++;
              progres.maju(gagal: true);
            }
          }
        }

        // ── FASE B2: kas masuk/keluar & pelunasan offline ──────────────────
        // Sesudah penjualan (pelunasan bisa menunggu penjualannya), SEBELUM
        // tutup shift — supaya ekspektasi kas yang dihitung server saat tutup
        // sudah memuat uangnya. Yang terlambat pun tetap diterima server dan
        // shift-nya dihitung ulang.
        if (!stoppedOffline) {
          final hasilB2 = await _kirimKasDanPelunasan(
            shiftOutbox,
            shiftApi,
            ditolakDiPanggilanIni,
            progres,
          );
          if (hasilB2.offline) stoppedOffline = true;
          if (hasilB2.terkirim > 0) {
            adaKemajuan = true;
            shiftChanged = true;
            shiftTerkirim += hasilB2.terkirim;
          }
        }

        // ── FASE C: drain TUTUP shift ──────────────────────────────────────
        if (!stoppedOffline) {
          // Shift lokal yang op BUKA-nya masih di antrian. Hanya untuk merekalah
          // "server_shift_id belum ada" berarti benar-benar tinggal menunggu.
          final bukaMasihAntri = <String>{
            for (final o in await shiftOutbox.opensPending())
              if (o.localShiftId != null) o.localShiftId!,
          };

          for (final op in await shiftOutbox.closesPending()) {
            if (ditolakDiPanggilanIni.contains('shift:${op.localId}')) continue;
            var targetId = op.serverShiftId ?? '';

            // OP TUTUP YATIM.
            //
            // server_shift_id diisi saat op BUKA pasangannya sukses. Ada dua
            // jalan ia tak pernah terisi walau buka-nya sudah selesai:
            // respons buka tak membawa id, atau op buka mati tanpa sempat
            // meng-cascade (localShiftId-nya null).
            //
            // Sebelumnya kasus itu hanya di-`continue`: attempts tak pernah
            // naik, jadi ia tak pernah mati, tak pernah muncul di daftar
            // "Perlu dipulihkan", dan tak pernah terkirim. Yang dirasakan
            // kasir bukan galat melainkan pintu terkunci — shift-nya sudah
            // ditutup di layar (cache dikosongkan saat mengantri), sementara
            // server masih menganggapnya terbuka, jadi ia tak bisa membuka
            // shift baru dan tak bisa berjualan. Selamanya, tanpa satu pun
            // pesan.
            if (targetId.isEmpty) {
              if (bukaMasihAntri.contains(op.localShiftId)) continue;

              // Buka-nya sudah tak di antrian → id-nya bisa dipulihkan dari
              // server: shift yang masih terbuka untuk kasir ini di outlet ini
              // adalah shift yang op ini hendak tutup.
              Shift? aktif;
              try {
                aktif = await shiftApi.getActiveShift(op.outletId);
              } catch (e) {
                if (isOfflineError(e)) {
                  stoppedOffline = true;
                  break;
                }
                aktif = null;
              }

              // Tapi jangan menutup shift yang SALAH. Kalau shift terbuka di
              // server dimulai SESUDAH tutup ini terjadi, ia shift lain yang
              // dibuka belakangan — menutupnya dengan hitungan laci milik
              // shift lama akan memindahkan selisih kas ke kasir yang keliru.
              final mulai = aktif?.startTime;
              final saat = DateTime.tryParse(op.occurredAt ?? '');
              final cocok =
                  (aktif?.remoteId ?? '').isNotEmpty &&
                  !(mulai != null && saat != null && mulai.isAfter(saat));

              if (!cocok) {
                ditolakDiPanggilanIni.add('shift:${op.localId}');
                await shiftOutbox.markError(
                  op.localId,
                  'Shift tujuan tidak ditemukan di server. Tutup shift ini '
                  'perlu dipulihkan manual.',
                );
                progres.maju(gagal: true);
                continue;
              }

              targetId = aktif!.remoteId!;
              if (op.localShiftId != null) {
                await shiftOutbox.setServerShiftId(op.localShiftId!, targetId);
              }
            }

            try {
              await shiftApi.closeShift(
                op.outletId,
                targetId,
                (op.payload['actual_balance'] as num?)?.toDouble() ?? 0,
                op.payload['notes']?.toString() ?? '',
                clientRef: op.clientRef,
                occurredAt: DateTime.tryParse(op.occurredAt ?? ''),
                cashierId: op.payload['cashier_id']?.toString(),
              );
              await shiftOutbox.remove(op.localId);
              shiftChanged = true;
              adaKemajuan = true;
              shiftTerkirim++;
              progres.maju();
            } catch (e) {
              if (isOfflineError(e)) {
                stoppedOffline = true;
                break;
              }
              ditolakDiPanggilanIni.add('shift:${op.localId}');
              await shiftOutbox.markError(op.localId, e.toString());
              progres.maju(gagal: true);
            }
          }
        }

        // Tak ada satu pun yang bergerak — putaran lagi hanya mengulang
        // kegagalan yang sama.
        if (!adaKemajuan || stoppedOffline) break;
      }
    } finally {
      _syncing = false;
      progres.selesai(
        terkirim: synced + shiftTerkirim,
        gagal: failed,
        terhentiOffline: stoppedOffline,
      );
      await _ref.read(pendingSyncCountProvider.notifier).refresh();
      // Transaksi yang menembus batas attempts jadi dead-letter → refresh
      // indikator merah supaya owner sadar ada yang gagal permanen.
      await _ref.read(deadLetterCountProvider.notifier).refresh();
      await _ref.read(pendingShiftSyncCountProvider.notifier).refresh();
      await _ref.read(shiftDeadLetterCountProvider.notifier).refresh();
      if (synced > 0) {
        // Data backend berubah → refresh riwayat penjualan.
        _ref.invalidate(salesFutureProvider);
      }
      if (synced > 0 || shiftChanged) {
        // Status shift berubah (open/close ter-sync) → refresh gate kasir.
        _ref.invalidate(activeShiftProvider);
      }
    }
    return SyncResult(
      synced: synced,
      failed: failed,
      stoppedOffline: stoppedOffline,
    );
  }

  /// True bila error backend = sale menyusul sebelum shift-nya ter-sync.
  /// Retryable-ordering, bukan kegagalan nyata.
  ///
  /// Dua bentuk, dari dua cabang server yang berbeda:
  ///
  ///   "harus membuka shift dulu"      sale tak menyebut shift apa pun dan
  ///                                   kasirnya memang belum punya yang aktif.
  ///   "belum tersedia di server"      sale MENYEBUT shift lewat client-ref,
  ///                                   tapi op buka-nya belum ter-drain.
  ///   "belum ditutup"                 buka shift berikutnya menyusul sebelum
  ///                                   tutup shift sebelumnya ter-drain.
  ///
  /// Yang kedua dulunya tak pernah muncul: server diam-diam mengikat sale itu
  /// ke shift lain yang kebetulan terbuka, membalas 200, dan outbox
  /// menghapusnya. Sekarang ia ditolak, dan penolakan itu HARUS dibaca sebagai
  /// "tunggu sebentar" — kalau tidak, seluruh omzet satu shift naik attempts
  /// lalu dead-letter padahal tak ada yang salah dengannya.
  /// Kirim antrian kas masuk/keluar & pelunasan offline (Fase B2).
  Future<({int terkirim, bool offline})> _kirimKasDanPelunasan(
    ShiftOutbox shiftOutbox,
    ShiftApiService shiftApi,
    Set<String> ditolak,
    ProgresSinkronNotifier progres,
  ) async {
    var terkirim = 0;
    final bukaMasihAntri = <String>{
      for (final o in await shiftOutbox.opensPending())
        if (o.localShiftId != null) o.localShiftId!,
    };
    final txApi = _ref.read(transactionApiServiceProvider);
    final ops = [
      ...await shiftOutbox.kasPending(),
      ...await shiftOutbox.lunasPending(),
    ];
    for (final op in ops) {
      if (ditolak.contains('op:${op.localId}')) continue;
      final shiftId = op.serverShiftId ?? '';
      // Shift dibuka offline dan buka-nya belum terkirim: tunggu.
      if (shiftId.isEmpty && bukaMasihAntri.contains(op.localShiftId)) {
        continue;
      }
      try {
        if (op.opType == opKas) {
          if (shiftId.isEmpty) {
            throw 'Shift tujuan kas ini tidak ditemukan di server.';
          }
          await shiftApi.addCashMovement(
            shiftId,
            type: op.payload['type']?.toString() ?? 'out',
            amount: (op.payload['amount'] as num?)?.toDouble() ?? 0,
            note: op.payload['note']?.toString() ?? '',
            clientRef: op.clientRef,
            occurredAt: DateTime.tryParse(op.occurredAt ?? ''),
            offline: true,
          );
        } else {
          final ids = [
            for (final id in (op.payload['transaction_ids'] as List? ?? []))
              id.toString(),
          ];
          // Menunggu penjualan offline yang dilunasi ini terkirim dulu —
          // kecuali penjualannya sudah tak ada di antrian (dibuang): pelunasan
          // ini tak akan pernah bisa terkirim, jadi harus terlihat.
          final lokal = ids.where(SaleOutbox.idOffline).toSet();
          if (lokal.isNotEmpty) {
            final outbox = _ref.read(saleOutboxProvider);
            final masihAda = {
              for (final ps in await outbox.pending()) ps.localId,
              for (final ps in await outbox.deadLetters()) ps.localId,
            };
            if (lokal.every(masihAda.contains)) continue;
            await shiftOutbox.markDead(
              op.localId,
              'Penjualan yang dilunasi ini sudah tidak ada di antrian.',
            );
            progres.maju(gagal: true);
            continue;
          }
          await txApi.lunasiOffline(op.outletId, {
            ...op.payload,
            'client_ref': op.clientRef,
            'occurred_at': op.occurredAt,
            if (shiftId.isNotEmpty) 'shift_id': shiftId,
          });
        }
        await shiftOutbox.remove(op.localId);
        terkirim++;
        progres.maju();
      } catch (e) {
        if (isOfflineError(e)) return (terkirim: terkirim, offline: true);
        ditolak.add('op:${op.localId}');
        // Tagihan sudah dilunasi di tempat lain: mencoba ulang tak akan
        // mengubahnya. Langsung tampil di "Perlu dipulihkan" untuk dicek —
        // pelanggan mungkin membayar dua kali.
        if (e.toString().contains('di tempat lain')) {
          await shiftOutbox.markDead(op.localId, e.toString());
        } else {
          await shiftOutbox.markError(op.localId, e.toString());
        }
        progres.maju(gagal: true);
      }
    }
    return (terkirim: terkirim, offline: false);
  }

  bool _isShiftOrderingError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('membuka shift') ||
        s.contains('buka shift') ||
        s.contains('belum tersedia di server') ||
        s.contains('belum ditutup');
  }
}

/// Progres pengiriman antrian offline, untuk tampilan floating.
class ProgresSinkron {
  const ProgresSinkron({
    this.berjalan = false,
    this.total = 0,
    this.terkirim = 0,
    this.gagal = 0,
    this.sedangDikirim,
    this.selesaiPada,
    this.terkirimTerakhir = 0,
    this.gagalTerakhir = 0,
    this.terhentiOffline = false,
  });

  /// Sedang mengirim antrian sekarang.
  final bool berjalan;

  /// Jumlah transaksi + operasi shift di antrian saat pengiriman dimulai.
  final int total;
  final int terkirim;
  final int gagal;

  /// local_id transaksi yang sedang dikirim (untuk menandainya di daftar).
  final String? sedangDikirim;

  /// Hasil pengiriman terakhir yang sudah selesai.
  final DateTime? selesaiPada;
  final int terkirimTerakhir;
  final int gagalTerakhir;
  final bool terhentiOffline;

  int get diproses => terkirim + gagal;
  double get rasio => total <= 0 ? 0 : (diproses / total).clamp(0, 1);
}

class ProgresSinkronNotifier extends Notifier<ProgresSinkron> {
  @override
  ProgresSinkron build() => const ProgresSinkron();

  void mulai(int total) {
    state = ProgresSinkron(
      berjalan: true,
      total: total,
      selesaiPada: state.selesaiPada,
      terkirimTerakhir: state.terkirimTerakhir,
      gagalTerakhir: state.gagalTerakhir,
    );
  }

  void sedangMengirim(String localId) {
    if (!state.berjalan) return;
    state = _salin(sedangDikirim: localId);
  }

  void maju({bool gagal = false}) {
    if (!state.berjalan) return;
    state = _salin(
      terkirim: state.terkirim + (gagal ? 0 : 1),
      gagal: state.gagal + (gagal ? 1 : 0),
    );
  }

  void selesai({
    required int terkirim,
    required int gagal,
    required bool terhentiOffline,
  }) {
    final adaHasil = terkirim > 0 || gagal > 0;
    state = ProgresSinkron(
      selesaiPada: adaHasil ? DateTime.now() : state.selesaiPada,
      terkirimTerakhir: adaHasil ? terkirim : state.terkirimTerakhir,
      gagalTerakhir: adaHasil ? gagal : state.gagalTerakhir,
      terhentiOffline: terhentiOffline,
    );
  }

  ProgresSinkron _salin({int? terkirim, int? gagal, String? sedangDikirim}) {
    return ProgresSinkron(
      berjalan: state.berjalan,
      total: state.total,
      terkirim: terkirim ?? state.terkirim,
      gagal: gagal ?? state.gagal,
      sedangDikirim: sedangDikirim ?? state.sedangDikirim,
      selesaiPada: state.selesaiPada,
      terkirimTerakhir: state.terkirimTerakhir,
      gagalTerakhir: state.gagalTerakhir,
    );
  }
}

final progresSinkronProvider =
    NotifierProvider<ProgresSinkronNotifier, ProgresSinkron>(
      ProgresSinkronNotifier.new,
    );

final offlineSyncServiceProvider = Provider<OfflineSyncService>(
  (ref) => OfflineSyncService(ref),
);

/// Provider "keep-alive" yang otomatis men-drain outbox setiap koneksi
/// kembali online. Watch sekali di shell aplikasi supaya aktif sepanjang
/// sesi. Juga memicu satu sync awal saat pertama dipasang (menangani
/// transaksi yang tertinggal dari sesi sebelumnya).
final offlineAutoSyncProvider = Provider<void>((ref) {
  // Sync sekali saat dipasang (mis. saat app start) bila ada yang tertahan.
  Future.microtask(() => ref.read(offlineSyncServiceProvider).sync());

  ref.listen<AsyncValue<ConnectionStatus>>(connectivityProvider, (prev, next) {
    if (next.value == ConnectionStatus.online) {
      ref.read(offlineSyncServiceProvider).sync();
    }
  });

  // Coba ulang berkala selama antrian belum kosong.
  //
  // # KENAPA PERLU
  //
  // Pemicu di atas hanya jalan saat status jaringan BERUBAH menjadi online.
  // Bila Wi-Fi tetap tersambung tapi server tak terjangkau (internet router
  // putus, server sedang restart), statusnya tak pernah berubah — transaksi
  // yang diantrekan selama itu tertahan sampai jaringan kebetulan putus lalu
  // tersambung lagi, bisa berjam-jam.
  //
  // Bila percobaan terakhir DITOLAK server (bukan gagal koneksi), jedanya
  // dipanjangkan: setiap penolakan menaikkan hitungan percobaan transaksi itu,
  // dan dengan jeda pendek lima percobaannya habis dalam beberapa menit
  // karena gangguan server yang sebentar saja.
  var jedaSampai = DateTime.fromMillisecondsSinceEpoch(0);
  final timer = Timer.periodic(const Duration(seconds: 30), (_) async {
    if (ref.read(isOfflineProvider)) return;
    if (DateTime.now().isBefore(jedaSampai)) return;
    final ada =
        ref.read(pendingSyncCountProvider) > 0 ||
        ref.read(pendingShiftSyncCountProvider) > 0;
    if (!ada) return;
    final hasil = await ref.read(offlineSyncServiceProvider).sync();
    jedaSampai = hasil.failed > 0 && hasil.synced == 0
        ? DateTime.now().add(const Duration(minutes: 5))
        : DateTime.fromMillisecondsSinceEpoch(0);
  });
  ref.onDispose(timer.cancel);
});
