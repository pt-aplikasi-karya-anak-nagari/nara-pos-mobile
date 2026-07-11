class SubscriptionPlan {
  final String code;
  final String name;
  final String description;
  final int priceIdr;
  final int tier;
  final List<String> features;
  final bool isHighlighted;

  const SubscriptionPlan({
    required this.code,
    required this.name,
    required this.description,
    required this.priceIdr,
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
      tier: (json['tier'] as num?)?.toInt() ?? 0,
      features: (json['features'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      isHighlighted: json['is_highlighted'] as bool? ?? false,
    );
  }
}

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
  final int daysRemaining;

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
    required this.daysRemaining,
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
      daysRemaining: (json['days_remaining'] as num?)?.toInt() ?? 0,
    );
  }
}
