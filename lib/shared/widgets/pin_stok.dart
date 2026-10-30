import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../../app/theme.dart';
import '../../core/network/galat_api.dart';

/// Kode galat server saat pengurangan stok melebihi batas outlet dan butuh
/// PIN atasan lain (internal/selisihstok di backend).
const kodePerluPinStok = 'perlu_pin_stok';

/// Jalankan [aksi]; bila server menolak karena pengurangan stok melebihi
/// batas, minta PIN atasan lalu ulangi dengan PIN itu. PIN salah memunculkan
/// dialog lagi dengan pesan server.
///
/// Mengembalikan hasil [aksi], atau null bila pengguna membatalkan dialog
/// PIN. Galat lain diteruskan ke pemanggil.
Future<T?> denganPinStok<T>(
  BuildContext context,
  Future<T> Function(String? pin) aksi,
) async {
  String? pin;
  while (true) {
    try {
      return await aksi(pin);
    } catch (e) {
      if (kodeGalat(e) != kodePerluPinStok || !context.mounted) rethrow;
      pin = await mintaPinStok(context, pesan: e.toString());
      if (pin == null) return null;
    }
  }
}

/// Dialog PIN atasan untuk pengurangan stok.
Future<String?> mintaPinStok(BuildContext context, {required String pesan}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final pin = ctrl.text.trim();
        final valid = pin.length >= 4 && pin.length <= 6;
        return AlertDialog(
          title: const Text('Perlu persetujuan atasan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kDanger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  pesan,
                  style: const TextStyle(
                    color: kDanger,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Gap(12),
              const Text(
                'Pengurangan stok sebesar ini harus disetujui atasan lain. '
                'Minta Pemilik atau penyelia memasukkan PIN-nya.',
              ),
              const Gap(12),
              TextField(
                controller: ctrl,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setLocal(() {}),
                decoration: InputDecoration(
                  labelText: 'PIN atasan',
                  hintText: '4-6 digit',
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: valid ? () => Navigator.pop(ctx, pin) : null,
              child: const Text('Setujui'),
            ),
          ],
        );
      },
    ),
  );
}
