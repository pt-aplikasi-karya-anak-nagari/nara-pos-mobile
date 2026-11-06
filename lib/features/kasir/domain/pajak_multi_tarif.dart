import '../../outlet/domain/outlet.dart';

/// PAJAK MULTI-TARIF di aplikasi kasir.
///
/// Outlet punya satu tarif DEFAULT (Outlet.taxPercent/taxName) dan boleh punya
/// tarif TAMBAHAN — mis. PB1 10% default + PPN 11% untuk barang retail.
/// Produk memilih tarif tambahan lewat Product.taxRateId.
///
/// Rumus di sini CERMIN PERSIS server (nara-pos-be internal/transaction
/// tax_multi.go: hitungMultiTarif + bulatkanRincian). Bila berbeda, total yang
/// dibayar pelanggan di kasir tak sama dengan yang tersimpan, dan laci kas
/// selisih. Dijaga test/pajak_multi_tarif_test.dart dengan fixture paritas
/// yang direkam server (test/fixtures/paritas_multi_tarif.json).
///
/// Kebijakan (sama dengan server):
///  - mode inclusive/exclusive SATU untuk seluruh outlet;
///  - service charge dipajaki dengan tarif DEFAULT saja;
///  - pajak outlet nonaktif → tarif tambahan diabaikan (jalur lama).
///  - tanpa tarif tambahan di keranjang → Outlet.computeTaxBreakdown apa adanya.

/// Tarif pajak tambahan outlet.
class TarifPajak {
  final String id;
  final String nama;
  final double persen;
  final bool aktif;

  const TarifPajak({
    required this.id,
    required this.nama,
    required this.persen,
    this.aktif = true,
  });

  factory TarifPajak.fromJson(Map<String, dynamic> j) => TarifPajak(
        id: (j['id'] ?? '').toString(),
        nama: (j['name'] as String?)?.trim() ?? '',
        persen: (j['percent'] as num? ?? 0).toDouble(),
        aktif: j['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': nama,
        'percent': persen,
        'is_active': aktif,
      };
}

/// Satu baris rincian pajak per tarif. [tarifId] null = tarif default.
class BarisPajak {
  final String? tarifId;
  final String nama;
  final double persen;
  final double dasar;
  final double pajak;

  const BarisPajak({
    required this.tarifId,
    required this.nama,
    required this.persen,
    required this.dasar,
    required this.pajak,
  });

  /// Label struk/keranjang, mis. "PPN (11%)".
  String get label {
    final p = persen == persen.roundToDouble()
        ? persen.toStringAsFixed(0)
        : persen.toString().replaceAll('.', ',');
    return '$nama ($p%)';
  }
}

/// Hasil hitung pajak keranjang. [rincian] kosong = satu tarif (pakai baris
/// tunggal lama: nama pajak outlet + [tax]).
class RincianPajakKeranjang {
  final double subtotal;
  final double serviceCharge;
  final double tax;
  final double grandTotal;
  final List<BarisPajak> rincian;

  const RincianPajakKeranjang({
    required this.subtotal,
    required this.serviceCharge,
    required this.tax,
    required this.grandTotal,
    this.rincian = const [],
  });

