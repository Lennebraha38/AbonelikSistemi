import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../models/categories.dart';
import '../models/subscription.dart';
import 'add_subscription_screen.dart';
import 'insights_screen.dart';
import 'settings_screen.dart';

/// Ana ekran: aylık toplam gider + yaklaşan ödemeler + kategori filtreleri.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final NumberFormat _amountFormat =
      NumberFormat.currency(symbol: '', decimalDigits: 2);

  List<Subscription> _subscriptions = const [];
  Map<String, double> _totalsByCurrency = const {};
  double _monthlyTotal = 0;
  String _displayCurrency = 'TRY';
  String? _categoryFilter;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final currency = prefs.getString('display_currency') ?? 'TRY';

    final subscriptions = await AppDatabase.instance.getSubscriptions()
      ..sort((a, b) {
        if (a.isCancelled != b.isCancelled) return a.isCancelled ? 1 : -1;
        return a.nextRenewalDate.compareTo(b.nextRenewalDate);
      });
    final totals =
        await AppDatabase.instance.getMonthlyTotalByCurrency();
    final total =
        await AppDatabase.instance.getMonthlyTotal(displayCurrency: currency);

    if (!mounted) return;
    setState(() {
      _displayCurrency = currency;
      _subscriptions = subscriptions;
      _totalsByCurrency = totals;
      _monthlyTotal = total;
      _loading = false;
    });
  }

  List<Subscription> get _filtered {
    if (_categoryFilter == null) return _subscriptions;
    return _subscriptions
        .where((s) => s.category == _categoryFilter)
        .toList();
  }

  Future<void> _openAddScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddSubscriptionScreen()),
    );
    _loadData();
  }

  Future<void> _editSubscription(Subscription s) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddSubscriptionScreen(subscription: s),
      ),
    );
    _loadData();
  }

  Future<void> _openInsights() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InsightsScreen()),
    );
    _loadData();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    _loadData();
  }

  Future<bool> _confirmDialog(
    String title,
    String content,
    String confirmLabel,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _cancelSubscription(Subscription s) async {
    final confirmed = await _confirmDialog(
      'Aboneliği İptal Et',
      '"${s.name}" aboneliği iptal edilsin mi? Yenileme uyarıları artık gönderilmez.',
      'İptal Et',
    );
    if (confirmed) {
      await AppDatabase.instance.cancelSubscription(s.id!);
      await _loadData();
    }
  }

  Future<void> _reactivateSubscription(Subscription s) async {
    await AppDatabase.instance.reactivateSubscription(s.id!);
    await _loadData();
  }

  Future<void> _deleteSubscription(Subscription s) async {
    final confirmed = await _confirmDialog(
      'Aboneliği Sil',
      '"${s.name}" aboneliği silinsin mi?',
      'Sil',
    );
    if (confirmed) {
      await AppDatabase.instance.deleteSubscription(s.id!);
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Abonelik Yöneticisi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: 'İstatistikler',
            onPressed: _openInsights,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ayarlar',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildTotalCard(),
                  const SizedBox(height: 20),
                  _buildFilterChips(),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Abonelikler',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (_categoryFilter != null)
                        TextButton(
                          onPressed: () {
                            setState(() => _categoryFilter = null);
                          },
                          child: const Text('Filtreyi Kaldır'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_filtered.isEmpty)
                    _buildEmptyState()
                  else
                    ..._filtered.map(_buildSubscriptionTile),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddScreen,
        icon: const Icon(Icons.add),
        label: const Text('Abonelik Ekle'),
      ),
    );
  }

  Widget _buildTotalCard() {
    final symbol = CurrencyConverter.symbols[_displayCurrency] ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3949AB), Color(0xFF1E88E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aylık Toplam Gider',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$symbol${_amountFormat.format(_monthlyTotal)} $_displayCurrency',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 44,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_totalsByCurrency.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _totalsByCurrency.entries.map((entry) {
                final sym = CurrencyConverter.symbols[entry.key] ?? '';
                return Chip(
                  backgroundColor: Colors.white24,
                  label: Text(
                    '$sym${_amountFormat.format(entry.value)} ${entry.key}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Tümü'),
              selected: _categoryFilter == null,
              onSelected: (_) => setState(() => _categoryFilter = null),
            ),
          ),
          for (final category in CategoryCatalog.all)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(
                  category.icon,
                  size: 18,
                  color: category.color,
                ),
                label: Text(category.label),
                selected: _categoryFilter == category.key,
                onSelected: (_) {
                  setState(() {
                    _categoryFilter =
                        _categoryFilter == category.key ? null : category.key;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionTile(Subscription s) {
    final symbol = CurrencyConverter.symbols[s.currency] ?? '';
    final isCancelled = s.isCancelled;
    final category = CategoryCatalog.byKey(s.category);
    final isOnTrial = s.isOnTrial;

    final String label;
    final Color color;
    if (isCancelled) {
      label = 'İptal Edildi';
      color = Colors.grey.shade600;
    } else if (isOnTrial) {
      label = 'Deneme';
      color = Colors.teal.shade700;
    } else {
      final days = s.daysUntilRenewal;
      if (days == 0) {
        label = 'Bugün';
        color = Colors.red.shade700;
      } else if (days == 1) {
        label = 'Yarın';
        color = Colors.orange.shade700;
      } else {
        label = '$days gün sonra';
        color = Colors.blueGrey;
      }
    }

    final String subtitle;
    if (isOnTrial) {
      subtitle = 'Deneme ${DateFormat('dd.MM').format(s.trialEndDate!)} bitiyor'
          '  •  $symbol${s.price.toStringAsFixed(2)} ${s.currency}';
    } else {
      subtitle =
          '${DateFormat('dd.MM.yyyy').format(s.nextRenewalDate)}  •  '
          '$symbol${s.price.toStringAsFixed(2)} ${s.currency}';
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: category.color.withValues(alpha: 0.15),
          child: Icon(category.icon, color: category.color),
        ),
        title: Text(
          s.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: isCancelled ? TextDecoration.lineThrough : null,
            color: isCancelled ? Colors.grey.shade600 : null,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: isCancelled
              ? TextStyle(color: Colors.grey.shade500)
              : null,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(
              label: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: color.withValues(alpha: 0.1),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            ),
            PopupMenuButton<String>(
              tooltip: 'İşlemler',
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    _editSubscription(s);
                    break;
                  case 'cancel':
                    _cancelSubscription(s);
                    break;
                  case 'reactivate':
                    _reactivateSubscription(s);
                    break;
                  case 'delete':
                    _deleteSubscription(s);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Düzenle'),
                ),
                if (!isCancelled)
                  const PopupMenuItem(
                    value: 'cancel',
                    child: Text('İptal Et'),
                  ),
                if (isCancelled)
                  const PopupMenuItem(
                    value: 'reactivate',
                    child: Text('İptali Geri Al'),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Sil'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.subscriptions_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            _subscriptions.isEmpty
                ? 'Henüz abonelik yok.'
                : 'Bu kategoride abonelik yok.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
          Text(
            _subscriptions.isEmpty
                ? 'Aşağıdaki butona basarak ilk aboneliğinizi ekleyin.'
                : 'Farklı bir kategori seçebilirsiniz.',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
