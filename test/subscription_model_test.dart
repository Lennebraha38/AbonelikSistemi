import 'package:flutter_test/flutter_test.dart';
import 'package:subscription_manager/models/subscription.dart';

void main() {
  group('Subscription.monthlyEquivalent', () {
    test('aylık abonelikte fiyat aynen aylık baza indirgenir', () {
      final s = _subscription(price: 100, billingCycle: 'monthly');
      expect(s.monthlyEquivalent, 100);
    });

    test('yıllık abonelik fiyatı 12\'ye bölünür', () {
      final s = _subscription(price: 1200, billingCycle: 'yearly');
      expect(s.monthlyEquivalent, 100);
    });

    test('yearlyEquivalent yıllık baza indirgenir', () {
      final s = _subscription(price: 50, billingCycle: 'monthly');
      expect(s.yearlyEquivalent, 600);
    });
  });

  group('Subscription.nextRenewalDate', () {
    test('aylık döngüde bugünden sonraki ilk aynı gün', () {
      final start = DateTime(2026, 1, 15);
      final s = _subscription(startDate: start, billingCycle: 'monthly');

      final now = DateTime.now();
      final todayOnly = DateTime(now.year, now.month, now.day);
      var expected = DateTime(now.year, now.month, 15);
      if (expected.isBefore(todayOnly)) {
        expected = DateTime(now.year, now.month + 1, 15);
      }
      expect(s.nextRenewalDate, expected);
    });

    test('yıllık döngüde bir sonraki yılın aynı günü', () {
      final start = DateTime(2025, 3, 10);
      final s = _subscription(startDate: start, billingCycle: 'yearly');
      final next = s.nextRenewalDate;
      expect(next.month, 3);
      expect(next.day, 10);
      expect(next.isBefore(DateTime.now()), isFalse);
    });
  });

  group('Subscription.daysUntilRenewal', () {
    test('başlangıç bugünse kalan gün 0 olur', () {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final s = _subscription(startDate: start, billingCycle: 'monthly');
      expect(s.daysUntilRenewal, 0);
    });
  });

  group('Subscription durum ve deneme', () {
    test('varsayılan durum aktif', () {
      expect(_subscription().isCancelled, isFalse);
    });

    test('cancelled durumu isCancelled döndürür', () {
      final s = _subscription(status: Subscription.cancelled);
      expect(s.isCancelled, isTrue);
    });

    test('deneme bitiş tarihi gelecekteyse isOnTrial true', () {
      final now = DateTime.now();
      final end = DateTime(now.year, now.month, now.day + 1);
      final s = _subscription(trialEndDate: end);
      expect(s.isOnTrial, isTrue);
    });

    test('deneme bitiş tarihi geçmişse isOnTrial false', () {
      final now = DateTime.now();
      final end = DateTime(now.year, now.month, now.day - 1);
      final s = _subscription(trialEndDate: end);
      expect(s.isOnTrial, isFalse);
    });

    test('daysUntilTrialEnd bitişe kalan günü verir', () {
      final now = DateTime.now();
      final end = DateTime(now.year, now.month, now.day + 3);
      final s = _subscription(trialEndDate: end);
      expect(s.daysUntilTrialEnd, 3);
    });
  });

  group('Subscription.toMap / fromMap', () {
    test('alanlar yuvarlak yolculukta korunur', () {
      final original = Subscription(
        id: 7,
        name: 'Netflix',
        price: 199.9,
        currency: 'TRY',
        billingCycle: 'monthly',
        startDate: DateTime(2025, 1, 15),
        status: Subscription.cancelled,
        category: 'video',
        trialEndDate: DateTime(2025, 2, 15),
        reminderDays: 7,
      );
      final restored = Subscription.fromMap(original.toMap());
      expect(restored.id, 7);
      expect(restored.name, 'Netflix');
      expect(restored.price, 199.9);
      expect(restored.currency, 'TRY');
      expect(restored.billingCycle, 'monthly');
      expect(restored.status, Subscription.cancelled);
      expect(restored.category, 'video');
      expect(restored.trialEndDate, DateTime(2025, 2, 15));
      expect(restored.reminderDays, 7);
    });

    test('eksik alanlar varsayılanlara döner', () {
      final restored = Subscription.fromMap({
        'id': 1,
        'name': 'Spotify',
        'price': 59.99,
        'currency': 'TRY',
        'billing_cycle': 'monthly',
        'start_date': DateTime(2026, 1, 1).toIso8601String(),
      });
      expect(restored.status, Subscription.active);
      expect(restored.category, 'other');
      expect(restored.reminderDays, Subscription.defaultReminderDays);
      expect(restored.trialEndDate, isNull);
    });
  });
}

Subscription _subscription({
  double price = 100,
  String billingCycle = 'monthly',
  DateTime? startDate,
  DateTime? trialEndDate,
  String status = Subscription.active,
}) {
  return Subscription(
    name: 'Test Aboneliği',
    price: price,
    currency: 'TRY',
    billingCycle: billingCycle,
    startDate: startDate ?? DateTime(2026, 1, 1),
    trialEndDate: trialEndDate,
    status: status,
  );
}
