import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../database/app_database.dart';
import '../models/categories.dart';
import '../models/payment.dart';
import '../models/subscription.dart';
import 'add_subscription_screen.dart';

/// Abonelik detayı: bilgiler, işlemler (düzenle/iptal/sil) ve ödeme geçmişi.
class SubscriptionDetailScreen extends StatefulWidget {
  final Subscription subscription;

  const SubscriptionDetailScreen({super.key, required this.subscription});

  @override
  State<SubscriptionDetailScreen> createState() =>
      _SubscriptionDetailScreenState();
}

class _SubscriptionDetailScreenState extends State<SubscriptionDetailScreen> {
  final NumberFormat _amountFormat =
      NumberFormat.currency(symbol: '', decimalDigits: 2);

  Subscription? _subscription;
  List<Payment> _payments = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await AppDatabase.instance.getSubscriptions();
    final sub = all.firstWhere(
      (s) => s.id == widget.subscription.id,
      orElse: () => widget.subscription,
    );
    final payments = sub.id == null
        ? <Payment>[]
        : await AppDatabase.instance
            .getPaymentsForSubscription(sub.id!);

    if (!mounted) return;
    setState(() {
      _subscription = sub;
      _payments = payments;
      _loading = false;
    });
  }

  double get _totalPaid {
    final sum = _payments.fold<double>(0, (a, p) => a + p.amount);
    return sum;
  }

  Future<bool> _confirm(
    String title,
    String content,
    String confirmLabel,
  ) async {
    final ok = await showDialog<bool>(
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
    return ok ?? false;
  }

  Future<void> _edit() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddSubscriptionScreen(subscription: _subscription!),
      ),
    );
    await _load();
  }

  Future<void> _cancelOrReactivate() async {
    final s = _subscription!;
    if (!s.isCancelled) {
      final ok = await _confirm(
        'Aboneliği İptal Et',
        '"${s.name}" aboneliği iptal edilsin mi? Yenileme uyarıları '
        'artık gönderilmez.',
        'İptal Et',
      );
      if (!ok) return;
      await AppDatabase.instance.cancelSubscription(s.id!);
    } else {
      await AppDatabase.instance.reactivateSubscription(s.id!);
    }
    HapticFeedback.mediumImpact();
    await _load();
  }

  Future<void> _delete() async {
    final s = _subscription!;
    final ok = await _confirm(
      'Aboneliği Sil',
      '"${s.name}" aboneliği ve tüm ödeme kayıtları silinsin mi?',
      'Sil',
    );
    if (!ok) return;
    await AppDatabase.instance.deleteSubscription(s.id!);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _addPayment() async {
    final s = _subscription!;
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController(
      text: s.price.toStringAsFixed(2),
    );
    final noteController = TextEditingController();
    String currency = s.currency;
    DateTime paidAt = DateTime.now();
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ödeme Ekle'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Tutar',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final parsed = double.tryParse(
                        (value ?? '').trim().replaceAll(',', '.'),
                      );
                      if (parsed == null || parsed <= 0) {
                        return 'Geçerli bir tutar girin';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: currency,
                    decoration: const InputDecoration(
                      labelText: 'Para Birimi',
                      border: OutlineInputBorder(),
                    ),
                    items: CurrencyConverter.supportedCurrencies.map((c) {
                      return DropdownMenuItem(
                        value: c,
                        child: Text('${CurrencyConverter.symbols[c]} $c'),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => currency = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Not (isteğe bağlı)',
                      hintText: 'Otomatik ödeme, indirimle alındı...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tarih'),
                    subtitle: Text(DateFormat('dd.MM.yyyy').format(paidAt)),
                    trailing: const Icon(Icons.calendar_month_outlined),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: paidAt,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setDialogState(() => paidAt = picked);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => saving = true);
                      final amount = double.parse(
                        amountController.text.trim().replaceAll(',', '.'),
                      );
                      await AppDatabase.instance.insertPayment(
                        Payment(
                          subscriptionId: s.id!,
                          amount: amount,
                          currency: currency,
                          paidAt: paidAt,
                          note: noteController.text.trim().isEmpty
                              ? null
                              : noteController.text.trim(),
                        ),
                      );
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop(true);
                    },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    amountController.dispose();
    noteController.dispose();

    if (saved == true) await _load();
  }

  Future<void> _removePayment(Payment payment) async {
    final ok = await _confirm(
      'Ödeme Kaydını Sil',
      '${DateFormat('dd.MM.yyyy').format(payment.paidAt)} tarihli '
      '${payment.amount.toStringAsFixed(2)} ${payment.currency} kaydı '
      'silinsin mi?',
      'Sil',
    );
    if (!ok) return;
    await AppDatabase.instance.deletePayment(payment.id!);
    HapticFeedback.mediumImpact();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _subscription;
    return Scaffold(
      appBar: AppBar(title: Text(s?.name ?? 'Abonelik')),
      body: _loading || s == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(s),
                  const SizedBox(height: 20),
                  _buildInfoCard(s),
                  const SizedBox(height: 20),
                  _buildActions(s),
                  const SizedBox(height: 24),
                  _buildPayments(s),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(Subscription s) {
    final category = CategoryCatalog.byKey(s.category);
    final symbol = CurrencyConverter.symbols[s.currency] ?? '';

    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: category.color.withValues(alpha: 0.15),
          child: Icon(category.icon, size: 32, color: category.color),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                category.label,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$symbol${s.price.toStringAsFixed(2)} ${s.currency}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              s.billingCycle == 'yearly' ? 'yıllık' : 'aylık',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoCard(Subscription s) {
    final colorScheme = Theme.of(context).colorScheme;
    final days = s.daysUntilRenewal;
    final renewalLabel = s.isCancelled
        ? 'İptal edildi'
        : days == 0
            ? 'Bugün'
            : days == 1
                ? 'Yarın'
                : '$days gün sonra';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _infoRow(
              'Sonraki yenileme',
              s.isCancelled
                  ? '—'
                  : '${DateFormat('dd.MM.yyyy').format(s.nextRenewalDate)} '
                      '($renewalLabel)',
            ),
            _infoRow('Başlangıç tarihi',
                DateFormat('dd.MM.yyyy').format(s.startDate)),
            _infoRow('Fatura döngüsü',
                s.billingCycle == 'yearly' ? 'Yıllık' : 'Aylık'),
            if (s.trialEndDate != null)
              _infoRow(
                'Deneme bitişi',
                s.isOnTrial
                    ? '${DateFormat('dd.MM.yyyy').format(s.trialEndDate!)} '
                        '(${s.daysUntilTrialEnd} gün kaldı)'
                    : DateFormat('dd.MM.yyyy').format(s.trialEndDate!),
              ),
            _infoRow(
              'Hatırlatma',
              '${s.reminderDays} gün önce',
            ),
            _infoRow(
              'Durum',
              s.isCancelled ? 'İptal edildi' : 'Aktif',
              valueColor: s.isCancelled
                  ? colorScheme.error
                  : colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: valueColor ?? colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(Subscription s) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Düzenle'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: s.isCancelled
              ? FilledButton.tonalIcon(
                  onPressed: _cancelOrReactivate,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Geri Al'),
                )
              : OutlinedButton.icon(
                  onPressed: _cancelOrReactivate,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('İptal Et'),
                ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Sil',
          onPressed: _delete,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  Widget _buildPayments(Subscription s) {
    final symbol = CurrencyConverter.symbols[s.currency] ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ödeme Geçmişi',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addPayment,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ödeme Ekle'),
                ),
              ],
            ),
            if (_payments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Henüz ödeme kaydı yok. İlk ödemeyi ekleyerek geçmişi takip edin.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              for (final p in _payments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.payments_outlined, size: 20),
                  title: Text(
                    '${DateFormat('dd.MM.yyyy').format(p.paidAt)}'
                    '${p.note == null ? '' : '  •  ${p.note}'}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${CurrencyConverter.symbols[p.currency] ?? ''}'
                        '${p.amount.toStringAsFixed(2)} ${p.currency}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        color: Theme.of(context).colorScheme.outline,
                        tooltip: 'Kaydı sil',
                        onPressed: () => _removePayment(p),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Toplam ödeme',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '$symbol${_amountFormat.format(_totalPaid)} ${s.currency}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
