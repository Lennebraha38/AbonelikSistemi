/// Bir abonelik için yapılmış ödeme kaydı.
class Payment {
  final int? id;
  final int subscriptionId;
  final double amount;
  final String currency; // TRY | USD | EUR
  final DateTime paidAt;
  final String? note;

  const Payment({
    this.id,
    required this.subscriptionId,
    required this.amount,
    required this.currency,
    required this.paidAt,
    this.note,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'subscription_id': subscriptionId,
        'amount': amount,
        'currency': currency,
        'paid_at': paidAt.toIso8601String(),
        'note': note,
      };

  factory Payment.fromMap(Map<String, dynamic> map) => Payment(
        id: map['id'] as int?,
        subscriptionId: map['subscription_id'] as int,
        amount: (map['amount'] as num).toDouble(),
        currency: map['currency'] as String,
        paidAt: DateTime.parse(map['paid_at'] as String),
        note: map['note'] as String?,
      );
}
