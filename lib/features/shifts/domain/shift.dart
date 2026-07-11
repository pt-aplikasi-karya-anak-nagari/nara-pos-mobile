class Shift {
  String? remoteId;
  DateTime startTime;
  DateTime? endTime;
  double startingCash;
  double totalSales; // Total penjualan tunai pada shift ini (dari backend)
  double? expectedCash;
  double? actualCash;
  double? difference;
  String cashierName;
  String cashierRemoteId;
  String? outletRemoteId;

  /// Legacy single `notes` — masih dibaca dari payload lama supaya
  /// device yang belum sync dengan migration 000093 tetap menampilkan
  /// sesuatu di UI. Versi baru pakai [openingNotes] / [closingNotes].
  String? notes;

  /// Catatan kasir saat OpenShift. Wajib diisi (validated di backend).
  String? openingNotes;

  /// Catatan saat shift ditutup (mis. alasan selisih kas). Opsional.
  String? closingNotes;

  /// User yang melakukan close. NULL = shift masih open. Sama dengan
  /// [cashierRemoteId] = kasir tutup sendiri. Beda = force-close oleh
  /// owner/admin dari dashboard web.
  String? closedByUserId;

  /// Nama user yang close (hydrated dari backend lewat JOIN users).
  String? closedByName;

  bool isOpen;

  /// Diisi HANYA untuk shift yang dibuka OFFLINE (belum sync). [localShiftId]
  /// = id optimistik lokal; [clientRef] = idempotency key (open_client_ref)
  /// yang dipakai saat replay open ke backend. Null untuk shift dari server.
  /// Di-carry lewat cache active_shift supaya bertahan melewati app restart.
  String? localShiftId;
  String? clientRef;

  /// True kalau shift ditutup oleh user lain (force-close). Untuk
  /// menampilkan badge khusus di history page kasir ("Manager closed").
  bool get isForceClosed =>
      !isOpen &&
      closedByUserId != null &&
      closedByUserId!.isNotEmpty &&
      closedByUserId != cashierRemoteId;

  Shift({
    this.remoteId,
    required this.startTime,
    this.endTime,
    required this.startingCash,
    this.totalSales = 0.0,
    this.expectedCash,
    this.actualCash,
    this.difference,
    required this.cashierName,
    required this.cashierRemoteId,
    this.outletRemoteId,
    this.notes,
    this.openingNotes,
    this.closingNotes,
    this.closedByUserId,
    this.closedByName,
    this.isOpen = true,
    this.localShiftId,
    this.clientRef,
  });

  factory Shift.fromJson(Map<String, dynamic> json) {
    final endExpected = _parseDouble(json['end_balance_expected']);
    final endActual = _parseDouble(json['end_balance_actual']);
    final totalSales = _parseDouble(json['total_sales']) ?? 0.0;

    // Backend pakai field `cash_difference` (computed) sejak migration
    // 000093, jadi pakai langsung kalau ada. Fallback ke selisih manual
    // untuk backward compat data lama.
    final cashDiff = _parseDouble(json['cash_difference']);
    final difference = cashDiff ??
        ((endActual != null && endExpected != null)
            ? endActual - endExpected
            : null);

    return Shift(
      remoteId: json['id']?.toString(),
      startTime: json['opened_at'] != null
          ? DateTime.tryParse(json['opened_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      endTime: json['closed_at'] != null
          ? DateTime.tryParse(json['closed_at'].toString())
          : null,
      startingCash: _parseDouble(json['start_balance']) ?? 0.0,
      totalSales: totalSales,
      expectedCash: endExpected,
      actualCash: endActual,
      difference: difference,
      cashierRemoteId: json['user_id']?.toString() ?? '',
      cashierName: json['user_name']?.toString() ?? '',
      outletRemoteId: json['outlet_id']?.toString(),
      notes: json['notes']?.toString(),
      // Field baru migration 000093. Optional di payload — kalau backend
      // belum support, fall back ke `notes` legacy.
      openingNotes: (json['opening_notes'] as String?) ??
          json['notes']?.toString(),
      closingNotes: json['closing_notes'] as String?,
      closedByUserId: json['closed_by_user_id']?.toString(),
      closedByName: json['closed_by_name']?.toString(),
      isOpen: json['status'] == 'open',
      // Key cache-only (backend tidak mengirim ini) — pulihkan id lokal +
      // idempotency key untuk shift offline yang di-cache.
      localShiftId: json['local_shift_id']?.toString(),
      clientRef: json['local_client_ref']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': remoteId,
      'start_balance': startingCash,
      'end_balance_expected': expectedCash,
      'end_balance_actual': actualCash,
    };
  }

  /// Serialisasi setia-fromJson untuk cache offline (EntityCache). [toJson] di
  /// atas adalah payload close-shift (3 field) — TIDAK cukup untuk cache. Ini
  /// menulis ulang seluruh field yang dibaca [fromJson] memakai key backend
  /// yang sama, supaya shift aktif yang di-cache pulih utuh saat offline.
  Map<String, dynamic> toCacheJson() {
    return {
      'id': remoteId,
      'opened_at': startTime.toIso8601String(),
      'closed_at': endTime?.toIso8601String(),
      'start_balance': startingCash,
      'total_sales': totalSales,
      'end_balance_expected': expectedCash,
      'end_balance_actual': actualCash,
      'cash_difference': difference,
      'user_id': cashierRemoteId,
      'user_name': cashierName,
      'outlet_id': outletRemoteId,
      'notes': notes,
      'opening_notes': openingNotes,
      'closing_notes': closingNotes,
      'closed_by_user_id': closedByUserId,
      'closed_by_name': closedByName,
      'status': isOpen ? 'open' : 'closed',
      'local_shift_id': localShiftId,
      'local_client_ref': clientRef,
    };
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
