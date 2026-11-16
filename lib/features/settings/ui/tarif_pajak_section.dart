import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../app/theme.dart';
import '../data/kelola_tarif_pajak.dart';

/// Tarif pajak TAMBAHAN outlet (pajak multi-tarif) — dulu hanya bisa diatur dari
/// web. Produk memakai tarif utama outlet kecuali dipilihkan tarif lain di
/// formulir produk.
class TarifPajakSection extends HookConsumerWidget {
  const TarifPajakSection({super.key, required this.outletId});

  final String outletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daftar = ref.watch(daftarTarifPajakProvider(outletId));
    final sibuk = useState(false);

    Future<void> jalankan(Future<void> Function() aksi, String berhasil) async {
      if (sibuk.value) return;
      sibuk.value = true;
      try {
        await aksi();
        segarkanTarifPajak(ref, outletId);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(berhasil)));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: kDanger),
          );
        }
      } finally {
        sibuk.value = false;
      }
    }

    final repo = ref.read(kelolaTarifPajakRepositoryProvider);

    Future<void> tambah() async {
      final h = await showDialog<_HasilDialog>(
        context: context,
        builder: (_) => const _DialogTarif(),
      );
      if (h == null || h.hapus) return;
      await jalankan(
        () => repo.tambah(outletId, nama: h.nama, persen: h.persen),
        'Tarif ${h.nama} ditambahkan',
      );
    }

    Future<void> ubah(TarifPajakKelola t) async {
      final h = await showDialog<_HasilDialog>(
        context: context,
        builder: (_) => _DialogTarif(awal: t),
      );
      if (h == null) return;
      if (h.hapus) {
        await jalankan(
          () => repo.hapus(outletId, t.id),
          'Tarif ${t.nama} dihapus',
        );
        return;
      }
      await jalankan(
        () => repo.ubah(
          outletId,
          t.id,
          nama: h.nama,
          persen: h.persen,
          aktif: t.aktif,
        ),
        'Tarif ${h.nama} diperbarui',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            'TARIF TAMBAHAN',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: kTextMid,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Untuk produk yang pajaknya berbeda dari tarif utama, mis. PB1 untuk '
            'makanan dan PPN untuk barang retail. Pilih tarifnya di formulir produk.',
            style: TextStyle(fontSize: 12, color: kTextMid, height: 1.4),
          ),
        ),
        // Material (bukan Container berwarna) supaya efek sentuh ListTile
        // terlihat.
        Material(
          color: kCard,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: kDivider),
          ),
          child: daftar.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    e.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kDanger),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(daftarTarifPajakProvider(outletId)),
                    child: const Text('Coba lagi'),
                  ),
                ],
              ),
            ),
            data: (items) => Column(
              children: [
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Text(
                      'Belum ada tarif tambahan. Semua produk kena pajak memakai tarif utama.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: kTextMid),
                    ),
                  ),
                for (final t in items) ...[
                  ListTile(
                    key: ValueKey('tarif-${t.id}'),
                    onTap: sibuk.value ? null : () => ubah(t),
                    title: Text(
                      t.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: t.aktif ? kTextDark : kTextMid,
                      ),
                    ),
                    subtitle: Text(
                      [
                        t.jumlahProduk == 0
                            ? 'Belum dipakai produk'
                            : 'Dipakai ${t.jumlahProduk} produk',
                        if (!t.aktif) 'nonaktif',
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: kTextMid),
                    ),
                    trailing: Switch(
                      value: t.aktif,
                      activeThumbColor: kPrimary,
                      onChanged: sibuk.value
                          ? null
                          : (v) => jalankan(
                              () => repo.ubah(
                                outletId,
                                t.id,
                                nama: t.nama,
                                persen: t.persen,
                                aktif: v,
                              ),
                              v
                                  ? 'Tarif ${t.nama} diaktifkan'
                                  : 'Tarif ${t.nama} dinonaktifkan',
                            ),
                    ),
                  ),
                  Divider(height: 1, color: kDivider),
                ],
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextButton.icon(
                    onPressed: sibuk.value ? null : tambah,
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah tarif'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HasilDialog {
  const _HasilDialog({this.nama = '', this.persen = 0, this.hapus = false});
  final String nama;
  final double persen;
  final bool hapus;
}

class _DialogTarif extends HookWidget {
  const _DialogTarif({this.awal});

  final TarifPajakKelola? awal;

  @override
  Widget build(BuildContext context) {
    final nama = useTextEditingController(text: awal?.nama ?? '');
    final persen = useTextEditingController(
      text: awal == null
          ? ''
          : formatPersenTarif(awal!.persen).replaceAll('%', ''),
    );
    final galat = useState<String?>(null);
    final konfirmasiHapus = useState(false);

    void simpan() {
      final g = validasiTarif(nama.text, persen.text);
      if (g != null) {
        galat.value = g;
        return;
      }
      Navigator.pop(
        context,
        _HasilDialog(
          nama: nama.text.trim(),
          persen: double.parse(persen.text.trim().replaceAll(',', '.')),
        ),
      );
    }

    return AlertDialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        awal == null ? 'Tambah tarif pajak' : 'Ubah tarif pajak',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nama,
              autofocus: awal == null,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Nama tarif',
                hintText: 'mis. PPN, PB1',
              ),
            ),
            TextField(
              controller: persen,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Persen',
                suffixText: '%',
              ),
            ),
            const Gap(12),
            Wrap(
              spacing: 8,
              children: [
                for (final p in const ['10', '11', '12'])
                  ActionChip(
                    label: Text('$p%'),
                    onPressed: () => persen.text = p,
                  ),
              ],
            ),
            if (galat.value != null) ...[
              const Gap(10),
              Text(
                galat.value!,
                style: TextStyle(color: kDanger, fontSize: 12),
              ),
            ],
            if (awal != null && konfirmasiHapus.value) ...[
              const Gap(14),
              Text(
                awal!.jumlahProduk > 0
                    ? '${awal!.jumlahProduk} produk yang memakai tarif ini akan kembali ke tarif utama. '
                          'Transaksi lama tidak berubah.'
                    : 'Tarif ini belum dipakai produk mana pun.',
                style: TextStyle(fontSize: 12, color: kTextMid),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (awal != null)
          TextButton(
            onPressed: () {
              if (!konfirmasiHapus.value) {
                konfirmasiHapus.value = true;
                return;
              }
              Navigator.pop(context, const _HasilDialog(hapus: true));
            },
            child: Text(
              konfirmasiHapus.value ? 'Ya, hapus' : 'Hapus',
              style: TextStyle(color: kDanger, fontWeight: FontWeight.w700),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: simpan, child: const Text('Simpan')),
      ],
    );
  }
}
