import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/network/base_api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/outlet_scope.dart';

// Pencatatan pengeluaran (expenses) di mobile — parity dengan web/backend (C2).
// Merchant mobile-first bisa catat belanja bahan, bensin, gaji harian dari HP.

class ExpenseCategory {
  final String id;
  final String name;
  final String icon;
  const ExpenseCategory({required this.id, required this.name, required this.icon});

  factory ExpenseCategory.fromJson(Map<String, dynamic> j) => ExpenseCategory(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    icon: j['icon']?.toString() ?? 'wallet',
  );
}

class Expense {
  final String id;
  final String title;
  final double amount;
  final String? categoryName;
  final String paymentMethod;
  final DateTime paidAt;
  final String? vendorName;

  const Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.categoryName,
    required this.paymentMethod,
    required this.paidAt,
    required this.vendorName,
  });

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
    id: j['id']?.toString() ?? '',
    title: j['title']?.toString() ?? '',
    amount: (j['amount'] as num?)?.toDouble() ?? 0,
    categoryName: j['category_name']?.toString(),
    paymentMethod: j['payment_method']?.toString() ?? '',
    paidAt: DateTime.tryParse(j['paid_at']?.toString() ?? '') ?? DateTime.now(),
    vendorName: j['vendor_name']?.toString(),
  );
}

class ExpenseService extends BaseApiService {
  ExpenseService(super.dio);

  Future<List<ExpenseCategory>> listCategories(String outletId) async {
    return get(
      '/outlets/$outletId/expense-categories',
      converter: (data) {
        final list = data as List<dynamic>? ?? const [];
        return list
            .map((e) => ExpenseCategory.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      },
    );
  }

  Future<List<Expense>> listExpenses(String outletId, {String? dateFrom, String? dateTo}) async {
    return get(
      '/outlets/$outletId/expenses',
      queryParameters: {
        if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
        'limit': 200,
      },
      converter: (data) {
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        final list = map['items'] as List<dynamic>? ?? const [];
        return list
            .map((e) => Expense.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      },
    );
  }

  Future<double> summaryTotal(String outletId, {String? dateFrom, String? dateTo}) async {
    return get(
      '/outlets/$outletId/expenses/summary',
      queryParameters: {
        if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
      },
      converter: (data) {
        final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
        return (map['total_amount'] as num?)?.toDouble() ?? 0;
      },
    );
  }

  Future<void> create(
    String outletId, {
    required String title,
    required double amount,
    String? categoryId,
    String paymentMethod = 'Tunai',
    String? vendorName,
    required DateTime paidAt,
  }) async {
    await post(
      '/outlets/$outletId/expenses',
      data: {
        'title': title,
        'amount': amount,
        if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
        'payment_method': paymentMethod,
        if (vendorName != null && vendorName.isNotEmpty) 'vendor_name': vendorName,
        'paid_at': paidAt.toIso8601String(),
      },
      converter: (data) => data,
    );
  }

  Future<void> deleteExpense(String id) async {
    await delete('/expenses/$id', converter: (data) => data);
  }
}

final expenseServiceProvider = Provider<ExpenseService>((ref) {
  return ExpenseService(ref.watch(dioProvider));
});

// Rentang bulan berjalan.
({String from, String to}) _thisMonth() {
  final now = DateTime.now();
  String d(DateTime x) =>
      '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  return (from: d(DateTime(now.year, now.month, 1)), to: d(now));
}

final expensesProvider = FutureProvider<List<Expense>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return [];
  final m = _thisMonth();
  return ref.watch(expenseServiceProvider).listExpenses(outletId, dateFrom: m.from, dateTo: m.to);
});

final expenseTotalProvider = FutureProvider<double>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return 0;
  final m = _thisMonth();
  return ref.watch(expenseServiceProvider).summaryTotal(outletId, dateFrom: m.from, dateTo: m.to);
});

final expenseCategoriesProvider = FutureProvider<List<ExpenseCategory>>((ref) async {
  final outletId = ref.watch(activeOutletIdProvider);
  if (outletId == null) return [];
  return ref.watch(expenseServiceProvider).listCategories(outletId);
});
