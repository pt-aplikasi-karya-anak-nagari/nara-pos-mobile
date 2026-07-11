/// Notifikasi yang pernah masuk ke device. Disimpan lokal di SharedPreferences
/// (lihat `notification_history.dart`) supaya kasir bisa lihat ulang notif
/// yang sudah lewat — banner OS langsung menghilang setelah swipe / dibuka.
///
/// Bukan duplikasi data backend: server tetap punya `transactions` table
/// sebagai source of truth. Entry di sini hanya copy ringkasan + payload
/// supaya bisa kunjung-balik (mis. user tap → buka detail transaksi via
/// `orderId`).
class AppNotification {
  /// ID stabil. Untuk push FCM diisi dari `RemoteMessage.messageId`. Untuk
  /// notif lokal (kasir checkout) di-generate dari hash sale id.
  final String id;
  final String title;
  final String body;
  /// Klasifikasi notif. Konvensi yang dipakai backend:
  ///   * 'new_menu_order' — pesanan baru dari QR menu mako-scan-qr
  ///   * 'order_updated'  — status pesanan berubah (mis. lunas)
  /// Bisa null untuk notif lokal yang tidak punya kategori.
  final String? type;
  /// ID transaksi/sale terkait. Tap notif → push route `/riwayat/<orderId>`.
  final String? orderId;
  final String? invoiceNo;
  /// Nama meja (mis. "A1"). Dipakai cuma untuk ringkasan tampilan.
  final String? table;
  final DateTime receivedAt;
  final bool read;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.type,
    this.orderId,
    this.invoiceNo,
    this.table,
    required this.receivedAt,
    this.read = false,
  });

  AppNotification copyWith({
    bool? read,
  }) {
    return AppNotification(
      id: id,
      title: title,
      body: body,
      type: type,
      orderId: orderId,
      invoiceNo: invoiceNo,
      table: table,
      receivedAt: receivedAt,
      read: read ?? this.read,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        if (type != null) 'type': type,
        if (orderId != null) 'order_id': orderId,
        if (invoiceNo != null) 'invoice_no': invoiceNo,
        if (table != null) 'table': table,
        'received_at': receivedAt.toUtc().toIso8601String(),
        'read': read,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final receivedAt = json['received_at'] != null
        ? DateTime.tryParse(json['received_at'].toString())?.toLocal() ??
            DateTime.now()
        : DateTime.now();
    return AppNotification(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      type: json['type']?.toString(),
      orderId: json['order_id']?.toString(),
      invoiceNo: json['invoice_no']?.toString(),
      table: json['table']?.toString(),
      receivedAt: receivedAt,
      read: json['read'] == true,
    );
  }
}
