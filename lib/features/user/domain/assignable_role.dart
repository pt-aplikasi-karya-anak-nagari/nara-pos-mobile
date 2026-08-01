/// Peran yang boleh diberikan ke karyawan, sebagaimana dijawab server lewat
/// `GET /outlets/:outletId/employee-roles`.
///
/// # KENAPA DAFTARNYA TIDAK DITULIS DI APLIKASI
///
/// Sebelumnya form karyawan membangun pilihannya dari enum `UserRole` lokal
/// yang hanya punya empat nilai (admin, owner, adminOutlet, cashier), lalu
/// mengirim `UserRole.cashier.name` — yaitu string `"cashier"` huruf kecil.
///
/// Server tidak mengenal token itu. Tabel `roles` berisi sepuluh peran dengan
/// nama berkapital (`Cashier`, `Barista`, `Waiter`, `Supervisor`, …), dan
/// `GetRoleByName` mencocokkannya PERSIS. Akibatnya setiap permintaan tambah
/// karyawan dari mobile ditolak dengan "role target tidak ditemukan" — sebuah
/// fitur yang tak pernah berhasil sekali pun.
///
/// Lebih dari itu, `adminOutlet` tak punya padanan sama sekali di server, dan
/// enam peran yang benar-benar ada (Barista, Kitchen, Waiter, Inventory,
/// Finance, Supervisor) tak pernah bisa dipilih dari mobile.
///
/// Karena itu daftarnya sekarang datang dari server. Server pula yang
/// menyaringnya (Owner & SuperAdminSystem tak pernah ditawarkan, peran yang
/// sudah dihapus disingkirkan), jadi aplikasi tak perlu menebak aturan itu
/// sendiri — dan tak bisa lagi berselisih dengannya.
class AssignableRole {
  /// Nama peran persis seperti di server. INILAH yang dikirim balik saat
  /// menyimpan; jangan pernah mengirim turunan huruf kecilnya.
  final String name;

  /// Keterangan dari server, mis. "Kasir — proses transaksi, buka/tutup
  /// shift, terima pembayaran."
  final String description;

  const AssignableRole({required this.name, this.description = ''});

  factory AssignableRole.fromJson(Map<String, dynamic> json) => AssignableRole(
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
  );

  /// Sebutan yang ditampilkan ke pengguna.
  String get label => labelPeran(name, description: description);

  /// Kalimat pendek di bawah nama peran, tanpa mengulang sebutannya.
  String get penjelasan {
    final i = description.indexOf('—');
    if (i < 0) return description.trim();
    return description.substring(i + 1).trim();
  }
}

/// Sebutan Indonesia untuk sebuah nama peran server.
///
/// Sumber utamanya deskripsi dari server itu sendiri, yang memang sudah
/// memuat sebutannya di depan tanda em-dash. Dengan begitu peran yang
/// ditambahkan server kelak langsung punya sebutan yang benar tanpa aplikasi
/// perlu dirilis ulang.
///
/// Peta cadangan di bawah dipakai HANYA saat deskripsinya tak tersedia — mis.
/// di kartu daftar karyawan, yang cuma menyimpan nama perannya.
///
/// Peran yang tak dikenal ditampilkan APA ADANYA. Menggantinya dengan "Kasir"
/// (perilaku lama) menyembunyikan peran baru di balik sebutan yang salah;
/// menampilkan nama aslinya membuat kekurangannya terlihat dan bisa
/// diperbaiki.
String labelPeran(String name, {String description = ''}) {
  final i = description.indexOf('—');
  if (i > 0) {
    final depan = description.substring(0, i).trim();
    if (depan.isNotEmpty) return depan;
  }
  return _sebutanCadangan[name] ?? name;
}

const Map<String, String> _sebutanCadangan = {
  'Owner': 'Pemilik',
  'Investor': 'Investor',
  'Supervisor': 'Supervisor',
  'Cashier': 'Kasir',
  'Barista': 'Barista',
  'Kitchen': 'Dapur',
  'Waiter': 'Pramusaji',
  'Inventory': 'Gudang',
  'Finance': 'Finance',
  'SuperAdminSystem': 'Admin Sistem',
};
