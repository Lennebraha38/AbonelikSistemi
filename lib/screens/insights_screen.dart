import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../models/categories.dart';
import '../models/payment.dart';
import '../models/subscription.dart';

/// İstatistik ekranı: yıllık/aylık toplam, yaklaşan ödemeler ve
/// kategori bazında harcama dökümü (donut grafik).
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final NumberFormat _amountFormat =
      NumberFormat.currency(symbol: '', decimalDigits: 2);

  String _displayCurrency = 'TRY';
  double _monthlyTotal = 0;
  double _yearlyTotal = 0;
  double _monthlyBudget = 0;
  List<Subscription> _active = const [];
  List<Payment> _payments = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final currency = prefs.getString('display_currency') ?? 'TRY';
    final active = await AppDatabase.instance.getActiveSubscriptions();
    final monthly =
        await AppDatabase.instance.getMonthlyTotal(displayCurrency: currency);
    final payments = await AppDatabase.instance.getAllPayments();

    if (!mounted) return;
    setState(() {
      _displayCurrency = currency;
      _active = active;
      _monthlyTotal = monthly;
      _yearlyTotal = monthly * 12;
      _monthlyBudget = prefs.getDouble('monthly_budget') ?? 0;
      _payments = payments;
      _loading = false;
    });
  }

  /// Son [months] ay için (bu ay dahil), ödeme geçmişine göre gerçek
  /// harcama. Tüm ödemeler görüntüleme para birimine çevrilir.
  List<_MonthSpend> _monthlySpending(int months) {
    final now = DateTime.now();
    final result = <_MonthSpend>[];
    for (var i = months - 1; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i);
      result.add(_MonthSpend(
        year: d.year,
        month: d.month,
        amount: 0,
        isCurrent: i == 0,
      ));
    }
    for (final p in _payments) {
      final target =
          result.where((m) => m.year == p.paidAt.year && m.month == p.paidAt.month);
      if (target.isEmpty) continue;
      target.first.amount += CurrencyConverter.convert(
        p.amount,
        p.currency,
        _displayCurrency,
      );
    }
    return result;
  }

  List<_CategorySlice> _categorySlices() {
    final totals = <String, double>{};
    final counts = <String, int>{};
    for (final s in _active) {
      final amount = CurrencyConverter.convert(
        s.monthlyEquivalent,
        s.currency,
        _displayCurrency,
      );
      totals[s.category] = (totals[s.category] ?? 0) + amount;
      counts[s.category] = (counts[s.category] ?? 0) + 1;
    }
    final slices = totals.entries.map((e) {
      return _CategorySlice(
        e.key,
        totals[e.key] ?? 0,
        counts[e.key] ?? 0,
        CategoryCatalog.byKey(e.key),
      );
    }).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return slices;
  }

  List<Subscription> _upcomingInDays(int days) {
    final list = _active.where((s) => s.daysUntilRenewal <= days).toList()
      ..sort((a, b) => a.daysUntilRenewal.compareTo(b.daysUntilRenewal));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('İstatistikler')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildTopCard(),
                  const SizedBox(height: 24),
                  _buildUpcomingCard(),
                  const SizedBox(height: 24),
                  _buildCategoryCard(),
                  const SizedBox(height: 24),
                  _buildSpendingCard(),
                  const SizedBox(height: 24),
                  _buildTopExpensiveCard(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildTopCard() {
    final symbol = CurrencyConverter.symbols[_displayCurrency] ?? '';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3949AB), Color(0xFF26A69A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aylık Gider',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$symbol${_amountFormat.format(_monthlyTotal)} $_displayCurrency',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Yıllık Gider',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$symbol${_amountFormat.format(_yearlyTotal)} $_displayCurrency',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${_active.length} aktif abonelik',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (_monthlyBudget > 0) ...[
            const SizedBox(height: 16),
            _buildBudgetProgress(),
          ],
        ],
      ),
    );
  }

  Widget _buildBudgetProgress() {
    final symbol = CurrencyConverter.symbols[_displayCurrency] ?? '';
    final ratio = _monthlyTotal / _monthlyBudget;
    final clamped = ratio.clamp(0.0, 1.0);
    final Color color;
    if (ratio > 1) {
      color = Colors.redAccent;
    } else if (ratio > 0.8) {
      color = Colors.amberAccent;
    } else {
      color = Colors.lightGreenAccent;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Aylık bütçe',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            Text(
              '$symbol${_amountFormat.format(_monthlyTotal)} / '
              '$symbol${_amountFormat.format(_monthlyBudget)} $_displayCurrency',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: clamped,
            minHeight: 8,
            backgroundColor: Colors.white24,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildUpcomingCard() {
    final next7 = _upcomingInDays(7);
    final symbol = CurrencyConverter.symbols[_displayCurrency] ?? '';
    var total7 = 0.0;
    for (final s in next7) {
      total7 += CurrencyConverter.convert(
        s.monthlyEquivalent,
        s.currency,
        _displayCurrency,
      );
    }

    return _sectionCard(
      title: 'Önümüzdeki 7 Gün',
      child: next7.isEmpty
          ? Text(
              'Bu hafta yenileme yok.',
              style: TextStyle(color: Colors.grey.shade600),
            )
          : Column(
              children: [
                for (final s in next7)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      CategoryCatalog.byKey(s.category).icon,
                      color: CategoryCatalog.byKey(s.category).color,
                    ),
                    title: Text(s.name),
                    subtitle: Text(
                      '${DateFormat('dd.MM').format(s.nextRenewalDate)}  •  '
                      '${s.daysUntilRenewal == 0 ? 'bugün' : '${s.daysUntilRenewal} gün'}',
                    ),
                    trailing: Text(
                      '$symbol${s.price.toStringAsFixed(2)} ${s.currency}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                const Divider(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '7 günlük toplam',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    Text(
                      '$symbol${_amountFormat.format(total7)} $_displayCurrency',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildCategoryCard() {
    final slices = _categorySlices();
    if (slices.isEmpty) {
      return _sectionCard(
        title: 'Kategoriye Göre Harcama',
        child: Text(
          'Veri yok.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    final total = slices.fold<double>(0, (sum, s) => sum + s.amount);
    final symbol = CurrencyConverter.symbols[_displayCurrency] ?? '';

    return _sectionCard(
      title: 'Kategoriye Göre Harcama',
      child: Column(
        children: [
          SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _DonutPainter(
                    slices
                        .map((s) =>
                            (value: s.amount, color: s.category.color))
                        .toList(),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$symbol${_amountFormat.format(total)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'aylık',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final slice in slices)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: CircleAvatar(
                radius: 6,
                backgroundColor: slice.category.color,
              ),
              title: Text(slice.category.label),
              trailing: Text(
                '${slice.count} • $symbol${_amountFormat.format(slice.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static const List<String> _trMonths = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];

  /// Ödeme geçmişinden ay bazında gerçek harcamayı gösterir.
  Widget _buildSpendingCard() {
    final symbol = CurrencyConverter.symbols[_displayCurrency] ?? '';
    final months = _monthlySpending(6);
    final hasAny = months.any((m) => m.amount > 0);
    final total = months.fold<double>(0, (sum, m) => sum + m.amount);
    final maxAmount = months.fold<double>(0, (max, m) => math.max(max, m.amount));

    return _sectionCard(
      title: 'Gerçek Harcama (Ödemeler)',
      child: !hasAny
          ? Text(
              'Henüz ödeme kaydı yok. Abonelik detayından '
              '"Ödeme Ekle" ile geçmişi takip edebilirsiniz.',
              style: TextStyle(color: Colors.grey.shade600),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in months)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(
                            m.isCurrent
                                ? '${_trMonths[m.month - 1]} (bu ay)'
                                : _trMonths[m.month - 1],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: m.isCurrent
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            children: [
                              Container(
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                              if (m.amount > 0)
                                FractionallySizedBox(
                                  widthFactor:
                                      maxAmount == 0 ? 0 : m.amount / maxAmount,
                                  child: Container(
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 88,
                          child: Text(
                            '$symbol${_amountFormat.format(m.amount)}',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Son 6 aylık toplam',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    Text(
                      '$symbol${_amountFormat.format(total)} $_displayCurrency',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Ödeme geçmişine eklenen gerçek tutarlar üzerinden hesaplanır.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
    );
  }

  Widget _buildTopExpensiveCard() {    final sorted = [..._active]
      ..sort((a, b) => b.monthlyEquivalent.compareTo(a.monthlyEquivalent));
    final top = sorted.take(3).toList();
    final symbol = CurrencyConverter.symbols[_displayCurrency] ?? '';

    return _sectionCard(
      title: 'En Pahalı Abonelikler',
      child: top.isEmpty
          ? Text(
              'Veri yok.',
              style: TextStyle(color: Colors.grey.shade600),
            )
          : Column(
              children: [
                for (var i = 0; i < top.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    title: Text(top[i].name),
                    subtitle: Text(
                      top[i].billingCycle == 'yearly' ? 'Yıllık' : 'Aylık',
                    ),
                    trailing: Text(
                      '$symbol${top[i].price.toStringAsFixed(2)} '
                      '${top[i].currency}/ay',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _CategorySlice {
  final String key;
  final double amount;
  final int count;
  final CategoryInfo category;

  _CategorySlice(this.key, this.amount, this.count, this.category);
}

/// Belirli bir ayın (yıl + ay) gerçek harcama tutarı.
class _MonthSpend {
  final int year;
  final int month;
  double amount;
  final bool isCurrent;

  _MonthSpend({
    required this.year,
    required this.month,
    required this.amount,
    required this.isCurrent,
  });
}

/// Basit bir donut (halka) grafik çizen painter.
class _DonutPainter extends CustomPainter {
  final List<({double value, Color color})> slices;

  _DonutPainter(this.slices);

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (sum, s) => sum + s.value);
    if (total <= 0) return;

    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2;
    final holeRadius = radius * 0.62;

    final stroke = radius - holeRadius;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    var startAngle = -math.pi / 2;
    for (final slice in slices) {
      final sweep = (slice.value / total) * 2 * math.pi;
      paint.color = slice.color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - stroke / 2),
        startAngle,
        sweep - 0.03,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) => true;
}
