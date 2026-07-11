/// Satu sesi absensi user kasir.
///
/// Sesi dimulai saat [checkInAt] terisi (saat user check-in) dan
/// ditutup saat [checkOutAt] terisi (saat user check-out). Sesi yang
/// belum tutup berarti user "sedang bekerja".
class Attendance {
  final String id;
  final String userId;
  final String outletId;
  final DateTime checkInAt;
  final DateTime? checkOutAt;
  final String? checkInPhotoUrl;
  final String? checkOutPhotoUrl;
  final String? notes;
  final String? userName;

  const Attendance({
    required this.id,
    required this.userId,
    required this.outletId,
    required this.checkInAt,
    this.checkOutAt,
    this.checkInPhotoUrl,
    this.checkOutPhotoUrl,
    this.notes,
    this.userName,
  });

  bool get isActive => checkOutAt == null;

  /// Durasi sesi: dari check-in sampai check-out (atau sekarang kalau
  /// masih aktif). Berguna untuk tampilkan "Sudah bekerja Xj Ym".
  Duration durationUntil(DateTime now) =>
      (checkOutAt ?? now).difference(checkInAt);

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      outletId: json['outlet_id']?.toString() ?? '',
      checkInAt: DateTime.tryParse(json['check_in_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.now(),
      checkOutAt: json['check_out_at'] != null
          ? DateTime.tryParse(json['check_out_at'].toString())?.toLocal()
          : null,
      checkInPhotoUrl: json['check_in_photo_url']?.toString(),
      checkOutPhotoUrl: json['check_out_photo_url']?.toString(),
      notes: json['notes']?.toString(),
      userName: json['user_name']?.toString(),
    );
  }
}
