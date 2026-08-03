import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/app_database.dart';
import '../models/categories.dart';
import '../models/subscription.dart';
import 'subscription_detail_screen.dart';

/// Aylık takvim görünümü: yaklaşan yenileme tarihleri işaretlenir.
/// Bir güne dokununca o gün yenilenen abonelikler listelenir.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const List<String> _trMonths = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];
  static const List<String> _trWeekdays = [
    'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz',
  ];

  final NumberFormat _amountFormat =
      NumberFormat.currency(symbol: '', decimalDigits: 2);

  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<Subscription> _active = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final active = await AppDatabase.instance.getActiveSubscriptions();
    if (!mounted) return;
    setState(() {
      _active = active;
      _loading = false;
    });
  }

  /// Bir aboneliğin verilen ay içindeki (geçmişte kalmayan) yenileme günleri.
  List<DateTime> _renewalDatesIn(DateTime firstOfMonth, Subscription s) {
    final result = <DateTime>[];
    final lastDay = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 0);
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    if (s.billingCycle == 'yearly') {
      for (var y = s.startDate.year; ; y++) {
        final d = DateTime(y, s.startDate.month, s.startDate.day);
        if (d.isAfter(lastDay)) break;
        if (!d.isBefore(firstOfMonth) && !d.isBefore(todayOnly)) result.add(d);
      }
    } else {
      for (var months = 0; ; months++) {
        final d = DateTime(
          s.startDate.year,
          s.startDate.month + months,
          s.startDate.day,
        );
        if (d.isAfter(lastDay)) break;
        if (!d.isBefore(firstOfMonth) && !d.isBefore(todayOnly)) result.add(d);
      }
    }
    return result;
  }

  /// Ay içinde yenilenecek abonelikler: gün -> abonelikler.
  Map<int, List<Subscription>> _renewalsByDay() {
    final map = <int, List<Subscription>>{};
    for (final s in _active) {
      for (final d in _renewalDatesIn(_visibleMonth, s)) {
        map.putIfAbsent(d.day, () => []).add(s);
      }
    }
    return map;
  }

  Future<void> _openDetail(Subscription s) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SubscriptionDetailScreen(subscription: s)),
    );
    await _load();
  }

  void _showDayRenewals(int day) {
    final items = _renewalsByDay()[day] ?? const <Subscription>[];
    if (items.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            Text(
              '${day} ${_trMonths[_visibleMonth.month - 1]} — Yenilemeler',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final s in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: CategoryCatalog.byKey(s.category).color
                      .withValues(alpha: 0.15),
                  child: Icon(
                    CategoryCatalog.byKey(s.category).icon,
                    size: 18,
                    color: CategoryCatalog.byKey(s.category).color,
                  ),
                ),
                title: Text(s.name),
                subtitle: Text(
                  s.billingCycle == 'yearly' ? 'Yıllık' : 'Aylık',
                ),
                trailing: Text(
                  '${CurrencyConverter.symbols[s.currency] ?? ''}'
                  '${_amountFormat.format(s.price)} ${s.currency}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _openDetail(s);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Takvim')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildMonthHeader(),
                  const SizedBox(height: 8),
                  _buildWeekdayHeader(),
                  _buildGrid(),
                  const SizedBox(height: 16),
                  if (_active.isNotEmpty)
                    Text(
                      'İşaretli günlere dokunarak o gün yenilenecek '
                      'abonelikleri görebilirsiniz.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildMonthHeader() {
    final now = DateTime.now();
    final isCurrentMonth =
        _visibleMonth.year == now.year && _visibleMonth.month == now.month;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          tooltip: 'Önceki ay',
          onPressed: () {
            setState(() {
              _visibleMonth =
                  DateTime(_visibleMonth.year, _visibleMonth.month - 1);
            });
          },
          icon: const Icon(Icons.chevron_left),
        ),
        Text(
          '${_trMonths[_visibleMonth.month - 1]} ${_visibleMonth.year}'
          '${isCurrentMonth ? ' (bu ay)' : ''}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        IconButton(
          tooltip: 'Sonraki ay',
          onPressed: () {
            setState(() {
              _visibleMonth =
                  DateTime(_visibleMonth.year, _visibleMonth.month + 1);
            });
          },
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _buildWeekdayHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final w in _trWeekdays)
          Expanded(
            child: Center(
              child: Text(
                w,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGrid() {
    final renewals = _renewalsByDay();
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0)
        .day;
    final leading = DateTime(_visibleMonth.year, _visibleMonth.month, 1)
            .weekday -
        1; // Pazartesi = 0
    final totalCells = leading + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: [
        for (var week = 0; week < rows; week++)
          Row(
            children: [
              for (var dow = 0; dow < 7; dow++)
                Expanded(
                  child: _buildDayCell(
                    dayIndex: week * 7 + dow,
                    day: week * 7 + dow - leading + 1,
                    renewals: renewals,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildDayCell({
    required int dayIndex,
    required int day,
    required Map<int, List<Subscription>> renewals,
  }) {
    final today = DateTime.now();
    final isCurrentMonthDay = day >= 1 && day <= _daysInVisibleMonth;
    if (!isCurrentMonthDay) {
      return const AspectRatio(aspectRatio: 1, child: SizedBox.shrink());
    }

    final isToday = isCurrentMonthDay &&
        _visibleMonth.year == today.year &&
        _visibleMonth.month == today.month &&
        day == today.day;
    final dayRenewals = renewals[day] ?? const <Subscription>[];
    final colorScheme = Theme.of(context).colorScheme;

    return AspectRatio(
      aspectRatio: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showDayRenewals(day),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: isToday
              ? BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                )
              : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                  color: isToday ? colorScheme.onPrimary : null,
                ),
              ),
              const SizedBox(height: 4),
              if (dayRenewals.isEmpty)
                const SizedBox(height: 6)
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: dayRenewals.take(3).map((s) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isToday
                            ? colorScheme.onPrimary
                            : CategoryCatalog.byKey(s.category).color,
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  int get _daysInVisibleMonth =>
      DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
}
