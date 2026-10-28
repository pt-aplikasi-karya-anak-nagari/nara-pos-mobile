import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/user/domain/user.dart';
import 'package:nara_pos_mobile/features/user/domain/user_role.dart';

// Gerbang masuk seluruh data orang di aplikasi kasir. Satu factory ini dipakai
// empat jalur yang bentuk JSON-nya BERBEDA-BEDA:
//
//   auth_service     login          → payload server (punya 'role' string)
//   auth_service     restore sesi   → hasil toJson() sendiri (punya 'role_id')
//   outlet_service   daftar karyawan→ payload server
//   outlet_staff     staf outlet    → payload server
//
// Karena satu fungsi melayani empat bentuk, tiap cabang di dalamnya adalah
// tempat data bisa hilang diam-diam. Tak ada yang error — field yang tak cocok
// cuma jadi null atau string kosong, dan baru kelihatan di layar.

void main() {
  group('username sudah dihapus', () {
    test('kunci username dari server lama diabaikan, tak ikut tersimpan', () {
      final u = User.fromJson({'id': 'U1', 'username': 'budi', 'name': 'Budi'});
      expect(u.name, 'Budi');
      expect(u.toJson().containsKey('username'), isFalse);
    });

    test('email tetap null bila absen', () {
      final u = User.fromJson({'id': 'E1', 'full_name': 'putra'});
      expect(u.email, isNull);
    });
  });

  group('nama', () {
    test('full_name diutamakan, name jadi cadangan, "" jadi jalan terakhir', () {
      expect(
        User.fromJson({'full_name': 'Dari full_name', 'name': 'Dari name'}).name,
        'Dari full_name',
      );
      expect(User.fromJson({'name': 'Dari name'}).name, 'Dari name');
      expect(User.fromJson({}).name, '');
    });
  });

  group('peran', () {
    test('peran tak dikenal jatuh ke kasir — keranjang paling sempit', () {
      // Sifat gagal-menutup. Kalau server kelak menambah peran yang belum
      // dikenal aplikasi ini, orang itu mendapat wewenang paling sedikit,
      // bukan paling banyak. Wildcard yang mengarah ke owner/adminOutlet akan
      // memberi seluruh izin lokal kepada peran yang tak dimengerti.
      final u = User.fromJson({'id': 'X', 'role': 'peran_yang_belum_ada'});
      expect(u.role, UserRole.cashier);
    });

    test('role_id dipakai bila tak ada string role (jalur pemulihan sesi)', () {
      expect(User.fromJson({'role_id': 1}).role, UserRole.admin);
      expect(User.fromJson({'role_id': 2}).role, UserRole.owner);
      expect(User.fromJson({'role_id': 3}).role, UserRole.adminOutlet);
      expect(User.fromJson({'role_id': 4}).role, UserRole.cashier);
      expect(User.fromJson({'role_id': 99}).role, UserRole.cashier);
    });

    test('role_id di luar jangkauan tidak melempar, tapi mengecil ke kasir', () {
      expect(roleFromIndex(-1), UserRole.cashier);
      expect(roleFromIndex(999), UserRole.cashier);
    });

    test('roleName menyimpan nama peran server APA ADANYA', () {
      // UserRole cuma punya empat nilai untuk sepuluh peran server, jadi
      // Barista/Kitchen/Waiter/Inventory/Finance/Supervisor semuanya jatuh ke
      // keranjang kasir. Itu cukup untuk gerbang izin lokal, tapi TIDAK cukup
      // untuk menampilkan peran orang — dan itulah kenapa nama aslinya
      // disimpan terpisah.
      final u = User.fromJson({'id': 'E1', 'role': 'Barista'});

      expect(u.roleName, 'Barista');
      expect(u.role, UserRole.cashier); // keranjang izin, sengaja kasar
    });

    test('roleName tidak dipaksa huruf kecil maupun dipetakan', () {
      for (final r in ['Cashier', 'Waiter', 'Supervisor', 'Finance']) {
        expect(User.fromJson({'role': r}).roleName, r);
      }
    });

    test('roleName kosong bila server tak mengirimnya', () {
      expect(User.fromJson({'id': 'E1'}).roleName, '');
    });
  });

  group('outlet: tiga sumber berbeda untuk satu field', () {
    test('argumen outlets (saat login) — daftar objek ber-id', () {
      final u = User.fromJson(
        {'id': 'U1'},
        outlets: [
          {'id': 'OUT1', 'name': 'Cabang A'},
          {'id': 'OUT2', 'name': 'Cabang B'},
        ],
      );
      expect(u.outletRemoteIds, ['OUT1', 'OUT2']);
    });

    test('objek ber-remote_id juga dikenali', () {
      final u = User.fromJson({'id': 'U1'}, outlets: [
        {'remote_id': 'OUT9'},
      ]);
      expect(u.outletRemoteIds, ['OUT9']);
    });

    test('outlet_ids di dalam json dipakai bila argumennya tak diberi', () {
      final u = User.fromJson({
        'id': 'U1',
        'outlet_ids': ['OUT3'],
      });
      expect(u.outletRemoteIds, ['OUT3']);
    });

    test('outletRemoteIds (bentuk simpanan sendiri) jadi cadangan terakhir', () {
      final u = User.fromJson({
        'id': 'U1',
        'outletRemoteIds': ['OUT4'],
      });
      expect(u.outletRemoteIds, ['OUT4']);
    });

    test('tanpa sumber apa pun → daftar kosong, bukan null', () {
      expect(User.fromJson({'id': 'U1'}).outletRemoteIds, isEmpty);
    });

    test('argumen outlets MENANG atas outlet_ids di json', () {
      // Urutan ini penting saat login: server mengirim daftar outlet terbaru
      // di luar objek user. Kalau json lama menang, kasir bisa terkunci di
      // outlet yang sudah tak jadi haknya.
      final u = User.fromJson(
        {
          'id': 'U1',
          'outlet_ids': ['LAMA'],
        },
        outlets: [
          {'id': 'BARU'},
        ],
      );
      expect(u.outletRemoteIds, ['BARU']);
    });
  });

  group('bolak-balik lewat penyimpanan lokal', () {
    // auth_service menyimpan sesi sebagai jsonEncode(user.toJson()) dan
    // memulihkannya dengan User.fromJson(jsonDecode(...)). Kalau perjalanan itu
    // tidak setia, orang yang membuka aplikasi dalam keadaan offline bisa
    // kembali dengan peran atau daftar outlet yang berbeda dari saat ia login.
    test('peran bertahan melewati toJson → fromJson', () {
      for (final peran in UserRole.values) {
        final asli = User(
          name: 'Uji',
          passwordHash: '',
          roleIndex: peran.index,
        );
        final pulih = User.fromJson(asli.toJson());
        expect(pulih.role, peran, reason: 'peran $peran tidak bertahan');
      }
    });

    test('toJson TIDAK menulis kunci "role" — dan itu memang harus begitu', () {
      // Perangkap yang halus. fromJson mendahulukan string 'role' dan hanya
      // memakai 'role_id' bila 'role' tak ada. Sementara pencocokan string
      // 'role' memakai huruf kecil.
      //
      // Jadi kalau suatu saat toJson ikut menulis 'role' (mis. role.name yang
      // menghasilkan "adminOutlet"), pemulihan sesi akan membaca kunci itu
      // lebih dulu, gagal mencocokkannya, lalu mengecilkan orangnya jadi
      // kasir — tanpa error apa pun.
      final json = User(
        name: 'Uji',
        passwordHash: '',
        roleIndex: UserRole.owner.index,
      ).toJson();

      expect(json.containsKey('role'), isFalse);
      expect(json['role_id'], 2);
    });

    test('daftar outlet bertahan melewati penyimpanan', () {
      final asli = User(
        name: 'Uji',
        passwordHash: '',
        roleIndex: UserRole.cashier.index,
        outletRemoteIds: const ['OUT1', 'OUT2'],
      );
      expect(User.fromJson(asli.toJson()).outletRemoteIds, ['OUT1', 'OUT2']);
    });

    test('roleName bertahan lewat penyimpanan — dan lewat kunci role_name', () {
      // Sengaja BUKAN kunci 'role'. fromJson mendahulukan 'role' dan
      // mencocokkannya dengan huruf kecil, jadi menulisnya ke sana akan
      // membuat pemulihan sesi mengecilkan orangnya jadi kasir — persis
      // perangkap yang dijaga tes di atas.
      final asli = User(
        name: 'putra',
        passwordHash: '',
        roleName: 'Barista',
        roleIndex: UserRole.cashier.index,
      );
      final json = asli.toJson();

      expect(json['role_name'], 'Barista');
      expect(json.containsKey('role'), isFalse);
      expect(User.fromJson(json).roleName, 'Barista');
    });
  });
}
