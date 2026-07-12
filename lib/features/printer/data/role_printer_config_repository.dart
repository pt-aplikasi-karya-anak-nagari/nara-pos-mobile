// Default printer PER-ROLE yang diatur owner di backend, plus penggabungan
// nilai efektif (override user → default role → pengaturan struk outlet →
// fallback hardcoded).
//
// Alur: PrinterSettings menyimpan OVERRIDE per-user (tri-state). Bila user tak
// menimpa sebuah field, nilai jatuh ke default role dari backend
// (`GET /outlets/:id/role-printer-config/mine`). Bila fetch gagal / offline,
// dipakai [RolePrinterConfig.fallback] supaya auto-print tetap jalan.

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/outlet_scope.dart';
import '../../outlet/data/outlet_service.dart';
import '../domain/receipt_settings.dart';
import 'printer_settings.dart';
import 'receipt_settings_repository.dart';

/// Default printer efektif untuk role user yang login (owner-set per role).
class RolePrinterConfig {
  final bool autoPrintReceipt;
  final bool autoPrintKitchen;
  final int printCopies;

  /// Ukuran kertas dalam mm: 58 | 72 | 80.
  final int paperSize;

  /// `true` bila objek ini adalah fallback hardcoded (fetch gagal / outlet
  /// belum dipilih), bukan konfigurasi nyata dari backend. Dipakai agar
  /// pengaturan struk outlet bisa menang atas nilai hardcoded untuk
  /// copies/paper saat offline.
  final bool isFallback;

  const RolePrinterConfig({
    required this.autoPrintReceipt,
    required this.autoPrintKitchen,
    required this.printCopies,
    required this.paperSize,
    this.isFallback = false,
  });

  /// Default aman saat offline / belum ada konfigurasi. Auto-print struk ON
  /// supaya perilaku baku "cetak otomatis" tetap bekerja walau role config
  /// belum termuat.
  static const fallback = RolePrinterConfig(
    autoPrintReceipt: true,
    autoPrintKitchen: false,
    printCopies: 1,
    paperSize: 58,
    isFallback: true,
  );

  factory RolePrinterConfig.fromJson(Map<String, dynamic> json) {
    return RolePrinterConfig(
      autoPrintReceipt: json['auto_print_receipt'] as bool? ?? true,
      autoPrintKitchen: json['auto_print_kitchen'] as bool? ?? false,
      printCopies: (json['print_copies'] as num?)?.toInt() ?? 1,
      paperSize: (json['paper_size'] as num?)?.toInt() ?? 58,
    );
  }
}

class RolePrinterConfigRepository {
  final Ref _ref;
  RolePrinterConfigRepository(this._ref);

  Future<RolePrinterConfig> get(String outletId) async {
    final raw =
        await _ref.read(outletServiceProvider).getRolePrinterConfig(outletId);
    return RolePrinterConfig.fromJson(raw);
  }
}

final rolePrinterConfigRepositoryProvider =
    Provider<RolePrinterConfigRepository>((ref) {
  return RolePrinterConfigRepository(ref);
});

/// Default role untuk outlet aktif. Tak pernah melempar — offline / error →
/// [RolePrinterConfig.fallback] supaya konsumen selalu punya baseline.
final rolePrinterConfigProvider =
    FutureProvider<RolePrinterConfig>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return RolePrinterConfig.fallback;
  try {
    return await ref.watch(rolePrinterConfigRepositoryProvider).get(outletId);
  } catch (_) {
    return RolePrinterConfig.fallback;
  }
});

// ── Nilai efektif (override user → default role → struk outlet → hardcoded) ──

/// Konversi [PaperSize] → mm (58/72/80). Terpisah dari `.value` (1/2/3).
int mmOfPaperSize(PaperSize s) {
  if (s.value == PaperSize.mm80.value) return 80;
  if (s.value == PaperSize.mm72.value) return 72;
  return 58;
}

/// Konversi mm (58/72/80) → [PaperSize].
PaperSize paperSizeFromMm(int mm) {
  if (mm >= 80) return PaperSize.mm80;
  if (mm >= 72) return PaperSize.mm72;
  return PaperSize.mm58;
}

/// Nilai printer yang benar-benar dipakai saat mencetak — hasil gabungan
/// override user, default role, dan pengaturan struk outlet.
class EffectivePrinterConfig {
  final bool autoPrint;
  final bool autoPrintKitchen;
  final int copies;
  final PaperSize paperSize;

  const EffectivePrinterConfig({
    required this.autoPrint,
    required this.autoPrintKitchen,
    required this.copies,
    required this.paperSize,
  });

  /// Presedensi:
  ///   auto-print / dapur : override user → default role.
  ///   salinan / kertas   : override user → default role (nyata) →
  ///                        pengaturan struk outlet → fallback hardcoded role.
  static EffectivePrinterConfig resolve({
    required PrinterSettings user,
    required RolePrinterConfig role,
    OutletReceiptSettings? receipt,
  }) {
    final autoPrint = user.autoPrintOverride ?? role.autoPrintReceipt;
    final autoPrintKitchen =
        user.autoPrintKitchenOverride ?? role.autoPrintKitchen;

    // Untuk copies/paper: default role nyata menang atas struk outlet. Bila
    // role hanya fallback (offline), struk outlet dipakai lebih dulu daripada
    // nilai hardcoded.
    final copies = user.copiesOverride ??
        (role.isFallback ? null : role.printCopies) ??
        receipt?.printCopies ??
        role.printCopies;

    final int paperMm = user.paperSizeOverride != null
        ? mmOfPaperSize(user.paperSizeOverride!)
        : (role.isFallback
            ? (receipt?.paperSize ?? role.paperSize)
            : role.paperSize);

    return EffectivePrinterConfig(
      autoPrint: autoPrint,
      autoPrintKitchen: autoPrintKitchen,
      copies: copies,
      paperSize: paperSizeFromMm(paperMm),
    );
  }
}

/// Nilai efektif untuk outlet + user aktif. SINKRON & tak pernah menunggu
/// jaringan: membaca nilai default role/struk yang SUDAH termuat (atau fallback
/// bila belum). Ini penting untuk jalur cetak OFFLINE — mengembalikan Future
/// yang menunggu GET role-config akan memblokir auto-print hingga timeout dio
/// saat offline. Nilai role/struk dipra-muat di layar kasir (ref.watch), lalu
/// provider ini otomatis recompute saat future-nya selesai.
final effectivePrinterConfigProvider = Provider<EffectivePrinterConfig>((ref) {
  final user = ref.watch(printerSettingsProvider);
  final role = ref.watch(rolePrinterConfigProvider).asData?.value ??
      RolePrinterConfig.fallback;
  final receipt = ref.watch(receiptSettingsFutureProvider).asData?.value;
  return EffectivePrinterConfig.resolve(
    user: user,
    role: role,
    receipt: receipt,
  );
});
