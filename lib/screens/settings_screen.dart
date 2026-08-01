import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/subscription.dart';
import '../services/export_service.dart';
import '../services/notification_service.dart';
import '../theme/theme_controller.dart';

/// Ayarlar: tema, para birimi, bütçe, bildirimler ve veri yönetimi.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _currency = 'TRY';
  bool _notificationsEnabled = true;
  int _alertHour = 9;
  ThemeMode _themeMode = ThemeMode.system;
  double _monthlyBudget = 0;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _currency = prefs.getString('display_currency') ?? 'TRY';
      _notificationsEnabled =
          prefs.getBool('notifications_enabled') ?? true;
      _alertHour = prefs.getInt('alert_hour') ?? 9;
      _themeMode = ThemeController.instance.value;
      _monthlyBudget = prefs.getDouble('monthly_budget') ?? 0;
      _loading = false;
    });
  }

  Future<void> _setCurrency(String currency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('display_currency', currency);
    if (mounted) setState(() => _currency = currency);
  }

  Future<void> _setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', enabled);
    if (mounted) setState(() => _notificationsEnabled = enabled);

    try {
      if (enabled) {
        await NotificationService.configureAndStartBackgroundService();
      } else {
        await NotificationService.stopBackgroundService();
      }
    } catch (_) {
      // Servis yönetimi başarısız olursa uygulama akışı bozulmasın.
    }
  }

  Future<void> _setAlertHour(int hour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('alert_hour', hour);
    if (mounted) setState(() => _alertHour = hour);
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    await ThemeController.instance.setMode(mode);
    if (mounted) setState(() => _themeMode = mode);
  }

  Future<void> _runExport(Future<void> Function() action) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Dışa aktarma başarısız: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (_exporting) return;
    final messenger = ScaffoldMessenger.of(context);
    BackupData? data;
    setState(() => _exporting = true);
    try {
      data = await ExportService.pickBackupFile();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Dosya okunamadı: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
    if (data == null || !mounted) return;

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yedeği Geri Yükle'),
        content: Text(
          'Yedekte ${data!.subscriptions.length} abonelik ve '
          '${data.payments.length} ödeme var.\n\n'
          'Değiştir: mevcut tüm veriler silinir, yedektekiler yüklenir.\n'
          'Birleştir: mevcut veriler korunur, yedektekiler eklenir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('merge'),
            child: const Text('Birleştir'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('replace'),
            child: const Text('Değiştir'),
          ),
        ],
      ),
    );
    if (choice == null) return;

    setState(() => _exporting = true);
    try {
      await ExportService.restoreBackupData(data, replace: choice == 'replace');
      HapticFeedback.mediumImpact();
      messenger.showSnackBar(
        const SnackBar(content: Text('Yedek başarıyla geri yüklendi.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Geri yükleme başarısız: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _setBudget() async {
    final controller = TextEditingController(
      text: _monthlyBudget == 0 ? '' : _monthlyBudget.toStringAsFixed(0),
    );
    final formKey = GlobalKey<FormState>();
    final symbol = CurrencyConverter.symbols[_currency] ?? '';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aylık Bütçe'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Aylık bütçe ($_currency)',
              hintText: 'örn. 1000',
              prefixText: '$symbol ',
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return null;
              final parsed =
                  double.tryParse(value.trim().replaceAll(',', '.'));
              if (parsed == null || parsed < 0) {
                return 'Geçerli bir tutar girin';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(context).pop(true);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved != true) return;

    final value = controller.text.trim();
    final parsed = value.isEmpty ? 0.0 : double.parse(value.replaceAll(',', '.'));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('monthly_budget', parsed);
    if (mounted) setState(() => _monthlyBudget = parsed);
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Sistem (cihaz ayarı)';
      case ThemeMode.light:
        return 'Açık tema';
      case ThemeMode.dark:
        return 'Koyu tema';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Görünüm',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Karanlık mod tüm ekranlara uygulanır.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: ThemeMode.values.map((mode) {
                      final selected = _themeMode == mode;
                      return ListTile(
                        leading: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                        title: Text(_themeModeLabel(mode)),
                        trailing: selected
                            ? Icon(
                                Icons.check,
                                color:
                                    Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onTap: () => _setThemeMode(mode),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Görüntüleme Para Birimi',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Aylık toplam gider bu birim üzerinden gösterilir.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: CurrencyConverter.supportedCurrencies.map((c) {
                      final symbol = CurrencyConverter.symbols[c] ?? '';
                      final selected = _currency == c;
                      return ListTile(
                        leading: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                        title: Text('$symbol $c'),
                        trailing: selected
                            ? Icon(
                                Icons.check,
                                color:
                                    Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onTap: () => _setCurrency(c),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Bildirimler',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Yenilenmesine 3 gün veya daha az kalan abonelikler '
                  'için günde bir kez bildirim gönderilir.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Yenileme bildirimleri'),
                        subtitle: const Text('Arka plan servisini etkinleştir'),
                        value: _notificationsEnabled,
                        onChanged: _setNotificationsEnabled,
                      ),
                      if (_notificationsEnabled)
                        ListTile(
                          title: const Text('Bildirim saati'),
                          subtitle: const Text(
                            'Her gün bu saatten sonra ilk kontrol yapılır.',
                          ),
                          trailing: DropdownButton<int>(
                            value: _alertHour,
                            underline: const SizedBox.shrink(),
                            items: const [
                              DropdownMenuItem(
                                value: 8,
                                child: Text('08:00'),
                              ),
                              DropdownMenuItem(
                                value: 9,
                                child: Text('09:00'),
                              ),
                              DropdownMenuItem(
                                value: 10,
                                child: Text('10:00'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) _setAlertHour(value);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Bütçe',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Aylık bütçe aşılırsa ana ekranda uyarı gösterilir.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.savings_outlined),
                    title: const Text('Aylık bütçe'),
                    subtitle: Text(
                      _monthlyBudget > 0
                          ? '${CurrencyConverter.symbols[_currency] ?? ''}'
                              '${_monthlyBudget.toStringAsFixed(0)} $_currency'
                          : 'Bütçe tanımlanmadı',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _setBudget,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Veri Yönetimi',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Yedekleme ve takvime aktarma işlemleri.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.backup_outlined),
                        title: const Text('Yedekle (JSON)'),
                        subtitle: const Text(
                          'Tüm verileri paylaşın veya indirin',
                        ),
                        trailing: _exporting
                            ? const _MiniLoader()
                            : const Icon(Icons.chevron_right),
                        onTap: () =>
                            _runExport(ExportService.exportBackupAndShare),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.restore_outlined),
                        title: const Text('Yedeği geri yükle'),
                        subtitle: const Text('JSON dosyasından içe aktarın'),
                        trailing: _exporting
                            ? const _MiniLoader()
                            : const Icon(Icons.chevron_right),
                        onTap: _restoreBackup,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.calendar_month_outlined),
                        title: const Text('Takvime aktar (.ics)'),
                        subtitle: const Text(
                          'Yenilemeleri Google/Apple takvimine ekleyin',
                        ),
                        trailing: _exporting
                            ? const _MiniLoader()
                            : const Icon(Icons.chevron_right),
                        onTap: () => _runExport(ExportService.exportIcsAndShare),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.file_download_outlined),
                        title: const Text('CSV dışa aktar'),
                        subtitle: const Text('abonelikler.csv oluşturulur'),
                        trailing: _exporting
                            ? const _MiniLoader()
                            : const Icon(Icons.chevron_right),
                        onTap: () => _runExport(ExportService.exportCsvAndShare),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Android cihazlarda arka plan kontrolünün '
                            'kesintisiz çalışması için uygulamayı pil '
                            'optimizasyonundan muaf tutmanız önerilir.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MiniLoader extends StatelessWidget {
  const _MiniLoader();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
