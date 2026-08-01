import 'package:flutter_test/flutter_test.dart';
import 'package:subscription_manager/models/payment.dart';

void main() {
  test('toMap/fromMap döngüsü', () {
    final payment = Payment(
      id: 7,
      subscriptionId: 3,
      amount: 149.9,
      currency: 'TRY',
      paidAt: DateTime(2026, 7, 15, 12, 30),
      note: 'Aylık ödeme',
    );

    final restored = Payment.fromMap(payment.toMap());

    expect(restored.id, 7);
    expect(restored.subscriptionId, 3);
    expect(restored.amount, closeTo(149.9, 0.0001));
    expect(restored.currency, 'TRY');
    expect(restored.paidAt, DateTime(2026, 7, 15, 12, 30));
    expect(restored.note, 'Aylık ödeme');
  });

  test('fromMap eksik alanlara karşı sağlamdır', () {
    final payment = Payment.fromMap({
      'subscription_id': 1,
      'amount': 50,
      'currency': 'USD',
      'paid_at': '2026-01-01T00:00:00.000',
    });
    expect(payment.id, isNull);
    expect(payment.note, isNull);
    expect(payment.amount, 50.0);
  });
}
