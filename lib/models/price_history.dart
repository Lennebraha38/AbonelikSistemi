/// Bir aboneliğin fiyatındaki değişiklik kaydı.
///
/// Abonelik eklendiğinde ilk kayıt atılır; fiyat veya para birimi her
/// değiştiğinde yeni bir kayıt eklenir. Detay ekranında fiyat geçmişi
/// grafiği bu veriyle çizilir.
class PriceHistory {
  final int? id;
  final int subscriptionId;
  final double price;
  final String currency; // TRY | USD | EUR
  final DateTime changedAt;

  const PriceHistory({
    this.id,
    required this.subscriptionId,
    required this.price,
    required this.currency,
    required this.changedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'subscription_id': subscriptionId,
        'price': price,
        'currency': currency,
        'changed_at': changedAt.toIso8601String(),
      };

  factory PriceHistory.fromMap(Map<String, dynamic> map) => PriceHistory(
        id: map['id'] as int?,
        subscriptionId: map['subscription_id'] as int,
        price: (map['price'] as num).toDouble(),
        currency: map['currency'] as String,
        changedAt: DateTime.parse(map['changed_at'] as String),
      );
}
