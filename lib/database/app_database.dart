import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/subscription.dart';

/// Yerel SQLite veritabanı katmanı.
/// Tüm CRUD işlemleri ve aylık toplam maliyet hesapları burada yapılır.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  /// Şema sürümü. Değişiklik yapıldığında bir üst sayıya çekilir ve
  /// [onUpgrade] içine eski sürümden gelen migration'lar eklenir.
  static const int schemaVersion = 3;

  /// Testlerde normal dosya yolunu geçersiz kılar (örn. `:memory:`).
  @visibleForTesting
  static String? overrideDatabasePath;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  /// Test sonrası veritabanını kapatıp sıfırlar.
  @visibleForTesting
  Future<void> resetForTesting() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      overrideDatabasePath ?? join(dbPath, 'subscriptions.db'),
      version: schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE subscriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            currency TEXT NOT NULL,
            billing_cycle TEXT NOT NULL,
            start_date TEXT NOT NULL,
            last_notified_date TEXT,
            status TEXT NOT NULL DEFAULT 'active',
            category TEXT NOT NULL DEFAULT 'other',
            trial_end_date TEXT,
            reminder_days INTEGER NOT NULL DEFAULT 3
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE subscriptions ADD COLUMN status TEXT NOT NULL DEFAULT 'active'",
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE subscriptions ADD COLUMN category TEXT NOT NULL DEFAULT 'other'",
          );
          await db.execute(
            'ALTER TABLE subscriptions ADD COLUMN trial_end_date TEXT',
          );
          await db.execute(
            'ALTER TABLE subscriptions ADD COLUMN reminder_days INTEGER NOT NULL DEFAULT 3',
          );
        }
      },
    );
  }

  // ---------- CREATE ----------

  Future<int> insertSubscription(Subscription subscription) async {
    final db = await database;
    return db.insert('subscriptions', {
      'name': subscription.name,
      'price': subscription.price,
      'currency': subscription.currency,
      'billing_cycle': subscription.billingCycle,
      'start_date': subscription.startDate.toIso8601String(),
      'status': subscription.status,
      'category': subscription.category,
      'trial_end_date': subscription.trialEndDate?.toIso8601String(),
      'reminder_days': subscription.reminderDays,
    });
  }

  // ---------- READ ----------

  Future<List<Subscription>> getSubscriptions() async {
    final db = await database;
    final rows = await db.query('subscriptions', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Subscription.fromMap).toList();
  }

  /// Sadece aktif (iptal edilmemiş) abonelikler.
  Future<List<Subscription>> getActiveSubscriptions() async {
    final subscriptions = await getSubscriptions();
    return subscriptions.where((s) => !s.isCancelled).toList();
  }

  /// Yenilenmesine [withinDays] gün veya daha az kalmış **aktif**
  /// abonelikler, yenileme tarihine göre sıralı.
  Future<List<Subscription>> getUpcomingRenewals(int withinDays) async {
    final subscriptions = await getActiveSubscriptions();
    return subscriptions
        .where((s) => s.daysUntilRenewal <= withinDays)
        .toList()
      ..sort((a, b) => a.daysUntilRenewal.compareTo(b.daysUntilRenewal));
  }

  /// Her para birimi için aylık baza indirgenmiş toplam (sadece aktif olanlar).
  Future<Map<String, double>> getMonthlyTotalByCurrency() async {
    final subscriptions = await getActiveSubscriptions();
    final totals = <String, double>{};
    for (final s in subscriptions) {
      totals[s.currency] = (totals[s.currency] ?? 0) + s.monthlyEquivalent;
    }
    return totals;
  }

  /// [displayCurrency] cinsinden aylık toplam gider.
  /// Yıllık abonelikler /12 ile aylık baza indirgenir.
  Future<double> getMonthlyTotal({required String displayCurrency}) async {
    final totals = await getMonthlyTotalByCurrency();
    var total = 0.0;
    totals.forEach((from, amount) {
      total += CurrencyConverter.convert(amount, from, displayCurrency);
    });
    return total;
  }

  // ---------- UPDATE ----------

  Future<int> updateSubscription(Subscription subscription) async {
    final db = await database;
    return db.update(
      'subscriptions',
      subscription.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [subscription.id],
    );
  }

  /// Aynı gün birden fazla bildirim gönderilmemesi için kullanılır.
  Future<void> updateLastNotifiedDate(int id, DateTime date) async {
    final db = await database;
    await db.update(
      'subscriptions',
      {'last_notified_date': date.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Aboneliği iptal eder: toplam gider ve bildirimlere dahil edilmez.
  Future<void> cancelSubscription(int id) async {
    final db = await database;
    await db.update(
      'subscriptions',
      {'status': Subscription.cancelled},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// İptal edilmiş aboneliği tekrar aktif eder.
  Future<void> reactivateSubscription(int id) async {
    final db = await database;
    await db.update(
      'subscriptions',
      {'status': Subscription.active},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------- DELETE ----------

  Future<int> deleteSubscription(int id) async {
    final db = await database;
    return db.delete('subscriptions', where: 'id = ?', whereArgs: [id]);
  }
}
