// Aturan kirim struk via WhatsApp — dipisah dari UI supaya bisa dites.
//
// Validasi di sini hanya untuk umpan balik cepat di dialog; backend tetap
// memvalidasi ulang (whatsapp.NomorWA) dan menyusun isi pesannya sendiri.

import 'sale.dart';

/// Nomor yang diisikan otomatis di dialog: HP yang tercatat di transaksi,
/// lalu HP pelanggan terdaftar, lalu kosong.
String nomorAwalStrukWa(Sale sale) {
  if (sale.customerPhone.trim().isNotEmpty) return sale.customerPhone.trim();
  final hpPelanggan = sale.customer?.phone.trim() ?? '';
  return hpPelanggan;
}

/// Normalkan ke format 62… seperti backend. Null bila tak wajar.
String? normalkanNomorWa(String input) {
  var p = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (p.startsWith('0')) p = '62${p.substring(1)}';
  if (p.startsWith('8')) p = '62$p';
  if (!p.startsWith('62') || p.length < 10 || p.length > 15) return null;
  return p;
}

/// Struk hanya untuk transaksi yang sudah lunas (atau diretur sebagian —
/// pelanggan tetap berhak atas bukti bayarnya).
bool bisaKirimStrukWa(Sale sale) =>
    !sale.pendingSync && (sale.isPaid || sale.isPartiallyRefunded);
