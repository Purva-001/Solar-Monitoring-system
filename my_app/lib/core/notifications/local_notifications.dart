import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../alerts/threshold_alert_state.dart';

class LocalNotifications {
  LocalNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const String _channelId = 'threshold_alerts';
  static const String _channelName = 'Threshold Alerts';
  static const String _channelDescription = 'Critical and warning alerts when sensor values cross thresholds.';

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(initSettings);

    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
      ),
    );

    if (!kDebugMode) return;
  }

  static Future<void> showThresholdAlert(ThresholdAlert alert) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: alert.severity == ThresholdSeverity.critical ? Importance.max : Importance.high,
      priority: alert.severity == ThresholdSeverity.critical ? Priority.high : Priority.defaultPriority,
      category: AndroidNotificationCategory.alarm,
    );

    final details = NotificationDetails(android: androidDetails);

    final id = alert.id.hashCode & 0x7fffffff;

    await _plugin.show(
      id,
      alert.title,
      alert.message,
      details,
      payload: alert.id,
    );
  }
}
