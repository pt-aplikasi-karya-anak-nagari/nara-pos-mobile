import 'dart:io';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/image_crop.dart';
import '../domain/category.dart';

import '../../../app/theme.dart';
import '../../../core/app_icons.dart';
import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/outlet_scope.dart';
import '../../../core/product_image.dart';
import '../../user/data/auth_service.dart';
import '../../user/domain/user_role.dart';
import '../domain/product.dart';
import '../domain/modifier_group.dart';
import '../data/modifier_repository.dart';
import '../../kasir/providers.dart';
import '../../outlet/data/outlet_service.dart';
import 'barcode_scanner_page.dart';

class ProductFormPage extends HookConsumerWidget {
  final String? productRemoteId;
  final String? initialOutletId;
  final bool embedded;
  final VoidCallback? onSaved;
  final VoidCallback? onDeleted;

  const ProductFormPage({
    super.key,
    this.productRemoteId,
    this.initialOutletId,
    this.embedded = false,
    this.onSaved,
    this.onDeleted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsStreamProvider);
    final existing = productRemoteId != null
        ? productsAsync.value?.firstWhereOrNull(
            (p) => p.remoteId == productRemoteId,
          )
        : null;
    final isEdit = existing != null;

    final nameCtrl = useTextEditingController(text: existing?.name ?? '');
    final priceCtrl = useTextEditingController(
      text: existing != null
          ? 'Rp ${formatThousand(existing.price.toInt())}'
          : '',
    );
    final skuCtrl = useTextEditingController(text: existing?.sku ?? '');
    final barcodeCtrl = useTextEditingController(text: existing?.barcode ?? '');
    final barcodeText = useValueListenable(barcodeCtrl);
    final trackStock = useState(existing?.trackStock ?? false);
    // Kena pajak (PPN/PB1). Default ON supaya produk baru mengikuti perilaku
    // umum; produk existing memakai nilai tersimpan.
    final isTaxable = useState(existing?.isTaxable ?? true);
    final stockCtrl = useTextEditingController(
      text: existing != null && existing.trackStock
          ? existing.stock.toString()
          : '',
    );
    final discountType = useState(existing?.discountType ?? 'none');
    final discountValueCtrl = useTextEditingController(
      text: existing != null && existing.discountValue > 0
          ? (existing.discountType == 'fixed'
                ? formatThousand(existing.discountValue.toInt())
                : existing.discountValue.toString())
          : '',
    );
    final discountNameCtrl = useTextEditingController(
      text: existing?.discountName ?? '',
    );
    // State untuk outlet selection
    final user = ref.watch(authProvider).user;
    final isAdmin = user?.role != UserRole.cashier;
    final selectedOutletId = useState<String?>(null);

    useEffect(() {
      if (existing != null) {
        selectedOutletId.value = existing.outletRemoteId;
      } else if (initialOutletId != null) {
        selectedOutletId.value = initialOutletId;
      } else {
        selectedOutletId.value = ref.read(activeOutletIdProvider);
      }
      return null;
    }, [existing, initialOutletId, user, isAdmin]);

    final catsAsync = selectedOutletId.value != null
        ? ref.watch(categoriesByOutletStreamProvider(selectedOutletId.value!))
        : const AsyncValue<List<Category>>.data([]);
    final categories = catsAsync.value ?? [];

    final selectedCategory = useState<Category?>(null);

    useEffect(() {
      if (selectedOutletId.value != null) {
        // Jika kategori saat ini tidak ada di daftar kategori outlet terpilih, reset.
        final exists = categories.any(
          (c) => c.remoteId == selectedCategory.value?.remoteId,
        );
        if (!exists) {
          selectedCategory.value = categories.firstOrNull;
        } else if (selectedCategory.value == null && categories.isNotEmpty) {
          selectedCategory.value = categories.first;
        }
      } else {
        selectedCategory.value = null;
      }
      return null;
    }, [selectedOutletId.value, categories]);

    final categoryName = selectedCategory.value?.name ?? '';

    final sizes = useState<List<_SizeDraft>>(
      existing?.variants
              .map((v) => _SizeDraft.fromVariant(v, existing.price))
              .toList() ??
          <_SizeDraft>[],
    );

    final categoryCtrl = useTextEditingController(text: categoryName);
    useEffect(() {
      categoryCtrl.text = categoryName;
      return null;
    }, [categoryName]);

    final nameText = useValueListenable(nameCtrl);
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final isLoading = useState(false);

    // Image picker state.
    // - pickedImagePath: file lokal hasil pick (belum diunggah).
    // - imageUrl: URL dari backend (existing atau hasil upload).
    final pickedImagePath = useState<String?>(null);
    final imageUrl = useState<String?>(existing?.imageUrl);
    final isUploadingImage = useState(false);

    // C4: grup modifier/add-on yang dilekatkan ke produk ini. Untuk produk
    // existing, muat set awal sekali; produk baru mulai kosong. Disimpan
    // setelah produk ter-save (butuh ID) di dalam save().
    final selectedModifierGroupIds = useState<Set<String>>(<String>{});
    final modifierGroupsInit = useState(false);
    useEffect(() {
      final oid = selectedOutletId.value;
      final pid = existing?.remoteId;
      if (oid != null && pid != null && !modifierGroupsInit.value) {
        modifierGroupsInit.value = true;
        () async {
          try {
            final ids = await ref
                .read(modifierRepositoryProvider)
                .attachedGroupIds(oid, pid);
            selectedModifierGroupIds.value = ids;
          } catch (_) {
            // Diamkan: produk tetap bisa disimpan tanpa modifier.
          }
        }();
      }
      return null;
    }, [selectedOutletId.value, existing]);
    final allModifierGroupsAsync = selectedOutletId.value != null
        ? ref.watch(modifierGroupsProvider(selectedOutletId.value!))
        : const AsyncValue<List<ModifierGroup>>.data(<ModifierGroup>[]);

    Future<void> pickImage() async {
      try {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        );
        if (picked == null) return;
        // Crop ke 1:1 sebelum upload — galeri produk seragam kotak.
        final croppedPath = await ImageCrop.square(
          picked.path,
          title: 'Crop foto produk',
        );
        if (croppedPath == null) return;
        pickedImagePath.value = croppedPath;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Gagal memilih gambar: $e')));
        }
      }
    }

    Future<void> save() async {
      if (isLoading.value) return;
      if (!formKey.currentState!.validate()) return;

      // Validasi outlet WAJIB sebelum set isLoading agar tombol tidak
      // stuck disabled jika user belum memilih outlet.
      if (selectedOutletId.value == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Silakan pilih outlet')));
        return;
      }

      isLoading.value = true;
      final price = parseRupiahInput(priceCtrl.text).toDouble();
      final sku = skuCtrl.text.trim();
      final barcode = barcodeCtrl.text.trim();
      final stockVal = trackStock.value
          ? (int.tryParse(stockCtrl.text.trim()) ?? 0)
          : 0;
      // Hitung nilai diskon berdasarkan tipe yang dipilih. Tipe 'none' selalu
      // memaksa value=0 dan name='' supaya tidak meninggalkan residu data
      // diskon lama saat user men-disable diskon.
      final discountValue = discountType.value == 'none'
          ? 0.0
          : (discountType.value == 'fixed'
                ? parseRupiahInput(discountValueCtrl.text).toDouble()
                : double.tryParse(discountValueCtrl.text) ?? 0);
      final discountName = discountType.value == 'none'
          ? ''
          : discountNameCtrl.text.trim();

      final product =
          existing?.copyWith(
            name: nameCtrl.text.trim(),
            price: price,
            sku: sku,
            barcode: barcode,
            trackStock: trackStock.value,
            stock: stockVal,
            isTaxable: isTaxable.value,
            discountType: discountType.value,
            discountValue: discountValue,
            discountName: discountName,
          ) ??
          Product(
            name: nameCtrl.text.trim(),
            emoji: '📦',
            price: price,
            sku: sku,
            barcode: barcode,
            trackStock: trackStock.value,
            stock: stockVal,
            isTaxable: isTaxable.value,
            discountType: discountType.value,
            discountValue: discountValue,
            discountName: discountName,
            outletRemoteId: selectedOutletId.value,
          );

      if (selectedCategory.value != null) {
        product.categoryId = selectedCategory.value?.remoteId;
        product.categoryName = selectedCategory.value?.name;
      }

      if (selectedOutletId.value != null) {
        product.outletRemoteId = selectedOutletId.value;
      }

      if (product.sku != null &&
          product.sku!.isNotEmpty &&
          product.sku != existing?.sku) {
        final available = await ref
            .read(outletServiceProvider)
            .checkSku(selectedOutletId.value!, product.sku!);
        if (!available && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('SKU ${product.sku} sudah digunakan produk lain'),
              backgroundColor: kDanger,
            ),
          );
          isLoading.value = false; // reset agar tombol bisa ditekan ulang
          return;
        }
      }

      // Bangun payload variants dari draft. Hanya yang punya nama yang dikirim.
      // Harga tambahan diparsing dari format rupiah, ditambahkan ke harga dasar.
      // ID varian existing disertakan supaya backend UPDATE (bukan INSERT baru
      // yang membuat ID lama orphan dan memutus relasi transaksi historis).
      // Stok varian existing dipertahankan; varian baru default 0.
      // Diskon per-varian dikirim apa adanya — backend akan menormalkan
      // ('none' → value=0 & name='', percent di-clamp 0..100).
      final variantPayload = sizes.value
          .where((d) => d.nameCtrl.text.trim().isNotEmpty)
          .map((d) {
            final extra = parseRupiahInput(d.priceCtrl.text).toDouble();
            return {
              if (d.remoteId != null && d.remoteId!.isNotEmpty)
                'id': d.remoteId,
              'name': d.nameCtrl.text.trim(),
              // Backend menyimpan harga absolut per varian, bukan delta.
              'price': product.price + extra,
              'stock': d.initialStock,
              'discount_type': d.discountType,
              'discount_value': d.discountValue,
              'discount_name': d.discountName,
            };
          })
          .toList();

      try {
        final saved = await ref
            .read(outletServiceProvider)
            .saveProduct(selectedOutletId.value!, {
              if (product.remoteId != null) 'id': product.remoteId,
              'name': product.name,
              'price': product.price,
              'stock': product.stock,
              'sku': product.sku,
              'barcode': product.barcode,
              'category_id': product.categoryId,
              'is_available': product.isAvailable,
              'track_stock': product.trackStock,
              'is_taxable': product.isTaxable,
              'description': product.description,
              'discount_type': product.discountType,
              'discount_value': product.discountValue,
              'discount_name': product.discountName,
              'variants': variantPayload,
            });

        // Upload gambar bila user pilih file baru. Saat create, kita pakai
        // ID dari produk yang baru dibuat. Saat edit, pakai ID existing.
        final productIdForImage = product.remoteId ?? saved?.remoteId;
        if (pickedImagePath.value != null && productIdForImage != null) {
          isUploadingImage.value = true;
          try {
            final uploadedUrl = await ref
                .read(outletServiceProvider)
                .uploadProductImage(productIdForImage, pickedImagePath.value!);
            imageUrl.value = uploadedUrl;
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Produk tersimpan tapi gambar gagal di-upload: $e',
                  ),
                  backgroundColor: kDanger,
                ),
              );
            }
          } finally {
            isUploadingImage.value = false;
          }
        }

        // C4: simpan grup modifier yang dilekatkan ke produk. Butuh ID, jadi
        // dilakukan setelah produk ter-save (berlaku untuk create & edit).
        // Non-fatal bila gagal — produk sudah tersimpan.
        final productIdForMods = product.remoteId ?? saved?.remoteId;
        if (productIdForMods != null && selectedOutletId.value != null) {
          try {
            await ref.read(modifierRepositoryProvider).setProductGroups(
                  selectedOutletId.value!,
                  productIdForMods,
                  selectedModifierGroupIds.value.toList(),
                );
            ref.invalidate(productModifierGroupsProvider);
          } catch (_) {
            // Diamkan — modifier bisa diatur ulang dari form produk.
          }
        }

        // Invalidate caches sehingga list produk di kasir & manajemen produk
        // langsung mencerminkan perubahan (sebelumnya hanya kategori yang
        // refresh; produk masih stale sampai user reload manual).
        ref.invalidate(outletCategoriesProvider);
        ref.invalidate(productsStreamProvider);
        if (embedded) {
          onSaved?.call();
        } else if (context.mounted) {
          context.pop();
        }
      } catch (e) {
        if (context.mounted) {
          String message = e.toString();
          if (message.contains('Exception:')) {
            message = message.split('Exception:').last.trim();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: kDanger,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              margin: const EdgeInsets.all(20),
            ),
          );
        }
      } finally {
        isLoading.value = false;
      }
    }

    Future<void> deleteProduct() async {
      if (existing == null) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ref.t('product.delete_q')),
          content: Text(ref.t('product.delete_perm')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ref.t('common.cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: kDanger),
              child: Text(ref.t('common.delete')),
            ),
          ],
        ),
      );
      if (ok == true && context.mounted) {
        try {
          await ref
              .read(outletServiceProvider)
              .deleteProduct(existing.remoteId!);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Produk berhasil dihapus')),
            );
            if (embedded) {
              onDeleted?.call();
            } else {
              context.pop();
            }
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Gagal menghapus produk: $e'),
                backgroundColor: kDanger,
              ),
            );
          }
        }
      }
    }

    final formChildren = <Widget>[
      Center(
        child: _ProductImagePicker(
          pickedPath: pickedImagePath.value,
          remoteUrl: imageUrl.value,
          fallbackSeed: nameText.text.isEmpty ? 'product' : nameText.text,
          isUploading: isUploadingImage.value,
          onTap: pickImage,
          onRemove: () {
            pickedImagePath.value = null;
          },
        ),
      ),
      const SizedBox(height: 20),
      _Label(ref.t('product.name')),
      _FieldWrap(
        child: TextFormField(
          controller: nameCtrl,
          decoration: _decoration(ref.t('product.name_hint')),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? ref.t('common.required') : null,
        ),
      ),
      const SizedBox(height: 12),
      _Label(ref.t('product.category')),
      _FieldWrap(
        child: TextFormField(
          readOnly: true,
          controller: categoryCtrl,
          decoration:
              _decoration(
                categories.isEmpty
                    ? ref.t('product.category_empty_hint')
                    : ref.t('product.category_hint'),
              ).copyWith(
                suffixIcon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: kTextMid,
                ),
              ),
          onTap: () async {
            final result = await showModalBottomSheet<Category>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (ctx) => _CategoryPickerSheet(
                categories: categories,
                selectedId: selectedCategory.value?.remoteId,
              ),
            );
            if (result != null) selectedCategory.value = result;
          },
          validator: (v) {
            if (v == null || v.isEmpty) return ref.t('common.required');
            if (categories.isEmpty) {
              return 'Outlet ini belum memiliki kategori produk';
            }
            return null;
          },
        ),
      ),
      if (categories.isEmpty && selectedOutletId.value != null)
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(
            'Harap buat kategori terlebih dahulu di manajemen kategori untuk outlet ini.',
            style: TextStyle(
              fontSize: 11,
              color: kDanger.withValues(alpha: 0.8),
            ),
          ),
        ),
      const SizedBox(height: 12),
      _Label(ref.t('product.price')),
      _FieldWrap(
        child: TextFormField(
          controller: priceCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
          decoration: _decoration('Rp 0'),
          validator: (v) {
            final n = parseRupiahInput(v ?? '');
            if (n <= 0) return ref.t('common.required');
            return null;
          },
        ),
      ),
      const SizedBox(height: 12),
      _Label(ref.t('product.sku')),
      _FieldWrap(
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: skuCtrl,
                decoration: _decoration(ref.t('product.sku_hint')),
                textCapitalization: TextCapitalization.characters,
                validator: (v) => null,
              ),
            ),
            TextButton(
              onPressed: () {
                skuCtrl.text = 'SKU-${DateTime.now().millisecondsSinceEpoch}';
              },
              style: TextButton.styleFrom(
                foregroundColor: kPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                ref.t('product.generate'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _Label(ref.t('product.barcode')),
      _FieldWrap(
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: barcodeCtrl,
                keyboardType: TextInputType.number,
                decoration: _decoration(ref.t('product.barcode_hint')),
              ),
            ),
            IconButton(
              tooltip: ref.t('product.scan_barcode'),
              onPressed: () async {
                final result = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const BarcodeScannerPage(),
                    fullscreenDialog: true,
                  ),
                );
                if (result != null && result.isNotEmpty) {
                  barcodeCtrl.text = result;
                }
              },
              icon: const HugeIcon(icon: AppIcons.qrCode, color: kPrimary),
            ),
          ],
        ),
      ),
      if (barcodeText.text.trim().isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 80,
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: barcodeText.text.trim(),
              drawText: true,
              style: TextStyle(fontSize: 11, color: kTextDark),
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      _FieldWrap(
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: kPrimary,
          title: Text(
            ref.t('product.track_stock'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: kTextDark,
            ),
          ),
          subtitle: Text(
            ref.t('product.track_stock_hint'),
            style: TextStyle(fontSize: 11, color: kTextMid),
          ),
          value: trackStock.value,
          onChanged: (v) => trackStock.value = v,
        ),
      ),
      if (trackStock.value) ...[
        const SizedBox(height: 12),
        _Label(ref.t('product.stock')),
        _FieldWrap(
          child: TextFormField(
            controller: stockCtrl,
            keyboardType: TextInputType.number,
            decoration: _decoration(ref.t('product.stock_hint')),
            validator: (v) {
              if (!trackStock.value) return null;
              final val = (v ?? '').trim();
              if (val.isEmpty) return null; // Optional
              final n = int.tryParse(val);
              if (n == null || n < 0) {
                return 'Hanya angka >= 0';
              }
              return null;
            },
          ),
        ),
      ],
      const SizedBox(height: 12),
      _FieldWrap(
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: kPrimary,
          title: Text(
            'Kena pajak (PPN/PB1)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: kTextDark,
            ),
          ),
          subtitle: Text(
            'Nonaktifkan untuk item bebas pajak — dikecualikan dari '
            'perhitungan pajak di kasir.',
            style: TextStyle(fontSize: 11, color: kTextMid),
          ),
          value: isTaxable.value,
          onChanged: (v) => isTaxable.value = v,
        ),
      ),
      const SizedBox(height: 12),
      _FieldWrap(
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: kPrimary,
          title: Text(
            sizes.value.isEmpty
                ? 'Aktifkan Diskon Produk'
                : 'Diskon Regular',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: kTextDark,
            ),
          ),
          subtitle: Text(
            sizes.value.isEmpty
                ? 'Berikan potongan harga khusus untuk produk ini.'
                : 'Berlaku saat opsi "Regular" dipilih di kasir.',
            style: TextStyle(fontSize: 11, color: kTextMid),
          ),
          value: discountType.value != 'none',
          onChanged: (v) {
            discountType.value = v ? 'percent' : 'none';
          },
        ),
      ),
      if (discountType.value != 'none') ...[
        const SizedBox(height: 12),
        const _Label('Nama Diskon'),
        _FieldWrap(
          child: TextFormField(
            controller: discountNameCtrl,
            decoration: _decoration('Contoh: Promo Weekend, Diskon Member'),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Label('Tipe Diskon'),
                  _FieldWrap(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: discountType.value,
                      decoration: _decoration(''),
                      items: const [
                        DropdownMenuItem(
                          value: 'percent',
                          child: Text('Persentase (%)'),
                        ),
                        DropdownMenuItem(
                          value: 'fixed',
                          child: Text('Nominal (Rp)'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          discountType.value = v;
                          discountValueCtrl.clear();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Label(
                    discountType.value == 'percent'
                        ? 'Nilai (%)'
                        : 'Nilai (Rp)',
                  ),
                  _FieldWrap(
                    child: TextFormField(
                      controller: discountValueCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: discountType.value == 'fixed'
                          ? [RupiahInputFormatter()]
                          : null,
                      decoration: _decoration(
                        discountType.value == 'percent' ? '0%' : 'Rp 0',
                      ),
                      validator: (v) {
                        if (discountType.value == 'none') return null;
                        if (discountType.value == 'percent') {
                          final n = double.tryParse(v ?? '');
                          if (n == null || n <= 0 || n > 100) return '0-100';
                        } else {
                          final n = parseRupiahInput(v ?? '');
                          if (n <= 0) return ref.t('common.required');
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ukuran / Varian',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kTextDark,
                  ),
                ),
                Text(
                  'Opsional. Contoh: Regular, Large.',
                  style: TextStyle(fontSize: 11, color: kTextMid),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              final result = await showModalBottomSheet<_SizeDraft>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (ctx) => _VariantEditSheet(draft: _SizeDraft.empty()),
              );
              if (result != null) {
                sizes.value = [...sizes.value, result];
              }
            },
            icon: const HugeIcon(icon: AppIcons.add, color: kPrimary, size: 18),
            label: const Text('Tambah'),
            style: TextButton.styleFrom(foregroundColor: kPrimary),
          ),
        ],
      ),
      const SizedBox(height: 8),
      for (int i = 0; i < sizes.value.length; i++) ...[
        GestureDetector(
          onTap: () async {
            final draft = sizes.value[i];
            final result = await showModalBottomSheet<_SizeDraft>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (ctx) => _VariantEditSheet(draft: draft),
            );
            if (result != null) {
              sizes.value = [
                for (int j = 0; j < sizes.value.length; j++)
                  if (j == i) result else sizes.value[j],
              ];
            }
          },
          child: _FieldWrap(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.straighten_rounded,
                      color: kPrimary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                sizes.value[i].nameCtrl.text.isEmpty
                                    ? 'Tanpa Nama'
                                    : sizes.value[i].nameCtrl.text,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: kTextDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (sizes.value[i].discountType != 'none' &&
                                sizes.value[i].discountValue > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: kAccent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  sizes.value[i].discountType == 'percent'
                                      ? '${sizes.value[i].discountValue.toInt()}% OFF'
                                      : 'DISKON',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          sizes.value[i].priceCtrl.text.isEmpty
                              ? 'Harga tetap'
                              : '+ ${sizes.value[i].priceCtrl.text}',
                          style: TextStyle(fontSize: 12, color: kTextMid),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      sizes.value = [
                        for (int j = 0; j < sizes.value.length; j++)
                          if (j != i) sizes.value[j],
                      ];
                    },
                    icon: const HugeIcon(
                      icon: AppIcons.delete,
                      color: kDanger,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 20),
      // ── C4: Modifier & Add-on ──
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modifier & Add-on',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kTextDark,
                  ),
                ),
                Text(
                  'Opsional. Grup add-on yang muncul di kasir saat item ini '
                  'ditambahkan.',
                  style: TextStyle(fontSize: 11, color: kTextMid),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      allModifierGroupsAsync.when(
        loading: () => _FieldWrap(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Memuat grup modifier...',
              style: TextStyle(fontSize: 13, color: kTextMid),
            ),
          ),
        ),
        error: (e, _) => _FieldWrap(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Gagal memuat grup modifier.',
              style: TextStyle(fontSize: 13, color: kDanger),
            ),
          ),
        ),
        data: (groups) {
          if (groups.isEmpty) {
            return _FieldWrap(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'Belum ada grup modifier. Buat dulu di menu '
                  '"Modifier & Add-on".',
                  style: TextStyle(fontSize: 12.5, color: kTextMid),
                ),
              ),
            );
          }
          final selectedNames = groups
              .where((g) => selectedModifierGroupIds.value.contains(g.id))
              .map((g) => g.name)
              .toList();
          return GestureDetector(
            onTap: () async {
              final result = await showModalBottomSheet<Set<String>>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (ctx) => _ModifierGroupPickerSheet(
                  groups: groups,
                  selected: selectedModifierGroupIds.value,
                ),
              );
              if (result != null) selectedModifierGroupIds.value = result;
            },
            child: _FieldWrap(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    HugeIcon(
                      icon: AppIcons.discount,
                      color: kPrimary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        selectedNames.isEmpty
                            ? 'Pilih grup modifier (opsional)'
                            : selectedNames.join(', '),
                        style: TextStyle(
                          fontSize: 13.5,
                          color: selectedNames.isEmpty ? kTextMid : kTextDark,
                          fontWeight: selectedNames.isEmpty
                              ? FontWeight.w400
                              : FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: kTextMid,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 20),
      SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: isLoading.value ? null : save,
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          child: isLoading.value
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Text(
                  isEdit
                      ? ref.t('product.save_changes')
                      : ref.t('product.add_full'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
        ),
      ),
    ];

    if (embedded) {
      return Column(
        children: [
          _EmbeddedFormHeader(
            title: isEdit ? ref.t('product.edit') : ref.t('product.add_full'),
            isEdit: isEdit,
            onDelete: isEdit ? deleteProduct : null,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) => Form(
                key: formKey,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: c.maxWidth / 2,
                    height: c.maxHeight,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                      children: formChildren,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kCard,
        elevation: 0,
        title: Text(
          isEdit ? ref.t('product.edit') : ref.t('product.add_full'),
          style: TextStyle(
            color: kTextDark,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        iconTheme: IconThemeData(color: kTextDark),
        actions: [
          if (isEdit)
            IconButton(
              icon: const HugeIcon(icon: AppIcons.delete, color: kDanger),
              onPressed: deleteProduct,
            ),
        ],
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: formChildren,
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: kTextDark,
      ),
    ),
  );
}

class _FieldWrap extends StatelessWidget {
  final Widget child;
  const _FieldWrap({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: kCard,
      borderRadius: BorderRadius.circular(12),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: child,
  );
}

class _EmbeddedFormHeader extends StatelessWidget {
  final String title;
  final bool isEdit;
  final VoidCallback? onDelete;
  const _EmbeddedFormHeader({
    required this.title,
    required this.isEdit,
    this.onDelete,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: BoxDecoration(
      color: kCard,
      border: Border(bottom: BorderSide(color: kDivider)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: kTextDark,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
        if (isEdit && onDelete != null)
          IconButton(
            icon: const HugeIcon(icon: AppIcons.delete, color: kDanger),
            onPressed: onDelete,
          ),
      ],
    ),
  );
}

InputDecoration _decoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: TextStyle(color: kTextMid, fontSize: 13),
  border: InputBorder.none,
  contentPadding: const EdgeInsets.symmetric(vertical: 14),
);

class _ProductImagePicker extends StatelessWidget {
  final String? pickedPath;
  final String? remoteUrl;
  final String fallbackSeed;
  final bool isUploading;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _ProductImagePicker({
    required this.pickedPath,
    required this.remoteUrl,
    required this.fallbackSeed,
    required this.isUploading,
    required this.onTap,
    required this.onRemove,
  });

  bool get _hasImage =>
      (pickedPath != null && pickedPath!.isNotEmpty) ||
      (remoteUrl != null && remoteUrl!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: isUploading ? null : onTap,
          borderRadius: BorderRadius.circular(20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(width: 96, height: 96, child: _buildPreview()),
          ),
        ),
        if (isUploading)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                color: Colors.black.withValues(alpha: 0.45),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          right: -4,
          bottom: -4,
          child: Material(
            color: kPrimary,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: isUploading ? null : onTap,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.camera_alt, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
        if (_hasImage && pickedPath != null)
          Positioned(
            left: -4,
            top: -4,
            child: Material(
              color: kDanger,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: isUploading ? null : onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPreview() {
    if (pickedPath != null && pickedPath!.isNotEmpty) {
      return Image.file(
        File(pickedPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    if (remoteUrl != null && remoteUrl!.isNotEmpty) {
      return Image.network(
        resolveAssetUrl(remoteUrl),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() => ProductImage(name: fallbackSeed, size: 96, radius: 20);
}

class _SizeDraft {
  /// Remote ID varian dari backend. Null untuk varian yang baru ditambahkan
  /// di form (belum pernah disimpan). Disertakan di payload supaya backend
  /// melakukan UPDATE bukan INSERT (kalau hilang, varian historis terputus
  /// dari transaksi yang merefer-nya).
  final String? remoteId;
  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;

  /// Stok awal saat draft dibuat. Tidak diedit di form (UI varian belum punya
  /// kolom stok), tapi nilainya dikirim balik supaya stok varian existing
  /// tidak ter-reset ke 0 setiap kali produk di-save.
  final int initialStock;

  /// Diskon spesifik varian. Berlaku saat varian ini dipilih di kasir,
  /// terpisah dari diskon "Regular" produk utama. discountType = 'none'
  /// berarti tidak ada diskon untuk varian.
  String discountType;
  double discountValue;
  String discountName;

  _SizeDraft({
    this.remoteId,
    required this.nameCtrl,
    required this.priceCtrl,
    this.initialStock = 0,
    this.discountType = 'none',
    this.discountValue = 0,
    this.discountName = '',
  });

  factory _SizeDraft.empty() => _SizeDraft(
    nameCtrl: TextEditingController(),
    priceCtrl: TextEditingController(),
  );

  /// Konstruksi dari varian existing. [basePrice] = harga produk utama;
  /// kolom priceCtrl menyimpan **delta** (extra) supaya konsisten dengan UI
  /// "Tambah Harga", bukan harga absolut.
  factory _SizeDraft.fromVariant(ProductVariant v, double basePrice) {
    final extra = v.price - basePrice;
    final extraInt = extra > 0 ? extra.round() : 0;
    return _SizeDraft(
      remoteId: v.remoteId,
      nameCtrl: TextEditingController(text: v.name),
      priceCtrl: TextEditingController(
        text: extraInt > 0 ? 'Rp ${formatThousand(extraInt)}' : '',
      ),
      initialStock: v.stock,
      discountType: v.discountType,
      discountValue: v.discountValue,
      discountName: v.discountName,
    );
  }

  _SizeDraft copy() => _SizeDraft(
    remoteId: remoteId,
    nameCtrl: TextEditingController(text: nameCtrl.text),
    priceCtrl: TextEditingController(text: priceCtrl.text),
    initialStock: initialStock,
    discountType: discountType,
    discountValue: discountValue,
    discountName: discountName,
  );
}

class _VariantEditSheet extends HookWidget {
  final _SizeDraft draft;
  const _VariantEditSheet({required this.draft});

  @override
  Widget build(BuildContext context) {
    final nameCtrl = useTextEditingController(text: draft.nameCtrl.text);
    final priceCtrl = useTextEditingController(text: draft.priceCtrl.text);

    // State diskon varian — paralel dengan section diskon di form produk.
    // Saat ditutup tombol "Simpan Varian", state ini disalin balik ke draft.
    final discountType = useState<String>(draft.discountType);
    final discountNameCtrl = useTextEditingController(
      text: draft.discountName,
    );
    final discountValueCtrl = useTextEditingController(
      text: draft.discountValue > 0
          ? (draft.discountType == 'fixed'
                ? formatThousand(draft.discountValue.toInt())
                : draft.discountValue.toString())
          : '',
    );

    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Detail Varian',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: kTextDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Atur nama, harga, dan diskon untuk varian ini.',
              style: TextStyle(fontSize: 12, color: kTextMid),
            ),
            const SizedBox(height: 20),
            const _Label('Nama Varian'),
            _FieldWrap(
              child: TextFormField(
                controller: nameCtrl,
                autofocus: true,
                decoration: _decoration('Contoh: Large, Dingin, Pakai Patai'),
              ),
            ),
            const SizedBox(height: 12),
            const _Label('Tambah Harga (Opsional)'),
            _FieldWrap(
              child: TextFormField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                decoration: _decoration('+ Rp 0'),
              ),
            ),
            const SizedBox(height: 16),
            _FieldWrap(
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: kPrimary,
                title: Text(
                  'Diskon Khusus Varian',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kTextDark,
                  ),
                ),
                subtitle: Text(
                  'Berlaku hanya saat varian ini dipilih di kasir.',
                  style: TextStyle(fontSize: 11, color: kTextMid),
                ),
                value: discountType.value != 'none',
                onChanged: (v) {
                  discountType.value = v ? 'percent' : 'none';
                  if (!v) discountValueCtrl.clear();
                },
              ),
            ),
            if (discountType.value != 'none') ...[
              const SizedBox(height: 12),
              const _Label('Nama Diskon'),
              _FieldWrap(
                child: TextFormField(
                  controller: discountNameCtrl,
                  decoration: _decoration('Contoh: Promo Patai'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Label('Tipe Diskon'),
                        _FieldWrap(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: discountType.value,
                            decoration: _decoration(''),
                            items: const [
                              DropdownMenuItem(
                                value: 'percent',
                                child: Text('Persentase (%)'),
                              ),
                              DropdownMenuItem(
                                value: 'fixed',
                                child: Text('Nominal (Rp)'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                discountType.value = v;
                                discountValueCtrl.clear();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Label(
                          discountType.value == 'percent'
                              ? 'Nilai (%)'
                              : 'Nilai (Rp)',
                        ),
                        _FieldWrap(
                          child: TextFormField(
                            controller: discountValueCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: discountType.value == 'fixed'
                                ? [RupiahInputFormatter()]
                                : null,
                            decoration: _decoration(
                              discountType.value == 'percent' ? '0%' : 'Rp 0',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  draft.nameCtrl.text = nameCtrl.text;
                  draft.priceCtrl.text = priceCtrl.text;
                  // Sinkronkan state diskon ke draft. type='none' memaksa
                  // value=0 & name='' supaya residu data lama tidak ikut
                  // terkirim ke backend.
                  if (discountType.value == 'none') {
                    draft.discountType = 'none';
                    draft.discountValue = 0;
                    draft.discountName = '';
                  } else {
                    draft.discountType = discountType.value;
                    draft.discountValue = discountType.value == 'fixed'
                        ? parseRupiahInput(discountValueCtrl.text).toDouble()
                        : double.tryParse(discountValueCtrl.text) ?? 0;
                    draft.discountName = discountNameCtrl.text.trim();
                  }
                  Navigator.pop(context, draft);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Simpan Varian',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// C4: sheet pemilih grup modifier untuk sebuah produk. Mengembalikan Set id
// grup terpilih via Navigator.pop. Full-replace: apa pun yang tercentang saat
// "Simpan" itulah set final untuk produk.
class _ModifierGroupPickerSheet extends StatefulWidget {
  final List<ModifierGroup> groups;
  final Set<String> selected;
  const _ModifierGroupPickerSheet({
    required this.groups,
    required this.selected,
  });

  @override
  State<_ModifierGroupPickerSheet> createState() =>
      _ModifierGroupPickerSheetState();
}

class _ModifierGroupPickerSheetState extends State<_ModifierGroupPickerSheet> {
  late Set<String> _sel;

  @override
  void initState() {
    super.initState();
    _sel = {...widget.selected};
  }

  void _toggle(String id) {
    setState(() {
      if (_sel.contains(id)) {
        _sel.remove(id);
      } else {
        _sel.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: kDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Modifier & Add-on',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: kTextDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pilih grup add-on yang muncul saat produk ini ditambahkan di '
            'kasir.',
            style: TextStyle(fontSize: 12, color: kTextMid),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.groups.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (ctx, i) {
                  final g = widget.groups[i];
                  final active = _sel.contains(g.id);
                  return GestureDetector(
                    onTap: () => _toggle(g.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: active ? kPrimary.withValues(alpha: 0.07) : kBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: active ? kPrimary : kDivider,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            active
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            color: active ? kPrimary : kTextMid,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  g.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: active ? kPrimary : kTextDark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${modifierRuleLabel(g)} · ${g.options.length} opsi',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: kTextMid,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _sel),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Simpan',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPickerSheet extends StatelessWidget {
  final List<Category> categories;
  final String? selectedId;
  const _CategoryPickerSheet({
    required this.categories,
    required this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: kDivider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Pilih Kategori',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: kTextDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pilih kategori yang sesuai untuk produk ini',
            style: TextStyle(fontSize: 12, color: kTextMid),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: categories.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (ctx, i) {
                  final c = categories[i];
                  final active = c.remoteId == selectedId;
                  return GestureDetector(
                    onTap: () => Navigator.pop(ctx, c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: active ? kPrimary.withValues(alpha: 0.07) : kBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: active ? kPrimary : kDivider),
                      ),
                      child: Row(
                        children: [
                          HugeIcon(
                            icon: AppIcons.inventory,
                            color: active ? kPrimary : kTextMid,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              c.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: active ? kPrimary : kTextDark,
                              ),
                            ),
                          ),
                          if (active)
                            Container(
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                color: kPrimary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
