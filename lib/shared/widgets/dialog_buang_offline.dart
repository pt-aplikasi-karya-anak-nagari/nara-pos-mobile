import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../../app/theme.dart';

/// Isian untuk membuang data offline yang ditolak server.
class IsianBuang {
  const IsianBuang({required this.alasan, required this.pin});
  final String alasan;
  final String pin;
}

/// Dialog membuang transaksi / catatan shift offline: alasan wajib dan PIN
/// manajer. Data yang dibuang tetap tercatat di server (lihat
/// AuditOfflineApi.catatBuang) — yang hilang hanya salinan di perangkat.
Future<IsianBuang?> mintaAlasanDanPinBuang(
  BuildContext context, {
  required String judul,
  required String keterangan,
}) {
  return showDialog<IsianBuang>(
    context: context,
    builder: (_) => _DialogBuang(judul: judul, keterangan: keterangan),
  );
}

class _DialogBuang extends StatefulWidget {
  const _DialogBuang({required this.judul, required this.keterangan});
  final String judul;
  final String keterangan;

  @override
  State<_DialogBuang> createState() => _DialogBuangState();
}

class _DialogBuangState extends State<_DialogBuang> {
  final _alasan = TextEditingController();
  final _pin = TextEditingController();

  bool get _lengkap =>
      _alasan.text.trim().length >= 5 && _pin.text.trim().length >= 4;

  @override
  void dispose() {
    _alasan.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.judul,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.keterangan,
              style: TextStyle(color: kTextMid, height: 1.4, fontSize: 13),
            ),
            const Gap(14),
            TextField(
              controller: _alasan,
              maxLines: 2,
              maxLength: 200,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Alasan membuang',
                hintText: 'mis. produk sudah dihapus, sudah dicatat manual',
              ),
            ),
            const Gap(6),
            TextField(
              key: const ValueKey('pin-buang'),
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'PIN manajer',
                counterText: '',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kDanger),
          onPressed: _lengkap
              ? () => Navigator.of(context).pop(
                  IsianBuang(
                    alasan: _alasan.text.trim(),
                    pin: _pin.text.trim(),
                  ),
                )
              : null,
          child: const Text('Buang'),
        ),
      ],
    );
  }
}
