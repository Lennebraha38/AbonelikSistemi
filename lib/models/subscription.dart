/// Abonelik modeli: her bir aylık/yıllık aboneliği temsil eder.
///
/// Sadece ilk ödeme tarihi (`startDate`) ve fatura döngüsü bilgisi saklanır;
/// bir sonraki yenileme tarihi ve aylık eşdeğer maliyet buradan türetilir.
class Subscription {
  final int? id;
  final String name;
  final double price;
  final String currency; // TRY | USD | EUR
  final String billingCycle; // monthly | yearly
  final DateTime startDate; // ilk ödeme tarihi
  final DateTime? lastNotifiedDate; // son bildirim gönderilen gün

  const Subscription({
    this.id,
    required this.name,
    required this.price,
    required this.currency,
    required this.billingCycle,
    required this.startDate,
    this.lastNotifiedDate,
  });

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

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'price': price,
        'currency': currency,
        'billing_cycle': billingCycle,
        'start_date': startDate.toIso8601String(),
        'last_notified_date': lastNotifiedDate?.toIso8601String(),
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
      );
}

/// Uygulama tamamen çevrimdışı çalıştığı için döviz çevrimi sabit
/// (statik) bir tablo ile yapılır. İsterseniz bu oranları güncelleyebilirsiniz.
class CurrencyConverter {
  static const List<String> supportedCurrencies = ['TRY', 'USD', 'EUR'];

  static const Map<String, String> symbols = {
    'TRY': '₺',
    'USD': r'$',
    'EUR': '€',
  };

  static const Map<String, double> _toUsd = {
    'TRY': 0.029,
    'USD': 1.0,
    'EUR': 1.09,
  };

  static double convert(double amount, String from, String to) {
    if (from == to) return amount;
    final usd = amount * (_toUsd[from] ?? 1.0);
    return usd / (_toUsd[to] ?? 1.0);
  }
}
