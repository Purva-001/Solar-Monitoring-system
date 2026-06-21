import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/alerts/threshold_alert_cubit.dart';
import '../features/dashboard/state/dashboard_cubit.dart';
import '../features/health_report/state/health_report_cubit.dart';
import '../features/maintenance/state/maintenance_comparison_cubit.dart';
import '../features/solar_history/state/solar_history_cubit.dart';
import 'home_shell.dart';
import 'theme/app_theme.dart';

class SolarDashboardApp extends StatelessWidget {
  const SolarDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => DashboardCubit()..load()),
        BlocProvider(create: (_) => ThresholdAlertCubit()),
        BlocProvider(create: (_) => HealthReportCubit()..load()),
        BlocProvider(create: (_) => MaintenanceComparisonCubit()..load()),
        BlocProvider(create: (_) => SolarHistoryCubit()..load()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'SolarMonitor Pro',
        theme: AppTheme.light(),
        home: const HomeShell(),
      ),
    );
  }
}
