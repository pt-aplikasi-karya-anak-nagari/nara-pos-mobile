import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nara_pos_mobile/app/app_routes.dart';
import 'package:nara_pos_mobile/app/router.dart';
import 'package:nara_pos_mobile/core/permission_service.dart';
import 'package:nara_pos_mobile/features/izin/gerbang_izin.dart';
import 'package:nara_pos_mobile/features/izin/ui/halaman_izin.dart';
import 'package:permission_handler/permission_handler.dart';

// Gerbang izin: seluruh izin sistem diminta di muka, sebelum login.
//
// # KENAPA DI DEPAN
//
// Pola "minta saat dipakai" gagal justru di saat yang paling mahal. Kasir
// menekan Cetak dengan pelanggan berdiri di depannya, dan dialog izin Bluetooth
// baru muncul saat itu — pertama kali seumur hidup aplikasi. Satu ketukan
// "Tolak" karena panik, dan struk tak pernah keluar; dialognya pun tak muncul
// lagi.
//
// # YANG PALING MUDAH SALAH DI SINI
//
// PEMETAAN VERSI ANDROID. Android 12 mengganti seluruh model izin Bluetooth.
// Meminta izin yang salah untuk versi yang salah tidak menghasilkan galat —
// hasilnya "ditolak permanen", karena izin itu memang tak ada di OS tersebut,
// dan dialognya tak pernah muncul. Gerbang wajib di atas pemetaan yang salah
// berarti aplikasi yang tak bisa dibuka siapa pun, di perangkat yang paling
// umum dipakai.
//
// GERBANG YANG TAK BISA DILEWATI. "Wajib" tak boleh berarti "buntu". Kalau
// pemeriksaan izinnya sendiri yang gagal — plugin bermasalah, perangkat aneh —
// menahan pengguna di halaman izin menghasilkan layar yang tak bisa dilewati
// bahkan dengan memberikan izinnya.

class IzinPalsu extends SystemPermissionService {
  IzinPalsu(this.peta);
  Map<IzinAplikasi, StatusIzin> peta;
  int diminta = 0;
  int pengaturanDibuka = 0;
  bool lempar = false;

  @override
  Future<Map<IzinAplikasi, StatusIzin>> periksaSemua() async {
    if (lempar) throw StateError('plugin izin bermasalah');
    return peta;
  }

  @override
  Future<StatusIzin> status(IzinAplikasi izin) async => peta[izin]!;

  @override
  Future<StatusIzin> minta(IzinAplikasi izin) async {
    diminta++;
    peta = {...peta, izin: StatusIzin.diberikan};
    return StatusIzin.diberikan;
  }

  @override
  Future<bool> get semuaDiberikan async =>
      (await periksaSemua()).values.every((s) => s == StatusIzin.diberikan);

  @override
  Future<void> bukaPengaturan() async => pengaturanDibuka++;
}

Map<IzinAplikasi, StatusIzin> semua(StatusIzin s) => {
  for (final i in IzinAplikasi.values) i: s,
};

