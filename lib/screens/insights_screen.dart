import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../models/categories.dart';
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
  List<Subscription> _active = const [];
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

    if (!mounted) return;
    setState(() {
      _displayCurrency = currency;
      _active = active;
      _monthlyTotal = monthly;
      _yearlyTotal = monthly * 12;
      _loading = false;
    });
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
        ],
      ),
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

  Widget _buildTopExpensiveCard() {
    final sorted = [..._active]
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
