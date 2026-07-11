import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/theme.dart';
import '../../../../core/image_crop.dart';
import '../../../../core/format.dart';
import '../../../payments/data/payment_method_repository.dart';
import '../../../payments/domain/payment_method.dart';
import '../../data/transaction_repository.dart';

/// Bottom sheet ringkas untuk melunasi transaksi unpaid (mark-as-paid).
///
/// Dipakai di:
///   - Halaman detail transaksi (Riwayat) → tombol "Bayar Sekarang"
///   - Dialog manajemen meja → tombol "Bayar" pada baris pesanan unpaid
///
/// Sheet ini mengambil pilihan dari user (metode + cash + bukti
/// pembayaran kalau non-cash) lalu mengembalikan
/// `(method, cash, proofUrl)` lewat `Navigator.pop`. Pemanggil yang
/// melakukan efektif `markAsPaid` (supaya invalidasi provider tetap
/// terkontrol di callsite).
///
/// Kontrak return:
///   - `null` → user batal / dismiss
///   - `(method, cash, proofUrl)` → method dipilih; cash >= 0;
///     proofUrl bisa kosong (cash) atau URL hasil upload (non-cash).
class MiniPaymentSheet extends HookConsumerWidget {
  final double total;
  const MiniPaymentSheet({super.key, required this.total});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashController = useTextEditingController();
    final cashAmount = useState(0.0);
    final selectedMethod = useState('Tunai');
    // State untuk upload bukti pembayaran (foto QRIS / struk transfer).
    // - proofPath: file lokal yang user pilih (sebelum upload)
    // - proofUrl: URL hasil upload dari backend
    // - uploading: spinner saat sedang upload
    final proofPath = useState<String?>(null);
    final proofUrl = useState<String?>(null);
    final uploading = useState(false);

    final methodsAsync = ref.watch(paymentMethodsFutureProvider);
    final methods = methodsAsync.when(
      data: (list) => list.where((m) => m.isActive).toList(),
      loading: () => <PaymentMethod>[],
      error: (_, _) => <PaymentMethod>[],
    );

    // Cek apakah metode terpilih memerlukan bukti pembayaran (non-cash).
    final selectedPM = methods.firstWhere(
      (m) => m.name == selectedMethod.value,
      orElse: () => PaymentMethod(name: selectedMethod.value, type: 'cash'),
    );
    final isCash = selectedPM.type == 'cash';

    Future<void> pickProof() async {
      try {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1280,
          maxHeight: 1280,
          imageQuality: 80,
        );
        if (picked == null) return;
        final croppedPath = await ImageCrop.square(
          picked.path,
          title: 'Crop bukti pembayaran',
        );
        if (croppedPath == null) return;
        proofPath.value = croppedPath;
        uploading.value = true;
        try {
          final url = await ref
              .read(transactionRepositoryProvider)
              .uploadPaymentProof(croppedPath);
          proofUrl.value = url;
        } finally {
          uploading.value = false;
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal upload bukti: $e')),
          );
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pilih Pembayaran',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const Gap(4),
          Text(
            'Total: ${formatRupiah(total)}',
            style: const TextStyle(
              color: kPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Gap(20),
          if (methods.isEmpty)
            const Center(child: CircularProgressIndicator())
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: methods.map((m) {
                  final active = selectedMethod.value == m.name;
                  return GestureDetector(
                    onTap: () => selectedMethod.value = m.name,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: active ? kPrimary.withValues(alpha: 0.1) : kBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active ? kPrimary : Colors.transparent,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          m.name,
                          style: TextStyle(
                            color: active ? kPrimary : kTextMid,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          if (isCash) ...[
            const Gap(20),
            TextField(
              controller: cashController,
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
              onChanged: (v) =>
                  cashAmount.value = parseRupiahInput(v).toDouble(),
              decoration: const InputDecoration(
                labelText: 'Jumlah Uang Tunai',
                hintText: 'Rp 0',
              ),
            ),
            // Live calculation kembalian — feedback langsung untuk kasir.
            if (cashAmount.value > 0) ...[
              const Gap(8),
              Text(
                cashAmount.value >= total
                    ? 'Kembalian: ${formatRupiah(cashAmount.value - total)}'
                    : 'Kurang: ${formatRupiah(total - cashAmount.value)}',
                style: TextStyle(
                  color: cashAmount.value >= total ? kSuccess : kDanger,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ] else ...[
            // Non-cash: tampilkan area upload bukti pembayaran (opsional).
            // Owner sering butuh foto sebagai backup audit.
            const Gap(20),
            _ProofPicker(
              filePath: proofPath.value,
              uploading: uploading.value,
              onPick: pickProof,
              onClear: () {
                proofPath.value = null;
                proofUrl.value = null;
              },
            ),
          ],
          const Gap(24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed:
                  (!uploading.value &&
                      (!isCash || cashAmount.value >= total))
                  ? () => Navigator.pop(context, (
                      method: selectedMethod.value,
                      cash: cashAmount.value,
                      proofUrl: proofUrl.value ?? '',
                    ))
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Bayar Sekarang',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Gap(MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }
}

/// Widget kompak untuk pilih + preview foto bukti pembayaran.
class _ProofPicker extends StatelessWidget {
  final String? filePath;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onClear;
  const _ProofPicker({
    required this.filePath,
    required this.uploading,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bukti Pembayaran (opsional)',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
        const Gap(2),
        Text(
          'Foto QRIS scan, struk transfer, atau receipt mesin EDC.',
          style: TextStyle(fontSize: 11, color: kTextMid),
        ),
        const Gap(10),
        if (filePath != null)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kDivider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Image.file(
                  File(filePath!),
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
                if (uploading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.4),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        height: 28,
                        width: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: kDanger,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: uploading ? null : onClear,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: const Text('Upload Foto Bukti'),
            style: OutlinedButton.styleFrom(
              foregroundColor: kPrimary,
              side: const BorderSide(color: kPrimary),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
      ],
    );
  }
}
