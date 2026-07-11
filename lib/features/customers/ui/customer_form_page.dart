import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/outlet_scope.dart';
import '../../../shared/widgets/tablet_components.dart';
import '../data/customer_repository.dart';
import '../domain/customer.dart';
import '../../user/data/auth_service.dart';

class CustomerFormPage extends HookConsumerWidget {
  final String? customerId;

  const CustomerFormPage({super.key, this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEdit = customerId != null;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Pelanggan' : 'Tambah Pelanggan'),
      ),
      body: CustomerFormView(customerId: customerId),
    );
  }
}

class CustomerFormView extends HookConsumerWidget {
  final String? customerId;
  final bool isEmbedded;
  final VoidCallback? onSaveComplete;

  const CustomerFormView({
    super.key,
    this.customerId,
    this.isEmbedded = false,
    this.onSaveComplete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(customerRepositoryProvider);
    final isEdit = customerId != null;

    final nameCtrl = useTextEditingController();
    final phoneCtrl = useTextEditingController();
    final emailCtrl = useTextEditingController();
    final addressCtrl = useTextEditingController();
    final errors = useState<Map<String, String>>({});

    // Pre-fill form saat mode edit. Data diambil dari customerDetailProvider
    // (cache atau fetch on-demand) — repo.getById() lokal selalu null.
    final detailAsync = isEdit
        ? ref.watch(customerDetailProvider(customerId!))
        : null;

    useEffect(() {
      if (isEdit) {
        final c = detailAsync?.value;
        if (c != null) {
          nameCtrl.text = c.name;
          phoneCtrl.text = c.phone;
          emailCtrl.text = c.email;
          addressCtrl.text = c.address;
        }
      } else {
        nameCtrl.clear();
        phoneCtrl.clear();
        emailCtrl.clear();
        addressCtrl.clear();
      }
      return null;
    }, [customerId, detailAsync?.value?.id]);

    Future<void> save() async {
      final newErrors = <String, String>{};

      final name = nameCtrl.text.trim();
      final phone = phoneCtrl.text.trim();
      final email = emailCtrl.text.trim();
      final address = addressCtrl.text.trim();

      if (name.isEmpty) {
        newErrors['name'] = 'Nama wajib diisi';
      }

      if (phone.isEmpty) {
        newErrors['phone'] = 'Nomor HP wajib diisi';
      } else if (!RegExp(r'^[0-9]+$').hasMatch(phone)) {
        newErrors['phone'] = 'Nomor HP hanya boleh berisi angka';
      } else if (phone.length < 8) {
        newErrors['phone'] = 'Nomor HP terlalu pendek';
      }

      if (email.isNotEmpty &&
          !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
        newErrors['email'] = 'Format email tidak valid';
      }

      errors.value = newErrors;
      if (newErrors.isNotEmpty) return;

      // Pastikan outlet aktif tersedia. Tanpa outletId, URL akan jadi
      // /outlets//customers yang ditolak backend dan bisa memicu logout
      // via interceptor.
      final outletId = ref.read(activeOutletIdProvider);
      if (!isEdit && (outletId == null || outletId.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Outlet aktif belum tersedia. Silakan pilih outlet terlebih dahulu.')),
        );
        return;
      }

      // Saat edit, dasar object diambil dari cache detail provider (yang sudah
      // di-fetch oleh useEffect di atas). Jika belum tersedia, beritahu user
      // alih-alih crash dengan null assertion.
      final Customer? base = isEdit ? detailAsync?.value : Customer(name: '');
      if (base == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data pelanggan masih dimuat, coba lagi sebentar')),
        );
        return;
      }
      final c = base;
      c.name = name;
      c.phone = phone;
      c.email = email;
      c.address = address;
      c.updatedAt = DateTime.now();

      if (!isEdit) {
        final currentUser = ref.read(authProvider).user;
        c.createdBy = currentUser?.name ?? 'Sistem';
      }

      try {
        await repo.save(c, outletId: outletId);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan pelanggan: $e')),
        );
        return;
      }

      // Refresh daftar pelanggan agar data baru langsung tampil.
      ref.invalidate(customersFutureProvider);
      // Refresh detail page bila ini operasi edit.
      if (isEdit) {
        ref.invalidate(customerDetailProvider(customerId!));
      }

      if (!context.mounted) return;
      if (onSaveComplete != null) {
        onSaveComplete!();
      } else {
        context.pop();
      }
    }

    return Container(
      color: kBg,
      child: Column(
        children: [
          if (isEmbedded)
            TabletPanelHeader(
              leading: TabletHeaderBadge(
                icon: isEdit ? AppIcons.person : AppIcons.add,
                color: isEdit ? kAccent : kSuccess,
              ),
              title: isEdit ? 'Edit Pelanggan' : 'Tambah Pelanggan',
            ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TabletFormIllustration(
                        icon: AppIcons.person,
                        color: isEdit ? kAccent : kSuccess,
                        title: isEdit ? 'Edit Pelanggan' : 'Tambah Pelanggan',
                      ),
                      _buildField(
                        'Nama Lengkap',
                        nameCtrl,
                        Icons.person,
                        error: errors.value['name'],
                      ),
                      const Gap(16),
                      _buildField(
                        'No. HP / WhatsApp',
                        phoneCtrl,
                        Icons.phone,
                        type: TextInputType.phone,
                        error: errors.value['phone'],
                      ),
                      const Gap(16),
                      _buildField(
                        'Email',
                        emailCtrl,
                        Icons.email,
                        type: TextInputType.emailAddress,
                        error: errors.value['email'],
                      ),
                      const Gap(16),
                      _buildField(
                        'Alamat Lengkap',
                        addressCtrl,
                        Icons.location_on,
                        maxLines: 3,
                        error: errors.value['address'],
                      ),
                      const Gap(32),
                      TabletPrimaryButton(
                        label: isEdit ? 'Simpan Perubahan' : 'Tambah Pelanggan',
                        onPressed: save,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    TextInputType type = TextInputType.text,
    int maxLines = 1,
    String? error,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: kTextMid,
          ),
        ),
        const Gap(6),
        TextField(
          controller: ctrl,
          keyboardType: type,
          maxLines: maxLines,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 20, color: kTextMid),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(16),
            errorText: error,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kDivider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: kDivider),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kDanger),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kDanger, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
