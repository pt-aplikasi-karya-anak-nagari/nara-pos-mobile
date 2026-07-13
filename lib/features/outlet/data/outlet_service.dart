import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../products/domain/product.dart';
import '../../../core/image_compress.dart';
import '../../../core/network/api_endpoint.dart';
import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../user/data/auth_service.dart';
import '../../user/domain/user.dart';
import '../../products/domain/category.dart';
import '../../../core/offline/entity_cache.dart';
import '../domain/outlet.dart';

/// Cache offline daftar outlet (global, lintas-outlet) + kategori per outlet.
/// Outlet adalah PRASYARAT offline-first: tanpa fallback ini, cold-start tanpa
/// koneksi → daftar outlet kosong → activeOutletProvider null → seluruh
/// provider kasir mati & pajak diam-diam jatuh ke default 10% PPN.
final _outletCache = EntityCache<Outlet>(
  'outlets',
  toJson: (o) => o.toCacheJson(),
  fromJson: Outlet.fromJson,
);
final _categoryCache = EntityCache<Category>(
  'categories',
  toJson: (c) => c.toCacheJson(),
  fromJson: Category.fromJson,
);

class OutletService extends BaseApiService {
  OutletService(super.dio);

  Future<List<Outlet>> getOutlets() async {
    return get(
      ApiEndpoint.outlets,
      converter: (data) {
        final List<dynamic> list = data;
        return list.map((json) {
          return Outlet.fromJson(json);
        }).toList();
      },
    );
  }

  Future<List<User>> getEmployees(String outletRemoteId) async {
    return get(
      ApiEndpoint.outletEmployees(outletRemoteId),
      converter: (data) {
        final List<dynamic> list = data;
        return list.map((json) => User.fromJson(json)).toList();
      },
    );
  }

  Future<void> createOutlet(Outlet outlet) async {
    await post(
      ApiEndpoint.outlets,
      data: {
        'name': outlet.name,
        'address': outlet.address,
        'phone': outlet.phone,
        'is_active': outlet.isActive,
      },
    );
  }

  Future<void> updateOutlet(Outlet outlet) async {
    if (outlet.remoteId == null) throw 'Outlet tidak memiliki Remote ID';
    await put(
      ApiEndpoint.outletDetail(outlet.remoteId!),
      data: {
        'name': outlet.name,
        'address': outlet.address,
        'phone': outlet.phone,
        'is_active': outlet.isActive,
      },
    );
  }

  Future<void> deleteOutlet(Outlet outlet) async {
    if (outlet.remoteId == null) throw 'Outlet tidak memiliki Remote ID';
    await delete(ApiEndpoint.outletDetail(outlet.remoteId!));
  }

  Future<void> createEmployee(
    String outletId,
    Map<String, dynamic> data,
  ) async {
    await post(ApiEndpoint.outletEmployees(outletId), data: data);
  }

  Future<void> updateEmployee(
    String outletId,
    String userId,
    Map<String, dynamic> data,
  ) async {
    await put('${ApiEndpoint.outletEmployees(outletId)}/$userId', data: data);
  }

  Future<void> deleteEmployee(String outletId, String userId) async {
    await delete('${ApiEndpoint.outletEmployees(outletId)}/$userId');
  }

  Future<List<Category>> getCategories(String outletId) async {
    return get(
      ApiEndpoint.outletCategories(outletId),
      queryParameters: {'pagination': 'false'},
      converter: (data) {
        // Handle paginated response structure if backend returns it
        final List<dynamic> list = data is Map ? (data['items'] ?? []) : data;
        return list.map((json) => Category.fromJson(json)).toList();
      },
    );
  }

  Future<void> saveCategory(String outletId, Category category) async {
    if (category.remoteId != null) {
      await put(
        '/categories/${category.remoteId}',
        data: {'name': category.name},
      );
    } else {
      await post(
        ApiEndpoint.outletCategories(outletId),
        data: {'name': category.name},
      );
    }
  }

  Future<void> deleteCategory(String categoryId) async {
    await delete('/categories/$categoryId');
  }

