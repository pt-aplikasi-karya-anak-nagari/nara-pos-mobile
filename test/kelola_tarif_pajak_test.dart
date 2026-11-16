import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nara_pos_mobile/features/products/ui/pilih_tarif_pajak.dart';
import 'package:nara_pos_mobile/features/settings/data/kelola_tarif_pajak.dart';
import 'package:nara_pos_mobile/features/settings/ui/tarif_pajak_section.dart';

// Tarif pajak tambahan dulu hanya bisa diatur dari web: Pemilik yang hanya
// memakai HP tidak bisa memasang PPN untuk barang retail di samping PB1.

class _RepoTiruan extends KelolaTarifPajakRepository {
  _RepoTiruan(this.isi) : super(Dio());

  List<TarifPajakKelola> isi;
  final panggilan = <String>[];
  Object? galat;

  @override
  Future<List<TarifPajakKelola>> daftar(String outletId) async {
    panggilan.add('daftar $outletId');
    return isi;
  }

  @override
  Future<void> tambah(
    String outletId, {
    required String nama,
    required double persen,
  }) async {
    if (galat != null) throw galat!;
    panggilan.add('tambah $nama $persen');
    isi = [
      ...isi,
      TarifPajakKelola(id: 'baru', nama: nama, persen: persen, aktif: true),
    ];
  }

  @override
  Future<void> ubah(
    String outletId,
    String id, {
    required String nama,
    required double persen,
    required bool aktif,
  }) async {
    panggilan.add('ubah $id $nama $persen $aktif');
  }

  @override
  Future<void> hapus(String outletId, String id) async {
    panggilan.add('hapus $id');
    isi = isi.where((t) => t.id != id).toList();
  }
}

const _pb1 = TarifPajakKelola(
  id: 't1',
  nama: 'PB1',
  persen: 10,
  aktif: true,
  jumlahProduk: 4,
);
const _ppn = TarifPajakKelola(id: 't2', nama: 'PPN', persen: 11, aktif: false);