  bool get multiTarif => rincian.isNotEmpty;
}

/// Baris keranjang minimal yang dibutuhkan untuk menghitung pajak.
class BarisHitungPajak {
  final double subtotal;
  final bool kenaPajak;
  final String? tarifId;
  const BarisHitungPajak({
    required this.subtotal,
    required this.kenaPajak,
    this.tarifId,
  });
}

/// Hitung subtotal, service charge, pajak, total, dan rincian per tarif.
RincianPajakKeranjang hitungPajakKeranjang({
  required Outlet outlet,
  required List<BarisHitungPajak> baris,
  Map<String, TarifPajak> tarif = const {},
}) {
  double total = 0;
  double kena = 0;
  // Porsi per tarif tambahan, urut ID (deterministik seperti server).
  final lain = <String, double>{};
  for (final b in baris) {
    total += b.subtotal;
    if (!b.kenaPajak) continue;
    kena += b.subtotal;
    final t = b.tarifId == null ? null : tarif[b.tarifId];
    if (t != null && t.aktif) {
      lain[t.id] = (lain[t.id] ?? 0) + b.subtotal;
    }
  }

  // Jalur lama: tanpa tarif tambahan, atau pajak outlet nonaktif.
  if (lain.isEmpty || !outlet.taxEnabled) {
    final r = outlet.computeTaxBreakdown(total, taxableSubtotal: kena);
    return RincianPajakKeranjang(
      subtotal: r.subtotal,
      serviceCharge: r.serviceCharge,
      tax: r.tax,
      grandTotal: r.grandTotal,
    );
  }

  final idUrut = lain.keys.toList()..sort();
  final rate = outlet.taxPercent / 100;
  final scRate = outlet.serviceChargePercent / 100;
  final dasarLain = idUrut.fold<double>(0, (s, id) => s + lain[id]!);
  var dasarDefault = kena - dasarLain;
  if (dasarDefault < 0) dasarDefault = 0;

  final mentah = <BarisPajak>[];
  double totalPajak = 0;
  double subtotal;
  double service;
  double grand;

  if (outlet.taxInclusive) {
    if (dasarDefault > 0) {
      final net = dasarDefault / (1 + rate);
      mentah.add(BarisPajak(
        tarifId: null,
        nama: outlet.taxName,
        persen: outlet.taxPercent,
        dasar: net,
        pajak: dasarDefault - net,
      ));
      totalPajak += dasarDefault - net;
    }
    for (final id in idUrut) {
      final t = tarif[id]!;
      final dasar = lain[id]!;
      final net = dasar / (1 + t.persen / 100);
      mentah.add(BarisPajak(
        tarifId: id,
        nama: t.nama,
        persen: t.persen,
        dasar: net,
        pajak: dasar - net,
      ));
      totalPajak += dasar - net;
    }
    subtotal = total - totalPajak;
    service = subtotal * scRate;
    grand = subtotal + totalPajak + service;
  } else {
    service = total * scRate;
    if (dasarDefault + service > 0) {
      final pajak = (dasarDefault + service) * rate;
      mentah.add(BarisPajak(
        tarifId: null,
        nama: outlet.taxName,
        persen: outlet.taxPercent,
        dasar: dasarDefault + service,
        pajak: pajak,
      ));
      totalPajak += pajak;
    }
    for (final id in idUrut) {
      final t = tarif[id]!;
      final dasar = lain[id]!;
      final pajak = dasar * (t.persen / 100);
      mentah.add(BarisPajak(
        tarifId: id,
        nama: t.nama,
        persen: t.persen,
        dasar: dasar,
        pajak: pajak,
      ));
      totalPajak += pajak;
    }
    subtotal = total;
    grand = total + service + totalPajak;
  }

  final pajakBulat = _bulat(totalPajak);
  return RincianPajakKeranjang(
    subtotal: _bulat(subtotal),
    serviceCharge: _bulat(service),
    tax: pajakBulat,
    grandTotal: _bulat(grand),
    rincian: bulatkanRincian(mentah, pajakBulat),
  );
}

/// Bulatkan rincian ke rupiah dengan Σ pajak tepat = [pajakHeader]; selisih
/// pembulatan ke baris berpajak terbesar (pertama bila seri). Baris kosong
/// dibuang. Cermin bulatkanRincian di server.
List<BarisPajak> bulatkanRincian(List<BarisPajak> mentah, double pajakHeader) {
  final out = <BarisPajak>[];
  double jumlah = 0;
  for (final r in mentah) {
    final dasar = _bulat(r.dasar);
    final pajak = _bulat(r.pajak);
    if (dasar == 0 && pajak == 0) continue;
    jumlah += pajak;
    out.add(BarisPajak(
      tarifId: r.tarifId,
      nama: r.nama,
      persen: r.persen,
      dasar: dasar,
      pajak: pajak,
    ));
  }
  final selisih = pajakHeader - jumlah;
  if (out.isNotEmpty && selisih != 0) {
    var besar = 0;
    for (var i = 1; i < out.length; i++) {
      if (out[i].pajak > out[besar].pajak) besar = i;
    }
    final b = out[besar];
    out[besar] = BarisPajak(
      tarifId: b.tarifId,
      nama: b.nama,
      persen: b.persen,
      dasar: b.dasar,
      pajak: b.pajak + selisih,
    );
  }
  return out;
}

/// Pembulatan seperti Go math.Round: setengah menjauhi nol.
double _bulat(double v) => v.roundToDouble();
