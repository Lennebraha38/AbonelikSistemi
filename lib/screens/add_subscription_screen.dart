import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../models/subscription.dart';

/// Yeni abonelik ekleme formu.
class AddSubscriptionScreen extends StatefulWidget {
  const AddSubscriptionScreen({super.key});

  @override
  State<AddSubscriptionScreen> createState() => _AddSubscriptionScreenState();
}

class _AddSubscriptionScreenState extends State<AddSubscriptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();

  String _currency = 'TRY';
  String _billingCycle = 'monthly';
  DateTime _startDate = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPreferredCurrency();
  }

  Future<void> _loadPreferredCurrency() async {
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

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final price =
        double.parse(_priceController.text.trim().replaceAll(',', '.'));

    final subscription = Subscription(
      name: _nameController.text.trim(),
      price: price,
      currency: _currency,
      billingCycle: _billingCycle,
      startDate: _startDate,
    );

    setState(() => _saving = true);
    await AppDatabase.instance.insertSubscription(subscription);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = CurrencyConverter.symbols[_currency] ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Abonelik Ekle')),
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
                labelText: 'İlk Ödeme Tarihi',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(DateFormat('dd.MM.yyyy').format(_startDate)),
                trailing: const Icon(Icons.calendar_month_outlined),
                onTap: _pickStartDate,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Kaydet'),
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
