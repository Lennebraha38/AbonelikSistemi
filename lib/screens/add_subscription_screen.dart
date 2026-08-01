import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../models/categories.dart';
import '../models/subscription.dart';

/// Yeni abonelik ekleme / mevcut aboneliği düzenleme formu.
class AddSubscriptionScreen extends StatefulWidget {
  /// Doluysa bu aboneliğin değerleriyle form doldurulur ve kayıt güncellenir;
  /// boşsa yeni abonelik eklenir.
  final Subscription? subscription;

  const AddSubscriptionScreen({super.key, this.subscription});

  @override
  State<AddSubscriptionScreen> createState() => _AddSubscriptionScreenState();
}

class _AddSubscriptionScreenState extends State<AddSubscriptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();

  late String _currency;
  late String _billingCycle;
  late DateTime _startDate;
  late String _category;
  late bool _hasTrial;
  late DateTime _trialEndDate;
  late int _reminderDays;
  bool _saving = false;

  bool get _isEditing => widget.subscription != null;

  @override
  void initState() {
    super.initState();
    _prefill();
    _loadPreferredCurrency();
  }

  void _prefill() {
    final s = widget.subscription;
    if (s == null) {
      _currency = 'TRY';
      _billingCycle = 'monthly';
      _startDate = DateTime.now();
      _category = 'other';
      _hasTrial = false;
      _trialEndDate = DateTime.now().add(const Duration(days: 7));
      _reminderDays = Subscription.defaultReminderDays;
      return;
    }
    _nameController.text = s.name;
    _priceController.text = s.price.toString();
    _currency = s.currency;
    _billingCycle = s.billingCycle;
    _startDate = s.startDate;
    _category = s.category;
    _hasTrial = s.trialEndDate != null;
    _trialEndDate = s.trialEndDate ?? DateTime.now().add(const Duration(days: 7));
    _reminderDays = s.reminderDays;
  }

  Future<void> _loadPreferredCurrency() async {
    if (_isEditing) return;
    final prefs = await SharedPreferences.getInstance();
    final preferred = prefs.getString('display_currency');
    if (preferred != null && mounted) {
      setState(() => _currency = preferred);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(
    DateTime current,
    void Function(DateTime) onPicked,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final price =
        double.parse(_priceController.text.trim().replaceAll(',', '.'));

    final existing = widget.subscription;
    final subscription = Subscription(
      id: existing?.id,
      name: _nameController.text.trim(),
      price: price,
      currency: _currency,
      billingCycle: _billingCycle,
      startDate: _startDate,
      category: _category,
      trialEndDate: _hasTrial ? _trialEndDate : null,
      reminderDays: _reminderDays,
      status: existing?.status ?? Subscription.active,
      lastNotifiedDate: existing?.lastNotifiedDate,
    );

    setState(() => _saving = true);
    if (_isEditing) {
      await AppDatabase.instance.updateSubscription(subscription);
    } else {
      await AppDatabase.instance.insertSubscription(subscription);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = CurrencyConverter.symbols[_currency] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Aboneliği Düzenle' : 'Abonelik Ekle'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Uygulama Adı',
                hintText: 'Netflix, Spotify, YouTube Premium...',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Uygulama adı gerekli';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Fiyat',
                prefixText: '$currencySymbol ',
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Fiyat gerekli';
                }
                final parsed =
                    double.tryParse(value.trim().replaceAll(',', '.'));
                if (parsed == null || parsed <= 0) {
                  return 'Geçerli bir fiyat girin';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Para Birimi',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: DropdownButton<String>(
                value: _currency,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: CurrencyConverter.supportedCurrencies.map((c) {
                  return DropdownMenuItem(
                    value: c,
                    child: Text('${CurrencyConverter.symbols[c]} $c'),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _currency = value);
                },
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fatura Döngüsü',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: DropdownButton<String>(
                value: _billingCycle,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                    value: 'monthly',
                    child: Text('Aylık'),
                  ),
                  DropdownMenuItem(
                    value: 'yearly',
                    child: Text('Yıllık'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _billingCycle = value);
                },
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Kategori',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: DropdownButton<String>(
                value: _category,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: CategoryCatalog.all.map((c) {
                  return DropdownMenuItem(
                    value: c.key,
                    child: Row(
                      children: [
                        Icon(c.icon, color: c.color, size: 20),
                        const SizedBox(width: 8),
                        Text(c.label),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'İlk Ödeme Tarihi',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(DateFormat('dd.MM.yyyy').format(_startDate)),
                trailing: const Icon(Icons.calendar_month_outlined),
                onTap: () => _pickDate(_startDate, (d) {
                  setState(() => _startDate = d);
                }),
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Hatırlatma (yenilemeden kaç gün önce)',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: DropdownButton<int>(
                value: _reminderDays,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 gün önce')),
                  DropdownMenuItem(value: 3, child: Text('3 gün önce')),
                  DropdownMenuItem(value: 7, child: Text('7 gün önce')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _reminderDays = value);
                },
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Deneme süresi var'),
              subtitle: Text(
                'Deneme bitince ücretliye geçmeden önce uyarır',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              value: _hasTrial,
              onChanged: (value) => setState(() => _hasTrial = value),
            ),
            if (_hasTrial) ...[
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Deneme Bitiş Tarihi',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    DateFormat('dd.MM.yyyy').format(_trialEndDate),
                  ),
                  trailing: const Icon(Icons.timelapse_outlined),
                  onTap: () => _pickDate(_trialEndDate, (d) {
                    setState(() => _trialEndDate = d);
                  }),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: Icon(
                _isEditing ? Icons.update : Icons.save_outlined,
              ),
              label: Text(_isEditing ? 'Güncelle' : 'Kaydet'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
