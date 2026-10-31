/// Satu nomor antrian (lihat backend internal/antrian).
class ItemAntrian {
  const ItemAntrian({
    required this.id,
    required this.nomor,
    this.namaPelanggan = '',
    this.meja = '',
    this.tipePesanan = '',
    this.dibuatPada,
    this.dipanggilPada,
    this.dipanggilKali = 0,
  });

  final String id;
  final String nomor;
  final String namaPelanggan;
  final String meja;
  final String tipePesanan;
  final DateTime? dibuatPada;
  final DateTime? dipanggilPada;
  final int dipanggilKali;

  /// Keterangan singkat di bawah nomor: nama pelanggan / meja.
  String get keterangan {
    final b = <String>[
      if (namaPelanggan.isNotEmpty) namaPelanggan,
      if (meja.isNotEmpty) 'Meja $meja',
    ];
    return b.join(' · ');
  }

  factory ItemAntrian.fromJson(Map<String, dynamic> j) => ItemAntrian(
    id: j['id']?.toString() ?? '',
    nomor: j['nomor']?.toString() ?? '',
    namaPelanggan: j['customer_name']?.toString() ?? '',
    meja: j['table_name']?.toString() ?? '',
    tipePesanan: j['order_type']?.toString() ?? '',
    dibuatPada: DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal(),
    dipanggilPada: DateTime.tryParse(
      j['called_at']?.toString() ?? '',
    )?.toLocal(),
    dipanggilKali: (j['call_count'] as num?)?.toInt() ?? 0,
  );
}

/// Keadaan antrian outlet hari ini.
class RingkasanAntrian {
  const RingkasanAntrian({
    this.total = 0,
    this.menunggu = 0,
    this.dipanggil = 0,
    this.sedangDipanggil,
    this.berikutnya,
    this.daftarMenunggu = const [],
    this.riwayatPanggil = const [],
  });

  final int total;
  final int menunggu;
  final int dipanggil;
  final ItemAntrian? sedangDipanggil;
  final ItemAntrian? berikutnya;
  final List<ItemAntrian> daftarMenunggu;
  final List<ItemAntrian> riwayatPanggil;

  factory RingkasanAntrian.fromJson(Map<String, dynamic> j) {
    ItemAntrian? item(Object? v) =>
        v is Map ? ItemAntrian.fromJson(Map<String, dynamic>.from(v)) : null;
    List<ItemAntrian> daftar(Object? v) =>
        v is List ? [for (final e in v) ?item(e)] : const [];
    return RingkasanAntrian(
      total: (j['total'] as num?)?.toInt() ?? 0,
      menunggu: (j['menunggu'] as num?)?.toInt() ?? 0,
      dipanggil: (j['dipanggil'] as num?)?.toInt() ?? 0,
      sedangDipanggil: item(j['sedang_dipanggil']),
      berikutnya: item(j['berikutnya']),
      daftarMenunggu: daftar(j['daftar_menunggu']),
      riwayatPanggil: daftar(j['riwayat_panggil']),
    );
  }
}
