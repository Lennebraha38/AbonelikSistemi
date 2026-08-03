import 'package:home_widget/home_widget.dart';

import '../database/app_database.dart';
import '../models/subscription.dart';

/// Ana ekran widget'ı (Android App Widget) için köprü.
///
/// Yaklaşan yenilemeleri biçimlendirip widget'ın SharedPreferences'ine yazar
/// ve widget'ı günceller. Veri her abonelik değişikliğinde yeniden yazılır.
class WidgetService {
  /// Android'deki AppWidgetProvider sınıf adı.
  static const String _androidName = 'SubscriptionWidgetProvider';

  /// Widget'a dokunulunca uygulamayı açan adres (varsayılan ana ekran).
  static const String launchUri = 'subscriptionmanager://dashboard';

  /// Ana ekran widget'ını yaklaşan yenilemelerle günceller.
  /// Widget kurulmamışsa veya platform desteklemiyorsa sessizce atlar.
  static Future<void> updateUpcoming() async {
    try {
      final upcoming = await AppDatabase.instance.getUpcomingRenewals(14);
      final buffer = StringBuffer();
      if (upcoming.isEmpty) {
        buffer.write('Sonraki 14 günde yenileme yok.');
      } else {
        for (final s in upcoming.take(5)) {
          final symbol = CurrencyConverter.symbols[s.currency] ?? '';
          final when = s.daysUntilRenewal == 0
              ? 'Bugün'
              : s.daysUntilRenewal == 1
                  ? 'Yarın'
                  : '${s.daysUntilRenewal} gün';
          buffer.writeln('• ${s.name}: $when ($symbol${s.price.toStringAsFixed(0)})');
        }
        if (upcoming.length > 5) {
          buffer.write('+${upcoming.length - 5} daha');
        }
      }

      await HomeWidget.saveWidgetData<String>('widget_text', buffer.toString());
      await HomeWidget.updateWidget(
        name: _androidName,
        androidName: _androidName,
        iOSName: _androidName,
      );
    } catch (_) {
      // Widget güncellenemezse uygulama akışı bozulmasın.
    }
  }
}
