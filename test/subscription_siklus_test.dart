import 'package:flutter_test/flutter_test.dart';
import 'package:nara_pos_mobile/features/billing/domain/billing_invoice.dart';
import 'package:nara_pos_mobile/features/subscription/domain/subscription.dart';

void main() {
  final pro = SubscriptionPlan.fromJson({
    'code': 'pro',
    'name': 'Pro',
    'price_idr': 299000,
    'price_yearly_idr': 2990000,
    'tier': 2,
  });
  final lama = SubscriptionPlan.fromJson({'code': 'basic', 'price_idr': 99000});

  test('harga per siklus', () {
    expect(pro.hargaSiklus(siklusBulanan), 299000);
    expect(pro.hargaSiklus(siklusTahunan), 2990000);
    expect(pro.hematTahunan, 598000);
    expect(pro.perBulanTahunan, 249167);
  });

  test('server lama tanpa harga tahunan: hanya bulanan', () {
    expect(lama.tersediaTahunan, isFalse);
    expect(lama.hargaSiklus(siklusTahunan), 99000);
    expect(lama.hematTahunan, 0);
  });

  test('siklus dari JSON; data lama = bulanan', () {
    final sub = OutletSubscription.fromJson({'billing_cycle': 'yearly'});
    expect(sub.billingCycle, siklusTahunan);
    expect(OutletSubscription.fromJson({}).billingCycle, siklusBulanan);
    expect(
      BillingInvoice.fromJson({'billing_cycle': 'yearly'}).billingCycle,
      'yearly',
    );
    expect(BillingInvoice.fromJson({}).billingCycle, 'monthly');
    expect(labelSiklus('yearly'), 'Tahunan');
    expect(labelSiklus(null), 'Bulanan');
  });
}
