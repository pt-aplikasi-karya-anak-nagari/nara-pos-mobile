import '../../transactions/domain/sale.dart';

class Customer {
    String id;

  String name;
  String phone;
  String email;
  String address;

  int points;
  String membershipLevel; // Regular, Silver, Gold, Platinum

    DateTime createdAt;

    DateTime updatedAt;

  String createdBy;

    List<Sale> sales = [];

  Customer({
    this.id = '',
    required this.name,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.points = 0,
    this.membershipLevel = 'Regular',
    this.createdBy = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      points: json['points'] is int ? json['points'] : int.tryParse(json['points']?.toString() ?? '0') ?? 0,
      membershipLevel: () {
        // Backend bisa kirim null/kosong; fallback ke 'Regular' agar UI tak
        // render label kosong ("Level: ", "0 ()").
        final m = json['membership_level']?.toString();
        return (m == null || m.isEmpty) ? 'Regular' : m;
      }(),
      createdBy: json['created_by']?.toString() ?? '',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now() : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'points': points,
      'membership_level': membershipLevel,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
