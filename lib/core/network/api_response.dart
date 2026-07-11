class ApiResponse<T> {
  final bool success;
  final String? message;
  final T? data;
  final PaginationMeta? pagination;

  ApiResponse({
    required this.success,
    this.message,
    this.data,
    this.pagination,
  });

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromJsonT,
  ) {
    final rawData = json['data'];

    // Backend membungkus list dalam { items: [...], pagination: {...} }.
    // Auto-unwrap hanya bila bentuknya benar-benar envelope pagination —
    // bukan sekadar map yang kebetulan punya key "items" (mis. Sale detail
    // yang punya field items berisi line items transaksi).
    dynamic payload = rawData;
    PaginationMeta? meta;
    if (_isPaginationEnvelope(rawData)) {
      final map = rawData as Map<String, dynamic>;
      payload = map['items'];
      final p = map['pagination'];
      if (p is Map<String, dynamic>) {
        meta = PaginationMeta.fromJson(p);
      }
    }

    return ApiResponse<T>(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String?,
      pagination: meta,
      data: payload != null
          ? (fromJsonT != null ? fromJsonT(payload) : payload as T?)
          : null,
    );
  }

  /// Envelope pagination dari backend selalu berbentuk salah satu dari:
  ///   { "items": [...] }                              // pagination=false
  ///   { "items": [...], "pagination": { ... } }       // pagination=true
  /// Map dengan key tambahan (mis. detail object yang punya field "items")
  /// tidak dianggap envelope.
  static bool _isPaginationEnvelope(dynamic data) {
    if (data is! Map<String, dynamic>) return false;
    if (data['items'] is! List) return false;
    for (final key in data.keys) {
      if (key != 'items' && key != 'pagination') return false;
    }
    return true;
  }
}

class PaginationMeta {
  final int page;
  final int limit;
  final int totalItems;
  final int totalPages;

  const PaginationMeta({
    required this.page,
    required this.limit,
    required this.totalItems,
    required this.totalPages,
  });

  factory PaginationMeta.fromJson(Map<String, dynamic> json) {
    return PaginationMeta(
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 0,
      totalItems: (json['total_items'] as num?)?.toInt() ?? 0,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Hasil fetch list yang membawa data + metadata pagination dari backend.
class Paginated<T> {
  final List<T> items;
  final PaginationMeta? pagination;

  const Paginated({required this.items, this.pagination});

  bool get hasMore {
    final p = pagination;
    if (p == null) return false;
    return p.page < p.totalPages;
  }
}
