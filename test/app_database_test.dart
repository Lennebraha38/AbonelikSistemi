import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:subscription_manager/database/app_database.dart';
import 'package:subscription_manager/models/payment.dart';
import 'package:subscription_manager/models/subscription.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    AppDatabase.overrideDatabasePath = inMemoryDatabasePath;
    await AppDatabase.instance.resetForTesting();
    await AppDatabase.instance.database;
  });

  tearDown(() async {
    await AppDatabase.instance.resetForTesting();
  });

  Subscription _sub({
    int? id,
    String name = 'Netflix',
    double price = 100,
    String currency = 'TRY',
    String billingCycle = 'monthly',
    String status = Subscription.active,
    String category = 'video',
    DateTime? startDate,
  }) {
    return Subscription(
      id: id,
      name: name,
      price: price,
      currency: currency,
      billingCycle: billingCycle,
      startDate: startDate ?? DateTime(2026, 1, 15),
      status: status,
      category: category,
    );
  }

  test('insert + getSubscriptions döngüsü', () async {
    final db = AppDatabase.instance;
    final id = await db.insertSubscription(_sub(name: 'Spotify'));
    expect(id, greaterThan(0));

    final all = await db.getSubscriptions();
    expect(all, hasLength(1));
    expect(all.first.id, id);
    expect(all.first.name, 'Spotify');
    expect(all.first.category, 'video');
    expect(all.first.status, Subscription.active);
  });

  test('getActiveSubscriptions iptal edilmişleri dışlar', () async {
    final db = AppDatabase.instance;
    await db.insertSubscription(_sub(name: 'Aktif'));
    await db.insertSubscription(
      _sub(name: 'İptal', status: Subscription.cancelled),
    );

    final active = await db.getActiveSubscriptions();
    expect(active, hasLength(1));
    expect(active.first.name, 'Aktif');
  });

  test('cancel / reactivate durumu değiştirir', () async {
    final db = AppDatabase.instance;
    final id = await db.insertSubscription(_sub());

    await db.cancelSubscription(id);
    expect(await db.getActiveSubscriptions(), isEmpty);

    await db.reactivateSubscription(id);
    expect(await db.getActiveSubscriptions(), hasLength(1));
  });

  test('updateSubscription alanları günceller', () async {
    final db = AppDatabase.instance;
    final id = await db.insertSubscription(_sub(name: 'Eski Ad'));

    await db.updateSubscription(_sub(id: id, name: 'Yeni Ad'));

    final all = await db.getSubscriptions();
    expect(all.single.name, 'Yeni Ad');
    expect(all.single.id, id);
  });

  test('deleteSubscription kaydı siler', () async {
    final db = AppDatabase.instance;
    final id = await db.insertSubscription(_sub());
    await db.deleteSubscription(id);
    expect(await db.getSubscriptions(), isEmpty);
  });

  test('getMonthlyTotalByCurrency para birimine göre toplar', () async {
    final db = AppDatabase.instance;
    await db.insertSubscription(_sub(price: 100, currency: 'TRY'));
    await db.insertSubscription(_sub(price: 200, currency: 'TRY'));
    await db.insertSubscription(
      _sub(price: 1200, currency: 'USD', billingCycle: 'yearly'),
    );

    final totals = await db.getMonthlyTotalByCurrency();
    expect(totals['TRY'], closeTo(300, 0.001));
    expect(totals['USD'], closeTo(100, 0.001));
  });

  test('getMonthlyTotal seçili birime çevirir', () async {
    final db = AppDatabase.instance;
    // 300 TRY -> USD (0.029) -> 8.7 USD
    await db.insertSubscription(_sub(price: 100, currency: 'TRY'));
    await db.insertSubscription(_sub(price: 200, currency: 'TRY'));

    final total = await db.getMonthlyTotal(displayCurrency: 'USD');
    expect(total, closeTo(300 * 0.029, 0.001));
  });

  test('getUpcomingRenewals sadece aktif ve yaklaşanları döndürür', () async {
    final db = AppDatabase.instance;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Bugün yenilenecek (kalan 0 gün)
    await db.insertSubscription(
      _sub(name: 'Bugün Yenilenen', startDate: today),
    );
    // Çok sonra yenilenecek
    await db.insertSubscription(
      _sub(
        name: 'Uzak',
        startDate: DateTime(now.year, now.month + 1, now.day),
      ),
    );
    // İptal edilmiş, bugün yenilense de dahil edilmemeli
    await db.insertSubscription(
      _sub(name: 'İptal', status: Subscription.cancelled, startDate: today),
    );

    final upcoming = await db.getUpcomingRenewals(3);
    expect(upcoming, hasLength(1));
    expect(upcoming.first.name, 'Bugün Yenilenen');
  });

  test('updateLastNotifiedDate kaydedilir', () async {
    final db = AppDatabase.instance;
    final id = await db.insertSubscription(_sub());
    final date = DateTime(2026, 5, 1);

    await db.updateLastNotifiedDate(id, date);

    final saved = (await db.getSubscriptions()).single;
    expect(saved.lastNotifiedDate, date);
  });

  test('insertPayment + getPaymentsForSubscription döngüsü', () async {
    final db = AppDatabase.instance;
    final id = await db.insertSubscription(_sub());

    await db.insertPayment(
      Payment(
        subscriptionId: id,
        amount: 100,
        currency: 'TRY',
        paidAt: DateTime(2026, 7, 20),
        note: 'İlk ödeme',
      ),
    );
    await db.insertPayment(
      Payment(
        subscriptionId: id,
        amount: 100,
        currency: 'TRY',
        paidAt: DateTime(2026, 8, 20),
      ),
    );

    final payments = await db.getPaymentsForSubscription(id);
    expect(payments, hasLength(2));
    expect(payments.first.paidAt, DateTime(2026, 8, 20));
    expect(payments.last.note, 'İlk ödeme');
    expect(payments.last.amount, closeTo(100, 0.001));
  });

  test('deletePayment kaydı siler', () async {
    final db = AppDatabase.instance;
    final id = await db.insertSubscription(_sub());
    final payId = await db.insertPayment(
      Payment(
        subscriptionId: id,
        amount: 100,
        currency: 'TRY',
        paidAt: DateTime(2026, 7, 20),
      ),
    );

    await db.deletePayment(payId);
    expect(await db.getPaymentsForSubscription(id), isEmpty);
  });

  test('deleteSubscription ödemeleri de siler', () async {
    final db = AppDatabase.instance;
    final id = await db.insertSubscription(_sub());
    await db.insertPayment(
      Payment(
        subscriptionId: id,
        amount: 100,
        currency: 'TRY',
        paidAt: DateTime(2026, 7, 20),
      ),
    );

    await db.deleteSubscription(id);
    expect(await db.getAllPayments(), isEmpty);
  });
}
