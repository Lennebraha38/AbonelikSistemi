import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/dashboard_screen.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Yerel bildirimlerin kurulumu.
  await NotificationService.init();

  // Bildirimler açıksa arka plan servisini başlat
  // (uygulama kapalıyken bile günlük kontrol yapılır).
  final prefs = await SharedPreferences.getInstance();
  final notificationsEnabled =
      prefs.getBool('notifications_enabled') ?? true;
  if (notificationsEnabled) {
    await NotificationService.configureAndStartBackgroundService();
  }

  runApp(const SubscriptionManagerApp());
}

class SubscriptionManagerApp extends StatelessWidget {
  const SubscriptionManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Abonelik Yöneticisi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3949AB),
        brightness: Brightness.light,
      ),
      home: const DashboardScreen(),
    );
  }
}
