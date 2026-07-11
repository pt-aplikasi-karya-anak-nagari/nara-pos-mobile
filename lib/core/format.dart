import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Locale default seluruh aplikasi untuk format angka & tanggal.
/// Ubah di sini saja kalau di masa depan butuh dukungan multi-locale.
const String kAppLocale = 'id_ID';

final NumberFormat _rupiahFormat = NumberFormat.currency(
  locale: kAppLocale,
  symbol: 'Rp ',
  decimalDigits: 0,
);

final NumberFormat _thousandFormat = NumberFormat.decimalPattern(kAppLocale);

// Formatter date/time dipakai di seluruh app. Semua locale-aware.
final DateFormat _dateFormat = DateFormat('d MMMM yyyy', kAppLocale);
final DateFormat _shortDateFormat = DateFormat('d MMM yyyy', kAppLocale);
final DateFormat _dayMonthFormat = DateFormat('d MMM', kAppLocale);
final DateFormat _dateTimeFormat = DateFormat('d MMM yyyy, HH:mm', kAppLocale);
final DateFormat _fullDateTimeFormat = DateFormat(
  'EEEE, d MMMM yyyy HH:mm',
  kAppLocale,
);
final DateFormat _timeFormat = DateFormat('HH:mm', kAppLocale);
final DateFormat _isoDateFormat = DateFormat('yyyy-MM-dd', kAppLocale);
final DateFormat _monthYearFormat = DateFormat('MMMM yyyy', kAppLocale);

String formatRupiah(num v) => _rupiahFormat.format(v);

String formatThousand(num v) => _thousandFormat.format(v);

/// Tanggal panjang berlokal Indonesia, mis. "3 Mei 2026".
String formatDate(DateTime dt) => _dateFormat.format(dt.toLocal());

/// Tanggal singkat, mis. "3 Mei 2026" → "3 Mei 2026" (sama untuk Mei).
/// Untuk bulan panjang seperti September, hasil: "3 Sep 2026".
String formatShortDate(DateTime dt) => _shortDateFormat.format(dt.toLocal());

/// Hanya hari & bulan singkat, mis. "3 Mei".
String formatDayMonth(DateTime dt) => _dayMonthFormat.format(dt.toLocal());

/// Tanggal + jam, mis. "3 Mei 2026, 14:05".
String formatDateTime(DateTime dt) => _dateTimeFormat.format(dt.toLocal());

/// Versi panjang dengan nama hari, mis. "Sabtu, 3 Mei 2026 14:05".
String formatFullDateTime(DateTime dt) =>
    _fullDateTimeFormat.format(dt.toLocal());

/// Hanya jam, mis. "14:05".
String formatTime(DateTime dt) => _timeFormat.format(dt.toLocal());

/// Tanggal ISO untuk filter/grouping, mis. "2026-05-03".
String formatIsoDate(DateTime dt) => _isoDateFormat.format(dt.toLocal());

/// Bulan & tahun, mis. "Mei 2026".
String formatMonthYear(DateTime dt) => _monthYearFormat.format(dt.toLocal());

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int parseRupiahInput(String text) {
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 0;
  return int.tryParse(digits) ?? 0;
}

class RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final value = int.tryParse(digits) ?? 0;
    final formatted = 'Rp ${_thousandFormat.format(value)}';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