void main() {
  group('pemetaan izin per perangkat', () {
    test('Android 12+ memakai BLUETOOTH_SCAN & CONNECT', () {
      expect(
        petakanIzin(
          izin: IzinAplikasi.perangkatSekitar,
          android: true,
          ios: false,
          sdkAndroid: 31,
        ),
        [Permission.bluetoothScan, Permission.bluetoothConnect],
      );
    });

    test('Android 11 ke bawah memakai izin LOKASI', () {
      // Di sana Bluetooth scanning memang dijaga izin lokasi. Meminta
      // BLUETOOTH_SCAN pada OS itu berakhir ditolak permanen tanpa dialog.
      expect(
        petakanIzin(
          izin: IzinAplikasi.perangkatSekitar,
          android: true,
          ios: false,
          sdkAndroid: 30,
        ),
        [Permission.location],
      );
    });

    test('batasnya tepat di SDK 31, bukan 30 atau 32', () {
      List<Permission> di(int sdk) => petakanIzin(
        izin: IzinAplikasi.perangkatSekitar,
        android: true,
        ios: false,
        sdkAndroid: sdk,
      );
      expect(di(30), [Permission.location]);
      expect(di(31), contains(Permission.bluetoothScan));
      expect(di(32), contains(Permission.bluetoothScan));
    });

    test('iOS memakai Permission.bluetooth', () {
      expect(
        petakanIzin(
          izin: IzinAplikasi.perangkatSekitar,
          android: false,
          ios: true,
          sdkAndroid: 0,
        ),
        [Permission.bluetooth],
      );
    });

    test('platform tanpa izin runtime menghasilkan daftar kosong', () {
      // Bukan sekadar kerapian: daftar kosong dirangkum jadi "diberikan", dan
      // itulah yang membuat gerbang tidak menahan di lingkungan yang memang
      // tak punya izin runtime sama sekali.
      for (final izin in IzinAplikasi.values) {
        expect(
          petakanIzin(izin: izin, android: false, ios: false, sdkAndroid: 0),
          isEmpty,
        );
      }
      expect(rangkumStatus(const []), StatusIzin.diberikan);
    });

    test('galeri foto TIDAK termasuk izin wajib', () {
      // Sejak Android 13 image_picker memakai Photo Picker sistem yang tak
      // butuh izin apa pun, jadi Permission.photos di sana selalu ditolak.
      // Memasukkannya ke daftar wajib mengunci setiap perangkat Android modern
      // di gerbang ini, selamanya, tanpa cara keluar.
      expect(IzinAplikasi.values, hasLength(3));
      expect(IzinAplikasi.values.map((e) => e.name), [
        'perangkatSekitar',
        'kamera',
        'notifikasi',
      ]);
    });
  });

  group('rangkuman status', () {
    test('semua diberikan → diberikan', () {
      expect(
        rangkumStatus([PermissionStatus.granted, PermissionStatus.granted]),
        StatusIzin.diberikan,
      );
    });

    test('satu saja belum → belum diberikan', () {
      // Bluetooth di Android 12+ butuh SCAN *dan* CONNECT. Meloloskan yang
      // setengah membuat printer terdeteksi tapi tak bisa disambung.
      expect(
        rangkumStatus([PermissionStatus.granted, PermissionStatus.denied]),
        isNot(StatusIzin.diberikan),
      );
    });

    test('ditolak permanen dibedakan dari ditolak biasa', () {
      // Perbedaan ini yang menentukan tombolnya: "Izinkan" masih berguna untuk
      // yang pertama, tapi untuk yang kedua dialognya tak akan muncul lagi dan
      // satu-satunya jalan adalah Pengaturan.
      expect(rangkumStatus([PermissionStatus.denied]), StatusIzin.ditolak);
      expect(
        rangkumStatus([PermissionStatus.permanentlyDenied]),
        StatusIzin.ditolakPermanen,
      );
    });

    test('limited/provisional iOS dihitung diberikan', () {
      expect(rangkumStatus([PermissionStatus.limited]), StatusIzin.diberikan);
      expect(
        rangkumStatus([PermissionStatus.provisional]),
        StatusIzin.diberikan,
      );
    });
  });

  group('keadaan gerbang', () {
    Future<bool?> gerbangDengan(IzinPalsu palsu) async {
      final c = ProviderContainer(
        overrides: [systemPermissionServiceProvider.overrideWithValue(palsu)],
      );
      addTearDown(c.dispose);
      c.read(gerbangIzinProvider);
      await Future<void>.delayed(Duration.zero);
      return c.read(gerbangIzinProvider);
    }

    test('awalnya null, BUKAN true dan bukan false', () {
      // null punya arti sendiri: "belum diperiksa". true membocorkan satu frame
      // ke halaman utama; false membuat aplikasi berkedip ke halaman izin tiap
      // kali dibuka walau izinnya sudah lengkap.
      final c = ProviderContainer(
        overrides: [
          systemPermissionServiceProvider.overrideWithValue(
            IzinPalsu(semua(StatusIzin.diberikan)),
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(gerbangIzinProvider), isNull);
    });

    test('izin lengkap → true', () async {
      expect(await gerbangDengan(IzinPalsu(semua(StatusIzin.diberikan))), true);
    });

    test('ada yang belum → false', () async {
      final palsu = IzinPalsu({
        ...semua(StatusIzin.diberikan),
        IzinAplikasi.perangkatSekitar: StatusIzin.ditolak,
      });
      expect(await gerbangDengan(palsu), false);
    });

    test('pemeriksaan yang GAGAL tidak mengunci aplikasi', () async {
      // Yang dijaga gerbang ini adalah pengguna yang menolak izin, bukan
      // perangkat yang plugin-nya rusak. Menahan saat pemeriksaannya sendiri
      // gagal menghasilkan layar yang tak bisa dilewati dengan cara apa pun —
      // termasuk dengan memberikan izinnya.
      final palsu = IzinPalsu(semua(StatusIzin.diberikan))..lempar = true;
      expect(
        await gerbangDengan(palsu),
        true,
        reason:
            'kasir terkunci dari alat kerjanya oleh galat yang tak ada '
            'hubungannya dengan izin',
      );
    });
  });

  group('halaman izin', () {
    Future<IzinPalsu> pasang(WidgetTester tester, IzinPalsu palsu) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [systemPermissionServiceProvider.overrideWithValue(palsu)],
          child: const MaterialApp(home: HalamanIzin()),
        ),
      );
      await tester.pumpAndSettle();
      return palsu;
    }

    testWidgets('ketiga izin ditampilkan beserta alasannya', (tester) async {
      await pasang(tester, IzinPalsu(semua(StatusIzin.ditolak)));
      for (final izin in IzinAplikasi.values) {
        expect(
          find.byKey(ValueKey('izin-${izin.name}')),
          findsOneWidget,
          reason: '${izin.name} tak muncul di daftar',
        );
        expect(find.text(izin.alasan), findsOneWidget);
      }
    });

    testWidgets('TIDAK ada tombol lewati', (tester) async {
      await pasang(tester, IzinPalsu(semua(StatusIzin.ditolak)));
      for (final teks in ['Lewati', 'Nanti', 'Lewat', 'Skip']) {
        expect(
          find.text(teks),
          findsNothing,
          reason:
              'ada jalan memutar bertuliskan "$teks" — izinnya jadi tidak '
              'wajib',
        );
      }
    });

    testWidgets('satu ketukan meminta SEMUA izin yang belum ada', (
      tester,
    ) async {
      final palsu = await pasang(tester, IzinPalsu(semua(StatusIzin.ditolak)));
      await tester.tap(find.byKey(const ValueKey('izin-tombol-utama')));
      await tester.pumpAndSettle();
      expect(
        palsu.diminta,
        3,
        reason: 'hanya ${palsu.diminta} dari 3 izin yang diminta',
      );
    });

    testWidgets('izin yang SUDAH ada tidak diminta ulang', (tester) async {
      // Meminta ulang izin yang sudah diberikan tidak memunculkan dialog, tapi
      // menambah bunyi pada alur yang seharusnya sekali jalan.
      final palsu = await pasang(
        tester,
        IzinPalsu({
          ...semua(StatusIzin.diberikan),
          IzinAplikasi.kamera: StatusIzin.ditolak,
        }),
      );
      await tester.tap(find.byKey(const ValueKey('izin-tombol-utama')));
      await tester.pumpAndSettle();
      expect(palsu.diminta, 1);
    });

    testWidgets('ditolak permanen → tombolnya menuju Pengaturan', (
      tester,
    ) async {
      // Tanpa ini halaman jadi buntu: sistem berhenti menampilkan dialog, jadi
      // "Izinkan Semua" tak akan pernah berhasil dan aplikasi hanya bisa
      // diperbaiki dengan memasang ulang.
      final palsu = await pasang(
        tester,
        IzinPalsu({
          ...semua(StatusIzin.diberikan),
          IzinAplikasi.notifikasi: StatusIzin.ditolakPermanen,
        }),
      );
      expect(find.text('Buka Pengaturan'), findsOneWidget);
      expect(find.text('Izinkan Semua'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('izin-tombol-utama')));
      await tester.pumpAndSettle();
      expect(palsu.pengaturanDibuka, 1);
    });
  });

  group('gerbang rute', () {
    // Inti dari permintaannya: tanpa izin lengkap, TIDAK ADA jalan ke login
    // maupun halaman utama.

    String? tujuan(String dari, {bool? izin, bool authed = false}) =>
        tentukanTujuan(lokasi: dari, izinLengkap: izin, authed: authed);

    test('izin belum lengkap → semua jalan berujung di halaman izin', () {
      for (final dari in [
        AppRoutes.login,
        AppRoutes.kasir,
        AppRoutes.riwayat,
        AppRoutes.profil,
        AppRoutes.products,
        '/rute-yang-tak-ada',
      ]) {
        expect(
          tujuan(dari, izin: false),
          AppRoutes.izin,
          reason: '$dari lolos tanpa izin lengkap',
        );
        // Bahkan untuk pengguna yang SUDAH login — sesi lama tak boleh jadi
        // celah yang melewati gerbang izin.
        expect(
          tujuan(dari, izin: false, authed: true),
          AppRoutes.izin,
          reason: '$dari lolos untuk pengguna yang sudah login',
        );
      }
    });

    test('BELUM DIPERIKSA diperlakukan seperti belum lengkap', () {
      // Celah yang paling sulit terlihat: kalau null dianggap lengkap, frame
      // pertama tiap kali aplikasi dibuka meloloskan pengguna ke halaman utama
      // sebelum satu izin pun diperiksa.
      expect(tujuan(AppRoutes.kasir, izin: null), AppRoutes.izin);
      expect(tujuan(AppRoutes.login, izin: null), AppRoutes.izin);
      expect(
        tujuan(AppRoutes.izin, izin: null),
        isNull,
        reason: 'halaman izin sendiri harus boleh ditampilkan saat memeriksa',
      );
    });

    test('halaman izin tidak memantul ke dirinya sendiri', () {
      // Mengembalikan AppRoutes.izin saat SUDAH di sana membuat GoRouter
      // berputar tanpa henti.
      expect(tujuan(AppRoutes.izin, izin: false), isNull);
    });

    test('izin lengkap → gerbang login berlaku seperti biasa', () {
      expect(tujuan(AppRoutes.kasir, izin: true), AppRoutes.login);
      expect(tujuan(AppRoutes.login, izin: true), isNull);
      expect(tujuan(AppRoutes.kasir, izin: true, authed: true), isNull);
      expect(
        tujuan(AppRoutes.login, izin: true, authed: true),
        AppRoutes.kasir,
      );
    });

    test('izin baru lengkap → keluar dari halaman izin sesuai status login', () {
      // Tanpa cabang ini pengguna tertahan di halaman izin walau semuanya sudah
      // diberikan — layar yang sudah tak punya apa pun untuk dikerjakan.
      expect(tujuan(AppRoutes.izin, izin: true), AppRoutes.login);
      expect(tujuan(AppRoutes.izin, izin: true, authed: true), AppRoutes.kasir);
    });
  });
}
