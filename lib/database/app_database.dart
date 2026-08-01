import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/subscription.dart';

/// Yerel SQLite veritabanı katmanı.
/// Tüm CRUD işlemleri ve aylık toplam maliyet hesapları burada yapılır.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'subscriptions.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE subscriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            currency TEXT NOT NULL,
            billing_cycle TEXT NOT NULL,
            start_date TEXT NOT NULL,
            last_notified_date TEXT
          )
        ''');
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
    });
  }

  // ---------- READ ----------

  Future<List<Subscription>> getSubscriptions() async {
    final db = await database;
    final rows = await db.query('subscriptions', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Subscription.fromMap).toList();
  }

  /// Yenilenmesine [withinDays] gün veya daha az kalmış abonelikler,
  /// yenileme tarihine göre sıralı.
  Future<List<Subscription>> getUpcomingRenewals(int withinDays) async {
    final subscriptions = await getSubscriptions();
    return subscriptions
        .where((s) => s.daysUntilRenewal <= withinDays)
        .toList()
      ..sort((a, b) => a.daysUntilRenewal.compareTo(b.daysUntilRenewal));
  }

  /// Her para birimi için aylık baza indirgenmiş toplam.
  Future<Map<String, double>> getMonthlyTotalByCurrency() async {
    final subscriptions = await getSubscriptions();
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

  // ---------- DELETE ----------

  Future<int> deleteSubscription(int id) async {
    final db = await database;
    return db.delete('subscriptions', where: 'id = ?', whereArgs: [id]);
  }
}
