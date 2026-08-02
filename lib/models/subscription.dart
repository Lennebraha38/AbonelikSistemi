import 'package:shared_preferences/shared_preferences.dart';

/// Abonelik modeli: her bir aylık/yıllık aboneliği temsil eder.
///
/// Sadece ilk ödeme tarihi (`startDate`) ve fatura döngüsü bilgisi saklanır;
/// bir sonraki yenileme tarihi ve aylık eşdeğer maliyet buradan türetilir.
class Subscription {
  /// Durum değerleri: 'active' (devam eden) veya 'cancelled' (iptal edilmiş).
  static const String active = 'active';
  static const String cancelled = 'cancelled';

  /// Varsayılan hatırlatma günü: yenilemeden kaç gün önce uyarılmalı.
  static const int defaultReminderDays = 3;

  final int? id;
  final String name;
  final double price;
  final String currency; // TRY | USD | EUR
  final String billingCycle; // monthly | yearly
  final DateTime startDate; // ilk ödeme tarihi
  final DateTime? lastNotifiedDate; // son bildirim gönderilen gün
  final String status; // active | cancelled
  final String category; // kategori anahtarı (bkz. CategoryCatalog)
  final DateTime? trialEndDate; // deneme süresinin bittiği gün (varsa)
  final int reminderDays; // yenilemeden kaç gün önce uyarı (1/3/7)

  const Subscription({
    this.id,
    required this.name,
    required this.price,
    required this.currency,
    required this.billingCycle,
    required this.startDate,
    this.lastNotifiedDate,
    this.status = active,
    this.category = 'other',
    this.trialEndDate,
    this.reminderDays = defaultReminderDays,
  });

  bool get isCancelled => status == cancelled;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Bugün ya da bugünden sonra gerçekleşecek bir sonraki yenileme tarihi.
  DateTime get nextRenewalDate {
    final today = _dateOnly(DateTime.now());
    final start = _dateOnly(startDate);

    if (billingCycle == 'yearly') {
      var years = today.year - start.year;
      if (years < 0) years = 0;
      var next = DateTime(start.year + years, start.month, start.day);
      while (next.isBefore(today)) {
        next = DateTime(next.year + 1, next.month, next.day);
      }
      return next;
    }

    var months = (today.year - start.year) * 12 + (today.month - start.month);
    if (months < 0) months = 0;
    var next = DateTime(start.year, start.month + months, start.day);
    while (next.isBefore(today)) {
      next = DateTime(next.year, next.month + 1, next.day);
    }
    return next;
  }

  /// Yenilemeye kalan gün sayısı (0 = bugün).
  int get daysUntilRenewal =>
      _dateOnly(nextRenewalDate).difference(_dateOnly(DateTime.now())).inDays;

  /// Aylık baza indirgenmiş maliyet.
  double get monthlyEquivalent =>
      billingCycle == 'monthly' ? price : price / 12;

  /// Yıllık baza indirgenmiş maliyet.
  double get yearlyEquivalent => monthlyEquivalent * 12;

  /// Aktif bir deneme süresi var mı? (trialEndDate bugün veya ileride)
  bool get isOnTrial {
    final end = trialEndDate;
    if (end == null) return false;
    return !_dateOnly(end).isBefore(_dateOnly(DateTime.now()));
  }

  /// Deneme süresinin bitmesine kalan gün sayısı (negatifse çoktan bitmiş).
  int get daysUntilTrialEnd {
    final end = trialEndDate;
    if (end == null) return 0;
    return _dateOnly(end).difference(_dateOnly(DateTime.now())).inDays;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'price': price,
        'currency': currency,
        'billing_cycle': billingCycle,
        'start_date': startDate.toIso8601String(),
        'last_notified_date': lastNotifiedDate?.toIso8601String(),
        'status': status,
        'category': category,
        'trial_end_date': trialEndDate?.toIso8601String(),
        'reminder_days': reminderDays,
      };

  factory Subscription.fromMap(Map<String, dynamic> map) => Subscription(
        id: map['id'] as int?,
        name: map['name'] as String,
        price: (map['price'] as num).toDouble(),
        currency: map['currency'] as String,
        billingCycle: map['billing_cycle'] as String,
        startDate: DateTime.parse(map['start_date'] as String),
        lastNotifiedDate: map['last_notified_date'] == null
            ? null
            : DateTime.parse(map['last_notified_date'] as String),
        status: (map['status'] as String?) ?? active,
        category: (map['category'] as String?) ?? 'other',
        trialEndDate: map['trial_end_date'] == null
            ? null
            : DateTime.parse(map['trial_end_date'] as String),
        reminderDays: (map['reminder_days'] as int?) ?? defaultReminderDays,
      );
}

/// Uygulama tamamen çevrimdışı çalıştığı için döviz çevrimi dahili bir
/// tabloyla yapılır. Kullanıcı Ayarlar > Döviz Kurları bölümünden
/// (1 USD = ? TRY / EUR) oranları elle güncelleyebilir; burada saklanır.
class CurrencyConverter {
  static const List<String> supportedCurrencies = ['TRY', 'USD', 'EUR'];

  static const Map<String, String> symbols = {
    'TRY': '₺',
    'USD': r'$',
    'EUR': '€',
  };

  /// Varsayılan oranlar: 1 birim döviz = kaç USD.
  /// TRY 0.029 -> 1 USD ≈ 34.48 TRY; EUR 1.09 -> 1 EUR = 1.09 USD.
  static const Map<String, double> _defaultToUsd = {
    'TRY': 0.029,
    'USD': 1.0,
    'EUR': 1.09,
  };

  static const String _prefUsdToTry = 'fx_usd_try';
  static const String _prefUsdToEur = 'fx_usd_eur';

  static Map<String, double> _toUsd = Map.of(_defaultToUsd);

  /// SharedPreferences'tan kaydedilmiş kullanıcı kurunu okur.
  /// Kayıt yoksa varsayılan oranlar kullanılır.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final usdToTry = _safeDouble(prefs, _prefUsdToTry);
    final usdToEur = _safeDouble(prefs, _prefUsdToEur);
    _toUsd = Map.of(_defaultToUsd);
    if (usdToTry != null && usdToTry > 0) _toUsd['TRY'] = 1 / usdToTry;
    if (usdToEur != null && usdToEur > 0) _toUsd['EUR'] = 1 / usdToEur;
  }

  /// Bozuk/uyumsuz bir değer saklanmışsa çevrimi çökertmeden yoksay.
  static double? _safeDouble(SharedPreferences prefs, String key) {
    try {
      final value = prefs.getDouble(key);
      return (value == null || !value.isFinite) ? null : value;
    } catch (_) {
      return null;
    }
  }

  /// Kullanıcının girdiği kurları kaydeder:
  /// [usdToTry] -> 1 USD kaç TRY; [usdToEur] -> 1 USD kaç EUR.
  static Future<void> saveRates({
    required double usdToTry,
    required double usdToEur,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefUsdToTry, usdToTry);
    await prefs.setDouble(_prefUsdToEur, usdToEur);
    await load();
  }

  static double get usdToTryRate => 1 / _toUsd['TRY']!;
  static double get usdToEurRate => 1 / _toUsd['EUR']!;

  static double convert(double amount, String from, String to) {
    if (from == to) return amount;
    final usd = amount * (_toUsd[from] ?? 1.0);
    return usd / (_toUsd[to] ?? 1.0);
  }
}
