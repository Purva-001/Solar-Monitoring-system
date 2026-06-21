import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/alerts/threshold_alert_cubit.dart';
import '../core/alerts/threshold_alert_state.dart';
import '../core/notifications/local_notifications.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/dashboard/state/dashboard_cubit.dart';
import '../features/dashboard/state/dashboard_state.dart';
import '../features/maintenance/presentation/maintenance_comparison_page.dart';
import '../features/maintenance/presentation/maintenance_page.dart';
import '../features/qr_scan/presentation/qr_scan_page.dart';
import '../features/panel_snapshot/presentation/genai_analysis_page.dart';
import '../features/solar_history/presentation/solar_history_page.dart';

class HomeShellCubit extends Cubit<int> {
  HomeShellCubit() : super(0);

  void setIndex(int i) => emit(i);
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _navItems = <({int index, IconData icon, String label})>[
    (index: 0, icon: Icons.dashboard_outlined, label: 'Dashboard'),
    (index: 1, icon: Icons.qr_code_scanner, label: 'QR Scan'),
    (index: 2, icon: Icons.auto_awesome_outlined, label: 'GenAI analysis'),
    (index: 3, icon: Icons.timeline_outlined, label: 'Solar History'),
    (index: 4, icon: Icons.compare_outlined, label: 'Maintenance Comparison'),
    (index: 5, icon: Icons.build_circle_outlined, label: 'Maintenance'),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeShellCubit(),
      child: MultiBlocListener(
        listeners: [
          BlocListener<DashboardCubit, DashboardState>(
            listenWhen: (prev, next) => next is DashboardLoaded,
            listener: (context, state) {
              if (state is! DashboardLoaded) return;
              context.read<ThresholdAlertCubit>().onReadings(state.readings);
            },
          ),
          BlocListener<ThresholdAlertCubit, ThresholdAlertState>(
            listenWhen: (prev, next) => next is ThresholdAlertEmitted,
            listener: (context, state) {
              if (state is! ThresholdAlertEmitted) return;
              final alert = state.alert;

              LocalNotifications.showThresholdAlert(alert);

              final (bg, fg) = switch (alert.severity) {
                ThresholdSeverity.critical => (Colors.red.shade700, Colors.white),
                ThresholdSeverity.warning => (Colors.orange.shade700, Colors.white),
                ThresholdSeverity.info => (Colors.blueGrey.shade800, Colors.white),
              };

              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    backgroundColor: bg,
                    content: Text('${alert.title}: ${alert.message}', style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
                    duration: const Duration(seconds: 4),
                  ),
                );
            },
          ),
        ],
        child: BlocBuilder<HomeShellCubit, int>(
          builder: (context, index) {
            final maxIndex = _navItems.fold<int>(0, (acc, e) => e.index > acc ? e.index : acc);
            final safeIndex = (index >= 0 && index <= maxIndex) ? index : 0;
            final title = _navItems.firstWhere((e) => e.index == safeIndex, orElse: () => _navItems[0]).label;

            final pagesByIndex = <int, Widget>{
              0: const DashboardPage(),
              1: const QrScanPage(),
              2: const GenaiAnalysisPage(panelId: null),
              3: const SolarHistoryPage(),
              4: const MaintenanceComparisonPage(),
              5: const MaintenancePage(),
            };

            final pages = List<Widget>.generate(
              maxIndex + 1,
              (i) => pagesByIndex[i] ?? const SizedBox.shrink(),
            );
            final width = MediaQuery.sizeOf(context).width;
            final isDesktop = width >= 980;

            if (!isDesktop) {
              return Scaffold(
                appBar: AppBar(
                  title: Text(title),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: CircleAvatar(
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: const Text('A', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                      ),
                    )
                  ],
                ),
                drawer: Drawer(
                  child: SafeArea(
                    child: _Sidebar(
                      safeIndex: safeIndex,
                      onSelect: (i) {
                        Navigator.of(context).pop();
                        context.read<HomeShellCubit>().setIndex(i);
                      },
                    ),
                  ),
                ),
                body: IndexedStack(index: safeIndex, children: pages),
              );
            }

            return Scaffold(
              body: Row(
                children: [
                  Container(
                    width: 236,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: SafeArea(
                      child: _Sidebar(
                        safeIndex: safeIndex,
                        onSelect: (i) => context.read<HomeShellCubit>().setIndex(i),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          height: 58,
                          decoration: const BoxDecoration(
                            color: Color(0xFF0EA5E9),
                            border: Border(bottom: BorderSide(color: Color(0xFF0284C7))),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              const Icon(Icons.bolt, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              const Text('SolarMonitor Pro', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Container(
                                  height: 34,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.search, size: 16, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text('Search metrics or panels...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Icon(Icons.notifications_none, color: Colors.white),
                              const SizedBox(width: 14),
                              const Text('Digital Twin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                              const SizedBox(width: 10),
                              const CircleAvatar(
                                radius: 12,
                                backgroundColor: Color(0x3399F6E4),
                                child: Text('A', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: IndexedStack(index: safeIndex, children: pages),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.safeIndex,
    required this.onSelect,
  });

  final int safeIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Text('Solar Plant Admin', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text('Site ID: PV-7742', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            children: [
              for (final item in HomeShell._navItems)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    leading: Icon(item.icon, size: 20, color: safeIndex == item.index ? const Color(0xFF0284C7) : const Color(0xFF334155)),
                    title: Text(
                      item.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: safeIndex == item.index ? const Color(0xFF0C4A6E) : const Color(0xFF0F172A),
                      ),
                    ),
                    selected: safeIndex == item.index,
                    selectedTileColor: const Color(0xFFE0F2FE),
                    onTap: () => onSelect(item.index),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

