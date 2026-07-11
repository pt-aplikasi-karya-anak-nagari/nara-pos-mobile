import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/shared_prefs.dart';
import '../../../core/outlet_scope.dart';
import '../../outlet/data/outlet_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoyaltySettings {
  final bool enabled;
  final double amountPerPoint; // How much IDR spent equals 1 point
  final double pointValue; // How much IDR discount 1 point gives
  // E5: pengali poin per tier (mis. {"Gold": 1.25}). Kosong = tanpa boost.
  final Map<String, double> tierMultipliers;

  const LoyaltySettings({
    this.enabled = true,
    this.amountPerPoint = 10000.0,
    this.pointValue = 100.0,
    this.tierMultipliers = const {},
  });

  LoyaltySettings copyWith({
    bool? enabled,
    double? amountPerPoint,
    double? pointValue,
    Map<String, double>? tierMultipliers,
  }) => LoyaltySettings(
    enabled: enabled ?? this.enabled,
    amountPerPoint: amountPerPoint ?? this.amountPerPoint,
    pointValue: pointValue ?? this.pointValue,
    tierMultipliers: tierMultipliers ?? this.tierMultipliers,
  );

  /// Pengali poin untuk sebuah tier (mis. customer.membershipLevel), 1.0 bila
  /// tier itu tak punya multiplier (atau ≤ 0). Lookup case-insensitive supaya
  /// konsisten dengan pewarnaan badge (yang pakai toLowerCase) — beda casing
  /// antara key config dan membership_level tidak menyembunyikan multiplier.
  double multiplierFor(String level) {
    final m = tierMultipliers[level.toLowerCase()];
    return (m != null && m > 0) ? m : 1.0;
  }

  static Map<String, double> _parseMultipliers(dynamic raw) {
    final out = <String, double>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        // Key dinormalisasi ke lowercase agar lookup case-insensitive.
        if (v is num) out[k.toString().toLowerCase()] = v.toDouble();
      });
    }
    return out;
  }

  // Backend memakai snake_case (lihat entity.OutletLoyaltySettings):
  // enabled, amount_per_point, point_value, tier_multipliers.
  factory LoyaltySettings.fromJson(Map<String, dynamic> j) => LoyaltySettings(
    enabled: j['enabled'] as bool? ?? true,
    amountPerPoint: (j['amount_per_point'] as num?)?.toDouble() ?? 10000.0,
    pointValue: (j['point_value'] as num?)?.toDouble() ?? 100.0,
    tierMultipliers: _parseMultipliers(j['tier_multipliers']),
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'amount_per_point': amountPerPoint,
    'point_value': pointValue,
    'tier_multipliers': tierMultipliers,
  };
}

/// Loyalty settings per-outlet dengan backend sebagai sumber kebenaran.
///
/// Sebelumnya settings ini hanya disimpan di SharedPreferences per-perangkat,
/// sehingga dua kasir dengan HP berbeda (atau kasir vs konfigurasi web) bisa
/// menghitung poin berbeda untuk transaksi yang sama. Sekarang:
///   - `build()` membaca cache lokal dulu (biar UI tidak flash nilai default),
///     lalu menyinkronkan dari backend untuk outlet aktif.
///   - Setiap perubahan (setEnabled/setAmountPerPoint/setPointValue) di-PUT ke
///     backend `/outlets/:id/loyalty-settings` DAN disimpan ke cache lokal
///     (optimistic — kalau offline, tetap tersimpan lokal & tersinkron nanti).
class LoyaltySettingsNotifier extends Notifier<LoyaltySettings> {
  static const _kEnabled = 'loyalty.enabled';
  static const _kAmountPerPoint = 'loyalty.amountPerPoint';
  static const _kPointValue = 'loyalty.pointValue';
  static const _kTierMultipliers = 'loyalty.tierMultipliers';

  late SharedPreferences _prefs;

  @override
  LoyaltySettings build() {
    _prefs = ref.read(sharedPreferencesProvider);
    final cached = LoyaltySettings(
      enabled: _prefs.getBool(_kEnabled) ?? true,
      amountPerPoint: _prefs.getDouble(_kAmountPerPoint) ?? 10000.0,
      pointValue: _prefs.getDouble(_kPointValue) ?? 100.0,
      tierMultipliers: LoyaltySettings._parseMultipliers(
        _decodeJson(_prefs.getString(_kTierMultipliers)),
      ),
    );
    // Re-fetch dari backend tiap kali outlet aktif berubah. Sengaja pakai
    // watch supaya ganti outlet memicu build ulang + fetch ulang.
    final outletId = ref.watch(activeOutletIdProvider);
    if (outletId != null) {
      _fetchFromBackend(outletId);
    }
    return cached;
  }

  Future<void> _fetchFromBackend(String outletId) async {
    try {
      final raw = await ref
          .read(outletServiceProvider)
          .getLoyaltySettings(outletId);
      final fresh = LoyaltySettings.fromJson(raw);
      await _cache(fresh);
      state = fresh;
    } catch (_) {
      // Biarkan pakai cache lokal kalau backend gagal (offline / belum ada
      // baris settings). Tidak menimpa state supaya nilai lokal tetap valid.
    }
  }

  Future<void> _cache(LoyaltySettings s) async {
    await _prefs.setBool(_kEnabled, s.enabled);
    await _prefs.setDouble(_kAmountPerPoint, s.amountPerPoint);
    await _prefs.setDouble(_kPointValue, s.pointValue);
    await _prefs.setString(_kTierMultipliers, jsonEncode(s.tierMultipliers));
  }

  static dynamic _decodeJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist(LoyaltySettings s) async {
    state = s;
    await _cache(s);
    final outletId = ref.read(activeOutletIdProvider);
    if (outletId != null) {
      try {
        await ref
            .read(outletServiceProvider)
            .updateLoyaltySettings(outletId, s.toJson());
      } catch (_) {
        // Optimistic — perubahan sudah tersimpan lokal; akan tersinkron ke
        // backend saat online / owner menyimpan ulang.
      }
    }
  }

  Future<void> setEnabled(bool v) => _persist(state.copyWith(enabled: v));

  Future<void> setAmountPerPoint(double v) =>
      _persist(state.copyWith(amountPerPoint: v > 0 ? v : 1.0));

  Future<void> setPointValue(double v) =>
      _persist(state.copyWith(pointValue: v >= 0 ? v : 0.0));
}

final loyaltySettingsProvider =
    NotifierProvider<LoyaltySettingsNotifier, LoyaltySettings>(
      LoyaltySettingsNotifier.new,
    );
