class SubscriptionPlan {
  final String code;
  final String name;
  final String description;
  final int priceIdr;

  /// Harga satu tahun. 0 = paket tidak dijual tahunan.
  final int priceYearlyIdr;
  final int tier;
  final List<String> features;
  final bool isHighlighted;

  const SubscriptionPlan({
    required this.code,
    required this.name,
    required this.description,
    required this.priceIdr,
    this.priceYearlyIdr = 0,
    required this.tier,
    required this.features,
    required this.isHighlighted,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      priceIdr: (json['price_idr'] as num?)?.toInt() ?? 0,
      priceYearlyIdr: (json['price_yearly_idr'] as num?)?.toInt() ?? 0,
      tier: (json['tier'] as num?)?.toInt() ?? 0,
      features: (json['features'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      isHighlighted: json['is_highlighted'] as bool? ?? false,
    );
  }

  bool get tersediaTahunan => priceYearlyIdr > 0;

  /// Harga untuk [siklus] ('monthly' / 'yearly'); tahunan yang tak tersedia
  /// jatuh ke harga bulanan.
  int hargaSiklus(String siklus) =>
      siklus == siklusTahunan && tersediaTahunan ? priceYearlyIdr : priceIdr;

  /// Selisih 12× bulanan dengan harga tahunan (0 bila tak hemat).
  int get hematTahunan {
    if (!tersediaTahunan) return 0;
    final h = priceIdr * 12 - priceYearlyIdr;
    return h > 0 ? h : 0;
  }

  /// Setara per bulan bila bayar tahunan.
  int get perBulanTahunan => (priceYearlyIdr / 12).round();
}

const siklusBulanan = 'monthly';
const siklusTahunan = 'yearly';

String labelSiklus(String? siklus) =>
    siklus == siklusTahunan ? 'Tahunan' : 'Bulanan';

class OutletSubscription {
  final String id;
  final String outletId;
  final String planCode;
  final String? planName;
  final String status;
  final bool isTrial;
  final DateTime startedAt;
  final DateTime expiresAt;
  final int priceIdrPaid;

  /// 'monthly' / 'yearly' dari pembayaran terakhir (data lama = bulanan).
  final String billingCycle;
  final int daysRemaining;

  /// Akhir masa tenggang (expires_at + tenggang). Null dari server lama.
  final DateTime? graceUntil;

  /// Key fitur katalog yang termasuk dalam plan langganan outlet ini
  /// (Basic ≈ 12, Pro ≈ 28, Enterprise ≈ 41). Dipakai untuk gating menu
  /// berbasis plan di halaman Profil. Kosong = fail-open (semua fitur tampil).
  final List<String> featureKeys;

  const OutletSubscription({
    required this.id,
    required this.outletId,
    required this.planCode,
    this.planName,
    required this.status,
    required this.isTrial,
    required this.startedAt,
    required this.expiresAt,
    required this.priceIdrPaid,
    this.billingCycle = siklusBulanan,
    required this.daysRemaining,
    this.graceUntil,
    this.featureKeys = const [],
  });

  bool get isUsable {
    final hasActiveStatus = status == 'trial' || status == 'active';
    return hasActiveStatus && expiresAt.isAfter(DateTime.now());
  }

  factory OutletSubscription.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) {
      if (value is String) {
        return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
      }
      return DateTime.now();
    }

    return OutletSubscription(
      id: json['id']?.toString() ?? '',
      outletId: json['outlet_id']?.toString() ?? '',
      planCode: json['plan_code']?.toString() ?? '',
      planName: json['plan_name']?.toString(),
      status: json['status']?.toString() ?? '',
      isTrial: json['is_trial'] as bool? ?? false,
      startedAt: parseDate(json['started_at']),
      expiresAt: parseDate(json['expires_at']),
      priceIdrPaid: (json['price_idr_paid'] as num?)?.toInt() ?? 0,
      billingCycle: json['billing_cycle']?.toString() == siklusTahunan
          ? siklusTahunan
          : siklusBulanan,
      daysRemaining: (json['days_remaining'] as num?)?.toInt() ?? 0,
      graceUntil: DateTime.tryParse(
        json['grace_until']?.toString() ?? '',
      )?.toLocal(),
      featureKeys: (json['feature_keys'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Masa tenggang bawaan server bila respons tak menyebutkan grace_until.
const masaTenggangAsal = Duration(days: 3);

/// Batas terakhir outlet boleh BERJUALAN OFFLINE: akhir masa tenggang.
DateTime batasJualOffline(OutletSubscription s) =>
    s.graceUntil ?? s.expiresAt.add(masaTenggangAsal);

/// Masih boleh berjualan offline pada [acuan] (jam yang tak bisa dimundurkan,
/// lihat JamOffline.waktuAcuan)? Sesudah masa tenggang server menolak
/// transaksinya; berjualan terus offline hanya menumpuk transaksi yang tak
/// akan diterima. MURNI.
bool bolehJualOffline(OutletSubscription s, DateTime acuan) =>
    !acuan.isAfter(batasJualOffline(s));
