import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/subscription.dart';
import '../services/export_service.dart';
import '../services/notification_service.dart';
import '../theme/theme_controller.dart';

/// Ayarlar: tema, para birimi, bildirimler ve veri dışa aktarma.
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

  Future<void> _exportCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ExportService.exportAndShare();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Dışa aktarma başarısız: $error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
                  'Veri Yedekleme',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Tüm abonelikleri CSV dosyası olarak indirin veya paylaşın.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.file_download_outlined),
                    title: const Text('CSV dışa aktar'),
                    subtitle: const Text(
                      'abonelikler.csv dosyası oluşturulur',
                    ),
                    trailing: _exporting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: _exportCsv,
                  ),
                ),
                const SizedBox(height: 28),
                Card(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.amber.shade900),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Android cihazlarda arka plan kontrolünün '
                            'kesintisiz çalışması için uygulamayı pil '
                            'optimizasyonundan muaf tutmanız önerilir.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade900,
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
