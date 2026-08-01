import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/access_rights/data/access_rights_repository.dart';
import 'package:nara_pos_mobile/features/access_rights/domain/permission.dart';
import 'package:nara_pos_mobile/features/user/domain/user_role.dart';

// Batas wewenang kasir di aplikasi POS. Ini bukan soal tampilan — `refund` dan
// `manageTax` menyentuh UANG, dan `manageProducts` mengubah harga jual.
//
// Yang dijaga di sini adalah himpunan izin DEFAULT, yaitu yang berlaku saat
// aplikasi tak bisa menghubungi server. Alurnya (lihat PermissionCheckRef):
//
//   online  → izin diambil dari backend (/outlets/:id/my-permissions)
//   offline → backendPermissionsProvider bernilai null → JATUH ke default ini
//
// Jadi himpunan di bawah adalah wewenang kasir ketika tak ada yang mengawasi:
// jaringan mati, kasir tetap melayani. Kalau ada yang menambahkan `refund` ke
// himpunan ini, kasir bisa meretur transaksi tanpa persetujuan siapa pun
// selama outlet offline — dan tak ada kompilator yang keberatan, karena
// menambah satu elemen ke sebuah Set adalah kode yang sah sempurna.

void main() {
  group('default izin per peran', () {
    test('kasir hanya dapat tiga izin, dan itu semuanya tak menyentuh uang', () {
      final kasir = defaultPermissionsFor(UserRole.cashier);

      expect(kasir, {
        Permission.managePrinter, // konfigurasi perangkat, bukan data
        Permission.viewHistory, // melihat, bukan mengubah
        Permission.markProducts86, // tandai habis — stok, bukan harga
      });
    });

    test('kasir TIDAK boleh: retur, pajak, harga, diskon, laporan', () {
      final kasir = defaultPermissionsFor(UserRole.cashier);

      // Dieja satu per satu, bukan lewat pembanding himpunan, supaya kalau
      // salah satu bocor kelak, pesan gagalnya menyebut izin yang mana.
      expect(kasir, isNot(contains(Permission.refund)));
      expect(kasir, isNot(contains(Permission.manageTax)));
      expect(kasir, isNot(contains(Permission.manageProducts)));
      expect(kasir, isNot(contains(Permission.manageCategories)));
      expect(kasir, isNot(contains(Permission.giveDiscount)));
      expect(kasir, isNot(contains(Permission.viewReports)));
    });

    test('izin BARU otomatis tertutup untuk kasir, tidak terbuka', () {
      // Sifat penting yang mudah hilang saat refactor: himpunan kasir ditulis
      // sebagai daftar literal, sedangkan peran lain memakai
      // Permission.values. Artinya menambah Permission baru ke enum tidak
      // diam-diam memberikannya kepada kasir.
      //
      // Kalau suatu saat himpunan kasir diubah jadi turunan dari
      // Permission.values (mis. "semua kecuali X"), tes ini gagal — dan itu
      // memang harus ditinjau, bukan lewat begitu saja.
      final kasir = defaultPermissionsFor(UserRole.cashier);
      expect(
        kasir.length,
        lessThan(Permission.values.length),
        reason: 'kasir tak boleh mendapat seluruh izin',
      );
      expect(kasir.length, 3);
    });

    test('owner & admin dapat seluruh izin', () {
      expect(defaultPermissionsFor(UserRole.owner), Permission.values.toSet());
      expect(defaultPermissionsFor(UserRole.admin), Permission.values.toSet());
    });
  });

  group('AccessRightsState.has', () {
    test('owner & admin selalu true, bahkan bila petanya bilang kosong', () {
      // Jalan pintas ini disengaja: owner tak pernah dikonfigurasi. Kalau
      // hilang, konfigurasi rusak/kosong bisa mengunci owner dari aplikasinya
      // sendiri.
      const state = AccessRightsState({
        UserRole.owner: <Permission>{},
        UserRole.admin: <Permission>{},
      });

      for (final p in Permission.values) {
        expect(state.has(UserRole.owner, p), isTrue, reason: p.name);
        expect(state.has(UserRole.admin, p), isTrue, reason: p.name);
      }
    });

    test('kasir TIDAK ikut jalan pintas itu — petanya benar-benar dibaca', () {
      const state = AccessRightsState({UserRole.cashier: <Permission>{}});

      // Kebalikan dari tes di atas. Kalau jalan pintasnya kelak salah tulis
      // (mis. `!=` bukan `==`), kasir mendadak dapat segalanya dan tes owner
      // di atas tetap hijau. Yang menangkapnya justru tes ini.
      for (final p in Permission.values) {
        expect(state.has(UserRole.cashier, p), isFalse, reason: p.name);
      }
    });

    test('peran yang tak ada di peta jatuh ke default-nya, bukan ke kosong', () {
      const state = AccessRightsState({});

      expect(state.has(UserRole.cashier, Permission.viewHistory), isTrue);
      expect(state.has(UserRole.cashier, Permission.refund), isFalse);
    });

    test('izin kasir yang dilonggarkan owner memang berlaku', () {
      // Sisi lain dari batas itu: owner memang BOLEH memberi kasir hak retur
      // lewat pengaturan. Yang dijaga tes-tes di atas adalah defaultnya, bukan
      // larangan mutlak — perbaikan yang membuat retur mustahil diberikan sama
      // salahnya dengan yang memberikannya cuma-cuma.
      const state = AccessRightsState({
        UserRole.cashier: {Permission.viewHistory, Permission.refund},
      });

      expect(state.has(UserRole.cashier, Permission.refund), isTrue);
      expect(state.has(UserRole.cashier, Permission.manageTax), isFalse);
    });
  });

  group('AccessRightsState.isDefault', () {
    test('true hanya bila persis sama dengan default', () {
      const samaPersis = AccessRightsState({
        UserRole.cashier: {
          Permission.managePrinter,
          Permission.viewHistory,
          Permission.markProducts86,
        },
      });
      expect(samaPersis.isDefault(UserRole.cashier), isTrue);
    });

    test('false bila ada tambahan, DAN false bila ada yang dicabut', () {
      const lebih = AccessRightsState({
        UserRole.cashier: {
          Permission.managePrinter,
          Permission.viewHistory,
          Permission.markProducts86,
          Permission.refund,
        },
      });
      expect(lebih.isDefault(UserRole.cashier), isFalse);

      // Arah yang berlawanan gampang terlewat: pembandingan yang cuma memakai
      // containsAll() akan bilang "default" untuk himpunan yang justru lebih
      // sempit. Panjangnya harus ikut diperiksa.
      const kurang = AccessRightsState({
        UserRole.cashier: {Permission.viewHistory},
      });
      expect(kurang.isDefault(UserRole.cashier), isFalse);
    });
  });

  group('padanan kunci backend', () {
    test('kunci yang dipakai untuk menegakkan izin tak boleh kosong/berubah', () {
      // Kunci ini dicocokkan apa adanya dengan jawaban
      // /outlets/:id/my-permissions. Satu huruf meleset (mis.
      // "transaction.refund") tidak error di mana pun — izinnya cuma tak
      // pernah cocok, dan staf ditolak diam-diam tanpa pesan apa pun.
      //
      // Ketujuhnya sudah dicocokkan dengan katalog di nara-pos-be.
      expect(Permission.manageProducts.backendKey, 'products.create');
      expect(Permission.manageCategories.backendKey, 'categories.manage');
      expect(Permission.manageTax.backendKey, 'settings.tax');
      expect(Permission.viewReports.backendKey, 'reports.view');
      expect(Permission.viewHistory.backendKey, 'transactions.view');
      expect(Permission.refund.backendKey, 'transactions.refund');
      expect(Permission.markProducts86.backendKey, 'products.mark_86');
    });

    test('yang null memang disengaja, bukan kelupaan', () {
      // managePrinter itu konfigurasi perangkat lokal — server tak tahu dan tak
      // perlu tahu. giveDiscount belum punya padanan di katalog backend.
      // Keduanya sengaja null supaya jatuh ke konfigurasi lokal, bukan ditolak.
      expect(Permission.managePrinter.backendKey, isNull);
      expect(Permission.giveDiscount.backendKey, isNull);

      // Sisanya WAJIB punya kunci. Kalau ada Permission baru ditambahkan tanpa
      // memutuskan kunci backendnya, ia diam-diam jadi "lokal saja" — artinya
      // pengaturan owner di web tak berpengaruh sama sekali untuk izin itu.
      final tanpaKunci = Permission.values
          .where((p) => p.backendKey == null)
          .toSet();
      expect(tanpaKunci, {Permission.managePrinter, Permission.giveDiscount});
    });
  });
}
