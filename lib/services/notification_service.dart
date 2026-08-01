import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../models/subscription.dart';

/// Yerel bildirimler + arka plan (background) servisi.
///
/// - `flutter_local_notifications`: cihaza bildirim gösterir.
/// - `flutter_background_service`: uygulama kapalıyken bile çalışan bir
///   arka plan isolate'i başlatır; periyodik olarak veritabanını kontrol
///   eder ve yenilenmesine 3 gün veya daha az kalmış abonelikler için
///   sabah ~09:00'da (ayarlanabilir) bildirim atar.
class NotificationService {
  static const int foregroundNotificationId = 999;
  static const int renewalNotificationBaseId = 1000;
  static const int trialNotificationBaseId = 2000;

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _renewalChannel =
      AndroidNotificationChannel(
    'renewal_alerts',
    'Yenileme Uyarıları',
    description: 'Yaklaşan abonelik yenileme bildirimleri',
    importance: Importance.high,
  );

  // ---------- Kurulum ----------

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _notifications.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Bildirime dokunulduğunda uygulama zaten açılır.
      },
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_renewalChannel);

    // Android 13+ için çalışma zamanı izni.
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> configureAndStartBackgroundService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        autoStartOnBoot: true,
        isForegroundMode: true,
        foregroundServiceNotificationId: foregroundNotificationId,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
        initialNotificationTitle: 'Abonelik Takibi',
        initialNotificationContent: 'Yenileme kontrolleri aktif',
        notificationChannelId: _renewalChannel.id,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    if (!await service.isRunning()) {
      await service.startService();
    }
  }

  static Future<void> stopBackgroundService() async {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stopService');
    }
  }

  // ---------- Arka plan servisi ----------

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) {
    WidgetsFlutterBinding.ensureInitialized();

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });
      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
      service.on('stopService').listen((event) {
        service.stopSelf();
      });
    }

    // Servis başlar başlamaz ilk kontrol (saat şartına takılır).
    performDailyCheck();

    // Her 30 dakikada bir veritabanını kontrol et.
    Timer.periodic(const Duration(minutes: 30), (timer) async {
      // Ayarlardan bildirimler kapatılmışsa servisi kendisi durdurur.
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('notifications_enabled') ?? true)) {
        if (service is AndroidServiceInstance) service.stopSelf();
        return;
      }

      await performDailyCheck();

      if (service is AndroidServiceInstance) {
        final now = DateTime.now();
        service.setForegroundNotificationInfo(
          title: 'Abonelik Takibi',
          content: 'Son kontrol: '
              '${now.hour}:${now.minute.toString().padLeft(2, '0')}',
        );
      }
    });
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    await performDailyCheck();
    return true;
  }

  // ---------- Günlük kontrol ----------

  /// Sabah [alertHour] (varsayılan 09:00) saatinden sonra günde yalnızca
  /// bir kez çalışır; yenilenmesine 3 gün veya daha az kalmış abonelikler
  /// ve bitmesine 3 gün veya daha az kalan deneme süreleri için bildirim
  /// gönderir.
  static Future<void> performDailyCheck() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('notifications_enabled') ?? true)) return;

    final now = DateTime.now();
    final alertHour = prefs.getInt('alert_hour') ?? 9;
    final todayKey =
        'last_daily_check_${now.year}-${now.month}-${now.day}';

    // Henüz saat gelmediyse veya bugün zaten kontrol yapıldıysa çık.
    if (now.hour < alertHour || (prefs.getBool(todayKey) ?? false)) return;
    await prefs.setBool(todayKey, true);

    final due = await AppDatabase.instance.getUpcomingRenewals(3);
    for (final subscription in due) {
      final lastNotified = subscription.lastNotifiedDate;
      final alreadyNotifiedToday = lastNotified != null &&
          lastNotified.year == now.year &&
          lastNotified.month == now.month &&
          lastNotified.day == now.day;
      if (alreadyNotifiedToday) continue;

      await showRenewalAlert(subscription);
      await AppDatabase.instance
          .updateLastNotifiedDate(subscription.id!, now);
    }

    await _checkTrialAlerts(now);
  }

  /// Bitmesine 3 gün veya daha az kalmış, aktif deneme süreleri için
  /// günde bir kez bildirim gönderir.
  static Future<void> _checkTrialAlerts(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final active = await AppDatabase.instance.getActiveSubscriptions();
    final dueTrials = active.where((s) {
      if (s.trialEndDate == null) return false;
      final days = s.daysUntilTrialEnd;
      return days >= 0 && days <= 3;
    });

    for (final subscription in dueTrials) {
      final key = 'trial_notified_${subscription.id!}_'
          '${now.year}-${now.month}-${now.day}';
      if (prefs.getBool(key) ?? false) continue;

      await showTrialEndAlert(subscription);
      await prefs.setBool(key, true);
    }
  }

  // ---------- Bildirim gösterimi ----------

  static Future<void> showTrialEndAlert(Subscription subscription) async {
    final days = subscription.daysUntilTrialEnd;
    final when = days == 0
        ? 'bugün'
        : days == 1
            ? 'yarın'
            : '$days gün sonra';

    await _notifications.show(
      trialNotificationBaseId + (subscription.id ?? 0),
      'Deneme Süresi Uyarısı',
      'Dikkat: ${subscription.name} deneme süresi $when sona eriyor! '
          'İptal etmezseniz ücretlendirilir.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'renewal_alerts',
          'Yenileme Uyarıları',
          channelDescription: 'Yaklaşan abonelik yenileme bildirimleri',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> showRenewalAlert(Subscription subscription) async {
    final symbol = CurrencyConverter.symbols[subscription.currency] ?? '';
    final days = subscription.daysUntilRenewal;
    final when = days == 0
        ? 'bugün'
        : days == 1
            ? 'yarın'
            : '$days gün sonra';

    await _notifications.show(
      renewalNotificationBaseId + (subscription.id ?? 0),
      'Yenileme Uyarısı',
      'Dikkat: ${subscription.name} yenilemesine $when kaldı! '
          '($symbol${subscription.price.toStringAsFixed(2)})',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'renewal_alerts',
          'Yenileme Uyarıları',
          channelDescription: 'Yaklaşan abonelik yenileme bildirimleri',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
