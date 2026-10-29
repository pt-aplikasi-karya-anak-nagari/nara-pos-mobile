import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Tanda tangan digital transaksi offline.
///
/// # MASALAHNYA
///
/// Transaksi offline menunggu di perangkat — di antrian, dan di file cadangan
/// tersembunyi — sebelum sampai ke server. Isinya (harga, jumlah, total) bisa
/// diubah di sana, atau permintaan dikarang di luar aplikasi memakai token
/// yang dicuri, dan server tak punya cara membedakannya dari transaksi asli.
///
/// # CARANYA
///
/// Perangkat punya kunci Ed25519 sendiri, dibuat sekali dan disimpan di
/// secure storage; kunci privatnya tak pernah keluar. Kunci publiknya
/// didaftarkan ke server selagi online (sekali per outlet, tak bisa diganti
/// perangkat itu sendiri). Setiap transaksi offline ditandatangani SAAT
/// DIBUAT; server memverifikasinya saat transaksi tiba. Isi yang diubah
/// sesudahnya ditandai `tanda_tangan_tidak_sah`.
///
/// Batas: perangkat yang di-root bisa mengambil kunci privatnya. Penanda lain
/// (riwayat harga, urutan nomor struk) tetap berlaku untuk kasus itu.

String _rp(Object? v) {
  if (v is num) return v.round().toString();
  final d = double.tryParse('${v ?? ''}');
  return (d ?? 0).round().toString();
}

String _teks(Object? v) => v?.toString() ?? '';

/// Bentuk tetap isi transaksi yang ditandatangani. HARUS identik dengan
/// offlinecheck.KanonikTransaksi di server — keduanya diuji dengan vektor
/// yang sama. Angka dibulatkan ke rupiah. MURNI.
String kanonikTransaksi(Map<String, dynamic> p) {
  final items = p['items'] is List ? p['items'] as List : const [];
  return [
    'v1',
    _teks(p['device_id']),
    _teks(p['client_ref']),
    _teks(p['offline_ref']),
    _teks(p['occurred_at']),
    _teks(p['cashier_id']),
    _teks(p['customer_id']),
    _teks(p['payment_method']),
    p['is_paid'] == true ? '1' : '0',
    _rp(p['subtotal_amount']),
    _rp(p['discount_amount']),
    _rp(p['tax_amount']),
    _rp(p['service_charge']),
    _rp(p['final_amount']),
    _rp(p['points_used']),
    _teks(p['promo_code']),
    for (final it in items)
      if (it is Map)
        [
          _teks(it['product_id']),
          _teks(it['variant_id']),
          _rp(it['quantity']),
          _rp(it['price']),
          _rp(it['base_price']),
        ].join('|'),
  ].join('\n');
}

class KunciTandaTangan {
  KunciTandaTangan({FlutterSecureStorage? secure, List<int>? benih})
    : _secure = secure ?? const FlutterSecureStorage(),
      _benihTetap = benih;

  static const _kunciBenih = 'offline.tanda_tangan.benih';

  final FlutterSecureStorage _secure;
  final List<int>? _benihTetap; // hanya untuk tes
  final _algo = Ed25519();
  SimpleKeyPair? _pasangan;

  Future<SimpleKeyPair> _kunci() async {
    if (_pasangan != null) return _pasangan!;
    var benih = _benihTetap;
    if (benih == null) {
      final tersimpan = await _secure.read(key: _kunciBenih);
      if (tersimpan != null) {
        benih = base64Decode(tersimpan);
      } else {
        final r = Random.secure();
        benih = List<int>.generate(32, (_) => r.nextInt(256));
        await _secure.write(key: _kunciBenih, value: base64Encode(benih));
      }
    }
    return _pasangan = await _algo.newKeyPairFromSeed(benih);
  }

  /// Kunci publik (base64) untuk didaftarkan ke server.
  Future<String> kunciPublik() async {
    final pub = await (await _kunci()).extractPublicKey();
    return base64Encode(pub.bytes);
  }

  /// Tanda tangan (base64) atas isi kanonik [payload].
  Future<String> tandatangani(Map<String, dynamic> payload) async {
    final sig = await _algo.sign(
      utf8.encode(kanonikTransaksi(payload)),
      keyPair: await _kunci(),
    );
    return base64Encode(sig.bytes);
  }
}

final kunciTandaTanganProvider = Provider<KunciTandaTangan>(
  (ref) => KunciTandaTangan(),
);
