import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../models/subscription.dart';
import 'add_subscription_screen.dart';
import 'settings_screen.dart';

/// Ana ekran: aylık toplam gider + yaklaşan ödemeler.
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final currency = prefs.getString('display_currency') ?? 'TRY';

    final subscriptions =
        await AppDatabase.instance.getSubscriptions()
          ..sort((a, b) => a.nextRenewalDate.compareTo(b.nextRenewalDate));
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

  Future<void> _openAddScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddSubscriptionScreen()),
    );
    _loadData();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Abonelik Yöneticisi'),
        actions: [
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
                  const SizedBox(height: 28),
                  Text(
                    'Yaklaşan Ödemeler',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (_subscriptions.isEmpty)
                    _buildEmptyState()
                  else
                    ..._subscriptions.map(_buildSubscriptionTile),
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

  Widget _buildSubscriptionTile(Subscription s) {
    final symbol = CurrencyConverter.symbols[s.currency] ?? '';
    final days = s.daysUntilRenewal;

    final String label;
    final Color color;
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

    return Dismissible(
      key: ValueKey(s.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade400,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Aboneliği Sil'),
            content: Text('"${s.name}" aboneliği silinsin mi?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Vazgeç'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sil'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await AppDatabase.instance.deleteSubscription(s.id!);
        }
        return confirmed ?? false;
      },
      onDismissed: (_) => _loadData(),
      child: Card(
        child: ListTile(
          leading: const CircleAvatar(
            child: Icon(Icons.subscriptions_outlined),
          ),
          title: Text(
            s.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${DateFormat('dd.MM.yyyy').format(s.nextRenewalDate)}  •  '
            '$symbol${s.price.toStringAsFixed(2)} ${s.currency}',
          ),
          trailing: Chip(
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
            'Henüz abonelik yok.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Aşağıdaki butona basarak ilk aboneliğinizi ekleyin.',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
