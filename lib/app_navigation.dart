import 'dart:async';

import 'package:flutter/material.dart';

import 'database/app_database.dart';
import 'screens/subscription_detail_screen.dart';

/// Uygulama genelinde kullanılan navigator anahtarı. Bildirimlere
/// dokunulduğunda (arka plandan veya kapalı durumdan) ekran üzerinden
/// abonelik detayına yönlendirme yapmak için kullanılır.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

int? _pendingSubscriptionId;

/// Bildirim payload'ından gelen abonelik kimliğini açar.
/// Uygulama henüz hazır değilse (soğuk başlangıç) bir süre bekleyip
/// navigator hazır olduğunda yönlendirir.
void openSubscriptionFromNotification(int subscriptionId) {
  _pendingSubscriptionId = subscriptionId;
  _tryOpen();
}

void _tryOpen() {
  if (_pendingSubscriptionId == null) return;
  if (appNavigatorKey.currentState == null) {
    Timer(const Duration(milliseconds: 250), _tryOpen);
    return;
  }
  final id = _pendingSubscriptionId!;
  _pendingSubscriptionId = null;
  _openDetail(id);
}

Future<void> _openDetail(int id) async {
  final matches = (await AppDatabase.instance.getSubscriptions())
      .where((s) => s.id == id)
      .toList();
  final navigator = appNavigatorKey.currentState;
  if (matches.isEmpty || navigator == null) return;
  navigator.push(
    MaterialPageRoute(
      builder: (_) => SubscriptionDetailScreen(subscription: matches.first),
    ),
  );
}
