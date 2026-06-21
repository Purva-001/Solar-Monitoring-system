import 'package:flutter/material.dart';

import 'app/solar_dashboard_app.dart';
import 'core/notifications/local_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalNotifications.init();
  runApp(const SolarDashboardApp());
}