  Future<List<Product>> getProducts(
    String outletId, {
    String? categoryId,
    String? search,
    bool? isFavorite,
    int? page,
    int? limit,
  }) async {
    // Endpoint khusus favorit lebih hemat: backend langsung filter is_favorite=true
    // sehingga query string tambahan tidak diperlukan.
    if (isFavorite == true) {
      return getFavoriteProducts(
        outletId,
        search: search,
        page: page,
        limit: limit,
      );
    }

    final Map<String, dynamic> params = {};
    if (categoryId != null && categoryId.isNotEmpty) {
      params['category_id'] = categoryId;
    }
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (page != null) params['page'] = page;
    if (limit != null) params['limit'] = limit;

    return get(
      ApiEndpoint.outletProducts(outletId),
      queryParameters: params,
      converter: _productListConverter,
    );
  }

  /// Mengambil hanya produk yang ditandai favorit.
  /// Memanggil endpoint dedicated `/outlets/:outletId/products/favorites`.
  Future<List<Product>> getFavoriteProducts(
    String outletId, {
    String? search,
    int? page,
    int? limit,
  }) async {
    final Map<String, dynamic> params = {};
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (page != null) params['page'] = page;
    if (limit != null) params['limit'] = limit;

    return get(
      ApiEndpoint.outletFavorites(outletId),
      queryParameters: params.isEmpty ? null : params,
      converter: _productListConverter,
    );
  }

  /// Produk terlaris berdasar SUM(quantity) di transaction_items dalam
  /// window [days] hari terakhir (default 30). Backend return list dgn
  /// urutan paling laku di awal. Limit default 10, max 50.
  Future<List<Product>> getBestSellerProducts(
    String outletId, {
    int days = 30,
    int limit = 10,
  }) async {
    final params = <String, dynamic>{
      'days': days,
      'limit': limit,
    };
    return get(
      ApiEndpoint.outletBestSellers(outletId),
      queryParameters: params,
      converter: _productListConverter,
    );
  }

  static List<Product> _productListConverter(dynamic data) {
    // Toleran terhadap dua bentuk response: list polos atau envelope { items: [...] }.
    final List<dynamic> list = data is Map ? (data['items'] ?? []) : data;
    return list.map((json) => Product.fromJson(json)).toList();
  }

  /// Simpan produk (create atau update) dan kembalikan Product hasil simpan.
  /// Berguna untuk callsite yang butuh ID produk baru (mis. upload gambar).
  Future<Product?> saveProduct(
    String outletId,
    Map<String, dynamic> data,
  ) async {
    final id = data['id'];
    if (id != null) {
      await put('/products/$id', data: data);
      // Update endpoint mengembalikan null pada beberapa path; ambil ulang
      // detail-nya dari list (lebih hemat daripada GET /products/:id).
      return null;
    }
    return post<Product?>(
      ApiEndpoint.outletProducts(outletId),
      data: data,
      converter: (raw) {
        if (raw is Map<String, dynamic>) return Product.fromJson(raw);
        return null;
      },
    );
  }

  Future<void> deleteProduct(String productId) async {
    await delete('/products/$productId');
  }

  /// Generate barcode internal (EAN-13) untuk produk yang belum punya barcode.
  /// Idempoten di backend — produk yang sudah punya barcode akan mengembalikan
  /// barcode yang sama. Envelope `{ data: { barcode: ... } }` di-unwrap oleh
  /// [BaseApiService]; converter menerima objek `data`.
  Future<String> generateBarcode(String productId) async {
    return post<String>(
      '/products/$productId/generate-barcode',
      converter: (raw) =>
          (raw is Map ? raw['barcode']?.toString() : null) ?? '',
    );
  }

  Future<void> toggleFavorite(String productId) async {
    await post('/products/$productId/favorite', data: {});
  }

  /// Tandai / pulihkan status "86" (habis manual) sebuah produk dari kasir.
  /// `outOfStock=true` → produk di-86 (disembunyikan dari penjualan);
  /// `false` → dipulihkan. Backend meng-OR-kan flag ini ke is_in_stock dan
  /// mengembalikan Product yang sudah di-enrich (is_in_stock, oos_reason,
  /// available_portions terkini). Envelope `{ data: ... }` di-unwrap oleh
  /// [BaseApiService].
  Future<Product> setManualOutOfStock(String productId, bool outOfStock) async {
    return put<Product>(
      '/products/$productId/manual-86',
      data: {'out_of_stock': outOfStock},
      converter: (raw) => Product.fromJson(raw as Map<String, dynamic>),
    );
  }