Future<void> _pompa(WidgetTester tester, _RepoTiruan repo, Widget anak) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [kelolaTarifPajakRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: anak)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('validasiTarif', () {
    test('sama dengan aturan server', () {
      expect(validasiTarif('', '10'), contains('wajib'));
      expect(validasiTarif('a' * 41, '10'), contains('40'));
      expect(validasiTarif('PPN', 'sebelas'), contains('angka'));
      expect(validasiTarif('PPN', '101'), contains('antara 0 dan 100'));
      expect(validasiTarif('PPN', '-1'), contains('antara 0 dan 100'));
      expect(validasiTarif(' PPN ', '11'), isNull);
      expect(validasiTarif('PPh', '2,5'), isNull);
    });

    test('format persen', () {
      expect(formatPersenTarif(11), '11%');
      expect(formatPersenTarif(2.5), '2,5%');
      expect(formatPersenTarif(0.25), '0,25%');
    });

    test('mengurai respons daftar tarif', () {
      final t = TarifPajakKelola.fromJson({
        'id': 'x',
        'name': ' PPN ',
        'percent': 11,
        'is_active': false,
        'product_count': 3,
      });
      expect(
        (t.id, t.nama, t.persen, t.aktif, t.jumlahProduk),
        ('x', 'PPN', 11.0, false, 3),
      );
      expect(t.label, 'PPN 11%');
    });
  });

  group('TarifPajakSection', () {
    testWidgets('menampilkan tarif, pemakaiannya, dan status nonaktif', (
      tester,
    ) async {
      await _pompa(
        tester,
        _RepoTiruan([_pb1, _ppn]),
        const TarifPajakSection(outletId: 'O1'),
      );
      expect(find.text('PB1 10%'), findsOneWidget);
      expect(find.text('Dipakai 4 produk'), findsOneWidget);
      expect(find.text('Belum dipakai produk · nonaktif'), findsOneWidget);
    });

    testWidgets('kosong: menjelaskan bahwa semua produk memakai tarif utama', (
      tester,
    ) async {
      await _pompa(
        tester,
        _RepoTiruan([]),
        const TarifPajakSection(outletId: 'O1'),
      );
      expect(find.textContaining('Belum ada tarif tambahan'), findsOneWidget);
    });

    testWidgets('tambah: isian divalidasi sebelum dikirim', (tester) async {
      final repo = _RepoTiruan([]);
      await _pompa(tester, repo, const TarifPajakSection(outletId: 'O1'));
      await tester.tap(find.text('Tambah tarif'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nama tarif wajib diisi'), findsOneWidget);
      expect(repo.panggilan.where((p) => p.startsWith('tambah')), isEmpty);

      await tester.enterText(
        find.widgetWithText(TextField, 'Nama tarif'),
        'PPN',
      );
      await tester.tap(find.text('11%'));
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(repo.panggilan, contains('tambah PPN 11.0'));
      expect(find.text('PPN 11%'), findsOneWidget);
    });

    testWidgets('galat server ditampilkan', (tester) async {
      final repo = _RepoTiruan([])
        ..galat = 'sudah ada tarif dengan nama ini di outlet ini';
      await _pompa(tester, repo, const TarifPajakSection(outletId: 'O1'));
      await tester.tap(find.text('Tambah tarif'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Nama tarif'),
        'PB1',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Persen'), '10');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(
        find.text('sudah ada tarif dengan nama ini di outlet ini'),
        findsOneWidget,
      );
    });

    testWidgets('saklar aktif mengubah status tanpa mengubah nama/persen', (
      tester,
    ) async {
      final repo = _RepoTiruan([_ppn]);
      await _pompa(tester, repo, const TarifPajakSection(outletId: 'O1'));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(repo.panggilan, contains('ubah t2 PPN 11.0 true'));
    });

    testWidgets('hapus butuh konfirmasi dan menyebut produk yang terdampak', (
      tester,
    ) async {
      final repo = _RepoTiruan([_pb1]);
      await _pompa(tester, repo, const TarifPajakSection(outletId: 'O1'));
      await tester.tap(find.text('PB1 10%'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          '4 produk yang memakai tarif ini akan kembali ke tarif utama',
        ),
        findsOneWidget,
      );
      expect(repo.panggilan.where((p) => p.startsWith('hapus')), isEmpty);
      await tester.tap(find.text('Ya, hapus'));
      await tester.pumpAndSettle();
      expect(repo.panggilan, contains('hapus t1'));
    });
  });

  group('PilihTarifPajak', () {
    testWidgets('tidak tampil bila outlet belum punya tarif tambahan', (
      tester,
    ) async {
      await _pompa(
        tester,
        _RepoTiruan([]),
        PilihTarifPajak(outletId: 'O1', nilai: null, onUbah: (_) {}),
      );
      expect(find.text('Tarif pajak'), findsNothing);
    });

    testWidgets(
      'menawarkan tarif aktif; tarif nonaktif hanya bila sedang dipakai',
      (tester) async {
        String? dipilih = 'awal';
        await _pompa(
          tester,
          _RepoTiruan([_pb1, _ppn]),
          PilihTarifPajak(
            outletId: 'O1',
            nilai: null,
            onUbah: (v) => dipilih = v,
          ),
        );
        expect(find.text('Tarif utama outlet'), findsOneWidget);
        await tester.tap(find.text('Tarif utama outlet'));
        await tester.pumpAndSettle();
        expect(find.text('PB1 10%'), findsWidgets);
        expect(find.textContaining('PPN'), findsNothing);
        await tester.tap(find.text('PB1 10%').last);
        await tester.pumpAndSettle();
        expect(dipilih, 't1');
      },
    );

    testWidgets('tarif nonaktif yang sedang dipakai tetap terlihat', (
      tester,
    ) async {
      await _pompa(
        tester,
        _RepoTiruan([_pb1, _ppn]),
        PilihTarifPajak(outletId: 'O1', nilai: 't2', onUbah: (_) {}),
      );
      expect(find.text('PPN 11% (nonaktif)'), findsOneWidget);
    });

    testWidgets(
      'tarif dari outlet lain / sudah dihapus dikembalikan ke tarif utama',
      (tester) async {
        String? dipilih = 'hilang';
        await _pompa(
          tester,
          _RepoTiruan([_pb1]),
          PilihTarifPajak(
            outletId: 'O1',
            nilai: 'hilang',
            onUbah: (v) => dipilih = v,
          ),
        );
        expect(dipilih, isNull);
      },
    );
  });
}
