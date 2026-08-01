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

  Subscription _sub({
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
      _sub(name: 'Spotify'),
      _sub(name: 'İptal, Edildi', status: Subscription.cancelled),
    ]);

    expect(csv, startsWith('id,name,price,currency,billing_cycle'));
    expect(csv, contains('Spotify'));
    expect(csv, contains('İptal, Edildi'));
    expect(csv, contains('"İptal, Edildi"'));
  });

  test('buildBackupJson → parseBackupJson döngüsü korur', () async {
    final db = AppDatabase.instance;
    final subId = await db.insertSubscription(_sub(name: 'Netflix'));
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
    await db.insertSubscription(_sub(name: 'Eski'));

    final backup = ExportService.parseBackupJson(jsonEncode({
      'subscriptions': [
        _sub(name: 'Yeni').toMap()..['id'] = 99,
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
    await db.insertSubscription(_sub(name: 'Mevcut'));

    final backup = ExportService.parseBackupJson(jsonEncode({
      'subscriptions': [
        _sub(name: 'Eklenen').toMap(),
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
      _sub(name: 'Netflix, HD', billingCycle: 'yearly'),
      _sub(name: 'İptal', status: Subscription.cancelled),
    ]);

    expect(ics, startsWith('BEGIN:VCALENDAR\n'));
    expect(ics, endsWith('END:VCALENDAR\n'));
    expect(ics, contains('BEGIN:VEVENT'));
    expect(ics, contains('Netflix\\, HD yenileme'));
    expect(ics, contains('RRULE:FREQ=YEARLY;INTERVAL=1'));
    expect(ics, contains('UID:sub-'));
    expect(ics.contains('İptal yenileme'), isFalse);
  });
}