  /// Upload gambar produk via multipart/form-data.
  /// Backend menyimpan file ke `uploads/products/` dan mengembalikan
  /// path relatif (mis. `/uploads/products/abc.jpg`) yang bisa di-prefix
  /// host saat menampilkan gambar.
  ///
  /// File di-kompres dulu (JPEG q=50, max 1600 px) supaya bandwidth &
  /// disk hemat — galeri produk biasanya cuma butuh resolusi medium.
  Future<String> uploadProductImage(String productId, String filePath) async {
    final compressedPath = await ImageCompress.compressFile(filePath);
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        compressedPath,
        filename: compressedPath.split('/').last,
      ),
    });
    // Pakai Dio utama (interceptor akan set Authorization). Override hanya
    // Content-Type via Options.contentType — Dio otomatis menambah boundary.
    final res = await dio.post<Map<String, dynamic>>(
      '/products/$productId/image',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        // Penting: ikut sertakan responseType JSON agar Dio tidak salah parse
        // body response (yang merupakan JSON dari backend).
        responseType: ResponseType.json,
      ),
    );
    final body = res.data;
    if (body == null) return '';
    final data = body['data'];
    return (data is Map ? data['image_url']?.toString() : null) ?? '';
  }

  Future<void> batchCreateProducts(
    String outletId,
    List<Map<String, dynamic>> products,
  ) async {
    await post(
      '/outlets/$outletId/products/batch',
      data: {'products': products},
    );
  }

  Future<bool> checkSku(String outletId, String sku) async {
    final res = await get('/outlets/$outletId/products/sku/$sku');
    return res['available'] as bool? ?? false;
  }

  Future<List<Map<String, dynamic>>> getPaymentMethods(String outletId) async {
    return get(
      ApiEndpoint.outletPaymentMethods(outletId),
      converter: (data) {
        final List<dynamic> list = data is Map ? (data['items'] ?? []) : data;
        return list.map((json) => json as Map<String, dynamic>).toList();
      },
    );
  }

  Future<void> savePaymentMethod(
    String outletId,
    Map<String, dynamic> data,
  ) async {
    final id = data['id'];
    if (id != null) {
      await put(ApiEndpoint.paymentMethod(id), data: data);
    } else {
      await post(ApiEndpoint.outletPaymentMethods(outletId), data: data);
    }
  }

  Future<void> deletePaymentMethod(String id) async {
    await delete(ApiEndpoint.paymentMethod(id));
  }

  // Toggle is_active via PATCH endpoint dedicated. Lebih ringan dari PUT
  // full body — dipakai swipe / tap toggle dari list view.
  Future<void> setPaymentMethodActive(String id, bool active) async {
    await patch<void>(
      ApiEndpoint.paymentMethodActive(id),
      data: {'active': active},
    );
  }

  // Tandai metode ini default outlet — backend otomatis unset semua
  // entri lain di outlet yang sama (single-default constraint).
  Future<void> setPaymentMethodDefault(String id) async {
    await patch<void>(ApiEndpoint.paymentMethodDefault(id));
  }

  // Ringkasan agregat untuk dashboard owner — total, active, by_type,
  // default_id. Sama struktur dengan response backend Summary().
  Future<Map<String, dynamic>> getPaymentMethodsSummary(String outletId) async {
    return get<Map<String, dynamic>>(
      ApiEndpoint.outletPaymentMethodsSummary(outletId),
      converter: (data) => data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{},
    );
  }

  // ── Receipt settings ─────────────────────────────────────────────
  //
  // Backend selalu return value — kalau outlet belum pernah save,
  // backend return default in-memory (sama dengan Flutter fallback).

  Future<Map<String, dynamic>> getReceiptSettings(String outletId) async {
    return get<Map<String, dynamic>>(
      ApiEndpoint.outletReceiptSettings(outletId),
      converter: (data) => data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> updateReceiptSettings(
    String outletId,
    Map<String, dynamic> body,
  ) async {
    return put<Map<String, dynamic>>(
      ApiEndpoint.outletReceiptSettings(outletId),
      data: body,
      converter: (data) => data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{},
    );
  }

  Future<void> deleteReceiptLogo(String outletId) async {
    await delete<void>(ApiEndpoint.outletReceiptLogo(outletId));
  }

  // ── Image quality settings ───────────────────────────────────────

  Future<Map<String, dynamic>> getImageSettings(String outletId) async {
    return get<Map<String, dynamic>>(
      ApiEndpoint.outletImageSettings(outletId),
      converter: (data) => data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> updateImageSettings(
    String outletId,
    Map<String, dynamic> body,
  ) async {
    return put<Map<String, dynamic>>(
      ApiEndpoint.outletImageSettings(outletId),
      data: body,
      converter: (data) => data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> getLoyaltySettings(String outletId) async {
    return get<Map<String, dynamic>>(
      ApiEndpoint.outletLoyaltySettings(outletId),
      converter: (data) => data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{},
    );
  }

  /// Pengaturan aplikasi per-outlet (security/PIN, cashier UX, QR menu, dll).
  /// Backend selalu return value — kalau outlet belum pernah save, backend
  /// return default in-memory. Mobile hanya mengonsumsi flag require_pin_*.
  Future<Map<String, dynamic>> getAppSettings(String outletId) async {
    return get<Map<String, dynamic>>(
      ApiEndpoint.outletAppSettings(outletId),
      converter: (data) => data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{},
    );
  }

  // E11: daftar stasiun cetak outlet. Backend membungkus rows di SuccessResponse
  // (data = list), tapi kita juga toleran bila berbentuk {items: [...]}.
  Future<List<Map<String, dynamic>>> getPrintStations(String outletId) async {
    return get<List<Map<String, dynamic>>>(
      ApiEndpoint.outletPrintStations(outletId),
      converter: (data) {
        final List<dynamic> list = data is List
            ? data
            : (data is Map ? (data['items'] ?? []) : <dynamic>[]);
        return list.map((json) => Map<String, dynamic>.from(json)).toList();
      },
    );
  }

  // Default printer per-role (owner-set) untuk role user yang login. Backend
  // membungkus objek di SuccessResponse (data = objek). Selalu return value —
  // kalau owner belum atur, backend kirim default in-memory.
  Future<Map<String, dynamic>> getRolePrinterConfig(String outletId) async {
    return get<Map<String, dynamic>>(
      ApiEndpoint.outletRolePrinterConfigMine(outletId),
      converter: (data) => data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{},
    );
  }

  // C4: grup modifier/add-on untuk sebuah produk.
  Future<List<Map<String, dynamic>>> getProductModifierGroups(
    String outletId,
    String productId,
  ) async {
    return get<List<Map<String, dynamic>>>(
      ApiEndpoint.productModifierGroups(outletId, productId),
      converter: (data) {
        final List<dynamic> list = data is List
            ? data
            : (data is Map ? (data['items'] ?? []) : <dynamic>[]);
        return list.map((json) => Map<String, dynamic>.from(json)).toList();
      },
    );
  }

  // C4 (manajemen): daftar SEMUA grup modifier milik outlet — untuk halaman
  // "Modifier & Add-on" dan dialog attach-ke-produk.
  Future<List<Map<String, dynamic>>> listModifierGroups(String outletId) async {
    return get<List<Map<String, dynamic>>>(
      ApiEndpoint.modifierGroups(outletId),
      converter: (data) {
        final List<dynamic> list = data is List
            ? data
            : (data is Map ? (data['items'] ?? []) : <dynamic>[]);
        return list.map((json) => Map<String, dynamic>.from(json)).toList();
      },
    );
  }

  // C4 (manajemen): buat grup modifier baru (opsi inline, full-set).
  Future<Map<String, dynamic>> createModifierGroup(
    String outletId,
    Map<String, dynamic> body,
  ) async {
    return post<Map<String, dynamic>>(
      ApiEndpoint.modifierGroups(outletId),
      data: body,
      converter: (data) =>
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
    );
  }

  // C4 (manajemen): update grup modifier — opsi di-REPLACE penuh oleh backend.
  Future<Map<String, dynamic>> updateModifierGroup(
    String outletId,
    String id,
    Map<String, dynamic> body,
  ) async {
    return put<Map<String, dynamic>>(
      ApiEndpoint.modifierGroup(outletId, id),
      data: body,
      converter: (data) =>
          data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
    );
  }

  // C4 (manajemen): hapus (soft-delete) grup modifier.
  Future<void> deleteModifierGroup(String outletId, String id) async {
    await delete<void>(ApiEndpoint.modifierGroup(outletId, id));
  }

  // C4 (manajemen): set/replace grup modifier yang melekat pada sebuah produk.
  // Urutan `groupIds` = urutan tampil (sort_order) di kasir.
  Future<void> setProductModifierGroups(
    String outletId,
    String productId,
    List<String> groupIds,
  ) async {
    await put<void>(
      ApiEndpoint.productModifierGroups(outletId, productId),
      data: {'group_ids': groupIds},
    );
  }

  Future<Map<String, dynamic>> updateLoyaltySettings(
    String outletId,
    Map<String, dynamic> body,
  ) async {
    return put<Map<String, dynamic>>(
      ApiEndpoint.outletLoyaltySettings(outletId),
      data: body,
      converter: (data) => data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{},
    );
  }

  Future<Map<String, dynamic>> validatePromo(
    String outletId,
    String code,
  ) async {
    return get<Map<String, dynamic>>(
      ApiEndpoint.outletPromotionsValidate(outletId),
      queryParameters: {'code': code},
      converter: (data) => data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{},
    );
  }

  /// Permission efektif user yang login di outlet — daftar key (mis.
  /// "transactions.refund"). Dipakai aplikasi kasir untuk menegakkan RBAC
  /// yang diatur owner di web.
  Future<List<String>> getMyPermissions(String outletId) async {
    final data = await get<Map<String, dynamic>>(
      ApiEndpoint.outletMyPermissions(outletId),
      converter: (data) => data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{},
    );
    final list = data['permissions'];
    if (list is List) {
      return list.map((e) => e.toString()).toList();
    }
    return const [];
  }
}

final outletServiceProvider = Provider<OutletService>((ref) {
  return OutletService(ref.watch(dioProvider));
});

/// A Notifier to manage the list of outlets directly from the API.
class OutletsNotifier extends AsyncNotifier<List<Outlet>> {
  @override
  Future<List<Outlet>> build() async {
    // Watch token: rebuild ulang setiap kali sesi berubah (login → token
    // muncul, logout → token null). Tanpa ini, build() pertama kali
    // dipanggil saat belum ada token (hasilnya kosong/error) lalu di-cache,
    // sehingga UI tidak pernah menampilkan outlet sampai app di-restart.
    final token = ref.watch(authProvider.select((s) => s.token));
    if (token == null) return const [];
    return readThroughCache(
      cache: _outletCache,
      outletId: kGlobalCacheScope,
      fetch: () => ref.read(outletServiceProvider).getOutlets(),
    );
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => readThroughCache(
        cache: _outletCache,
        outletId: kGlobalCacheScope,
        fetch: () => ref.read(outletServiceProvider).getOutlets(),
      ),
    );
  }
}

final outletsProvider = AsyncNotifierProvider<OutletsNotifier, List<Outlet>>(
  () {
    return OutletsNotifier();
  },
);

final outletEmployeesProvider = FutureProvider.family<List<User>, String>((
  ref,
  outletId,
) async {
  return ref.watch(outletServiceProvider).getEmployees(outletId);
});

final outletCategoriesProvider = FutureProvider.family<List<Category>, String>((
  ref,
  outletId,
) async {
  return readThroughCache(
    cache: _categoryCache,
    outletId: outletId,
    fetch: () => ref.read(outletServiceProvider).getCategories(outletId),
  );
});

/// Daftar produk favorit untuk satu outlet, langsung dari endpoint khusus.
/// Akan auto-refetch saat di-invalidate (mis. setelah toggle favorit).
final outletFavoriteProductsProvider =
    FutureProvider.family<List<Product>, String>((ref, outletId) async {
      return ref.watch(outletServiceProvider).getFavoriteProducts(outletId);
    });
