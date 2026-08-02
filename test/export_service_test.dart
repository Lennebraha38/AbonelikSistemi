import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:subscription_manager/database/app_database.dart';
import 'package:subscription_manager/models/payment.dart';
import 'package:subscription_manager/models/subscription.dart';
import 'package:subscription_manager/services/export_service.dart';

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

  Subscription makeSub({
    int? id,
    String name = 'Netflix',
    double price = 100,
    String currency = 'TRY',
    String billingCycle = 'monthly',
    String status = Subscription.active,
    String category = 'video',
  }) {
    return Subscription(
      id: id,
      name: name,
      price: price,
      currency: currency,
      billingCycle: billingCycle,
      startDate: DateTime(2026, 1, 15),
      status: status,
      category: category,
    );
  }

  test('buildCsv başlık ve satır üretir', () async {
    final csv = await ExportService.buildCsv([
      makeSub(name: 'Spotify'),
      makeSub(name: 'İptal, Edildi', status: Subscription.cancelled),
    ]);

    expect(csv, startsWith('id,name,price,currency,billing_cycle'));
    expect(csv, contains('Spotify'));
    expect(csv, contains('İptal, Edildi'));
    expect(csv, contains('"İptal, Edildi"'));
  });

  test('buildBackupJson → parseBackupJson döngüsü korur', () async {
    final db = AppDatabase.instance;
    final subId = await db.insertSubscription(makeSub(name: 'Netflix'));
    await db.insertPayment(
      Payment(
        subscriptionId: subId,
        amount: 100,
        currency: 'TRY',
        paidAt: DateTime(2026, 7, 20),
      ),
    );

    final json = await ExportService.buildBackupJson();
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['app'], 'subscription_manager');
    expect(decoded['subscriptions'], hasLength(1));
    expect(decoded['payments'], hasLength(1));

    final data = ExportService.parseBackupJson(json);
    expect(data.subscriptions.single.name, 'Netflix');
    expect(data.payments.single.amount, closeTo(100, 0.001));
  });

  test('parseBackupJson geçersiz girdiyi reddeder', () {
    expect(() => ExportService.parseBackupJson('{{'), throwsFormatException);
    expect(
      () => ExportService.parseBackupJson('"düz metin"'),
      throwsFormatException,
    );
  });

  test('restoreBackupData replace ile mevcut veriyi değiştirir', () async {
    final db = AppDatabase.instance;
    await db.insertSubscription(makeSub(name: 'Eski'));

    final backup = ExportService.parseBackupJson(jsonEncode({
      'subscriptions': [
        makeSub(name: 'Yeni').toMap()..['id'] = 99,
      ],
      'payments': [
        {
          'subscription_id': 99,
          'amount': 250,
          'currency': 'TRY',
          'paid_at': '2026-07-01T00:00:00.000',
        },
      ],
    }));

    await ExportService.restoreBackupData(backup, replace: true);

    final subs = await db.getSubscriptions();
    expect(subs, hasLength(1));
    expect(subs.single.name, 'Yeni');

    final payments = await db.getAllPayments();
    expect(payments, hasLength(1));
    expect(payments.single.amount, closeTo(250, 0.001));
    expect(payments.single.subscriptionId, subs.single.id);
  });

  test('restoreBackupData merge ile üzerine ekler', () async {
    final db = AppDatabase.instance;
    await db.insertSubscription(makeSub(name: 'Mevcut'));

    final backup = ExportService.parseBackupJson(jsonEncode({
      'subscriptions': [
        makeSub(name: 'Eklenen').toMap(),
      ],
    }));

    await ExportService.restoreBackupData(backup, replace: false);
    expect(await db.getSubscriptions(), hasLength(2));
  });

  test('restoreBackupData sahipsiz ödemeleri atlar', () async {
    final db = AppDatabase.instance;

    final backup = ExportService.parseBackupJson(jsonEncode({
      'subscriptions': <Map<String, dynamic>>[],
      'payments': [
        {
          'subscription_id': 12345,
          'amount': 50,
          'currency': 'USD',
          'paid_at': '2026-07-01T00:00:00.000',
        },
      ],
    }));

    await ExportService.restoreBackupData(backup, replace: true);
    expect(await db.getAllPayments(), isEmpty);
  });

  test('buildIcs aktif abonelikler için VEVENT üretir', () {
    final ics = ExportService.buildIcs([
      makeSub(name: 'Netflix, HD', billingCycle: 'yearly'),
      makeSub(name: 'İptal', status: Subscription.cancelled),
    ]);

    expect(ics, startsWith('BEGIN:VCALENDAR\n'));
    expect(ics, endsWith('END:VCALENDAR\n'));
    expect(ics, contains('BEGIN:VEVENT'));
    expect(ics, contains('Netflix\\, HD yenileme'));
    expect(ics, contains('RRULE:FREQ=YEARLY;INTERVAL=1'));
    expect(ics, contains('UID:sub-'));
    expect(ics.contains('İptal yenileme'), isFalse);
  });

  test('buildPaymentsCsv başlık ve satır üretir', () async {
    final csv = await ExportService.buildPaymentsCsv(
      [
        Payment(
          subscriptionId: 1,
          amount: 50.5,
          currency: 'TRY',
          paidAt: DateTime(2026, 7, 20),
          note: 'Aylık, ödeme',
        ),
      ],
      {1: 'Netflix'},
    );

    expect(csv, startsWith('subscription_name,amount,currency,paid_at,note'));
    expect(csv, contains('Netflix,50.5,TRY'));
    expect(csv, contains('"Aylık, ödeme"'));
  });

  test('parseCsv abonelik CSV satırlarını çözer', () {
    final csv = 'id,name,price,currency,billing_cycle,start_date,status,'
        'category,trial_end_date,reminder_days,next_renewal_date,'
        'days_until_renewal,monthly_equivalent\n'
        '1,Netflix,100,TRY,monthly,2026-01-15,active,video,,3,'
        '2026-08-15,0,100\n'
        '2,İptal,50,USD,yearly,2025-01-01,cancelled,other,2025-02-01,7,'
        '2026-01-01,0,4.17\n';

    final data = ExportService.parseCsv(csv);

    expect(data.isEmpty, isFalse);
    expect(data.subscriptions, hasLength(2));
    expect(data.subscriptions.first.name, 'Netflix');
    expect(data.subscriptions.first.currency, 'TRY');
    expect(data.subscriptions.first.billingCycle, 'monthly');
    expect(data.subscriptions.last.status, Subscription.cancelled);
    expect(data.subscriptions.last.trialEndDate, DateTime(2025, 2, 1));
    expect(data.subscriptions.last.reminderDays, 7);
    expect(data.payments, isEmpty);
  });

  test('parseCsv ödeme CSV satırlarını çözer', () {
    final csv = 'subscription_name,amount,currency,paid_at,note\n'
        'Netflix,100,TRY,2026-07-20T10:00:00.000,"Aylık, ödeme"\n';

    final data = ExportService.parseCsv(csv);

    expect(data.subscriptions, isEmpty);
    expect(data.payments, hasLength(1));
    expect(data.payments.single.subscriptionName, 'Netflix');
    expect(data.payments.single.amount, closeTo(100, 0.001));
    expect(data.payments.single.paidAt, DateTime(2026, 7, 20, 10));
    expect(data.payments.single.note, 'Aylık, ödeme');
  });

  test('parseCsv bilinmeyen başlıkta boş veri döner', () {
    expect(ExportService.parseCsv('foo,bar\n1,2').isEmpty, isTrue);
    expect(ExportService.parseCsv('').isEmpty, isTrue);
  });

  test('importCsvData yeni veriyi ekler, tekrarları atlar', () async {
    final db = AppDatabase.instance;
    final existingId = await db.insertSubscription(makeSub(name: 'Netflix'));
    await db.insertPayment(
      Payment(
        subscriptionId: existingId,
        amount: 100,
        currency: 'TRY',
        paidAt: DateTime(2026, 7, 20),
      ),
    );

    final subsData = ExportService.parseCsv(
      'id,name,price,currency,billing_cycle,start_date,status,category,'
      'trial_end_date,reminder_days\n'
      '1,Netflix,100,TRY,monthly,2026-01-15,active,video,,3\n'
      '2,Spotify,50,TRY,monthly,2026-03-10,active,music,,3\n',
    );
    final payData = ExportService.parseCsv(
      'subscription_name,amount,currency,paid_at,note\n'
      'Netflix,100,TRY,2026-07-20T10:00:00.000,\n'
      'Spotify,50,TRY,2026-04-10T10:00:00.000,\n'
      'Bilinmeyen,30,TRY,2026-05-01T10:00:00.000,\n',
    );
    final combined = ParsedCsvData(
      subscriptions: subsData.subscriptions,
      payments: payData.payments,
    );

    final result = await ExportService.importCsvData(combined);

    expect(result.addedSubscriptions, 1);
    expect(result.skippedSubscriptions, 1);
    expect(result.addedPayments, 1);
    expect(result.skippedPayments, 2);

    final subs = await db.getSubscriptions();
    expect(subs, hasLength(2));
    expect(subs.map((s) => s.name), containsAll(['Netflix', 'Spotify']));
    expect(await db.getAllPayments(), hasLength(2));
  });
}
