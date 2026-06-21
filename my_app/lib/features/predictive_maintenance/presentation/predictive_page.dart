import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/app_theme.dart';
import '../state/predictive_cubit.dart';
import '../state/predictive_state.dart';

class PredictiveMaintenancePage extends StatelessWidget {
  const PredictiveMaintenancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PredictiveMaintenanceCubit()..load(),
      child: BlocBuilder<PredictiveMaintenanceCubit, PredictiveMaintenanceState>(
        builder: (context, state) {
          if (state is PredictiveMaintenanceLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is PredictiveMaintenanceError) {
            return Center(child: Text(state.message));
          }

          final data = (state as PredictiveMaintenanceLoaded).data;

          Color priColor;
          if (data.maintenancePriority.toLowerCase() == 'high') {
            priColor = const Color(0xFFDC2626);
          } else if (data.maintenancePriority.toLowerCase() == 'medium') {
            priColor = const Color(0xFFF59E0B);
          } else {
            priColor = AppTheme.brandGreen;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(onRefresh: () => context.read<PredictiveMaintenanceCubit>().load(panelId: data.panelId)),
              const SizedBox(height: 12),
              Card(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    color: Colors.white,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Predictive Maintenance Dashboard', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _Pill(label: 'Priority: ${data.maintenancePriority}', bg: priColor.withOpacity(0.15), fg: priColor),
                          _Pill(label: 'Trend: ${data.trend}', bg: const Color(0xFFE0F2FE), fg: const Color(0xFF075985)),
                          _Pill(label: 'Next: ${data.nextMaintenanceRecommendedDays} days', bg: const Color(0xFFDCFCE7), fg: const Color(0xFF166534)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Predicted Efficiency', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 260,
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: 100,
                            titlesData: const FlTitlesData(show: true, leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)), bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true))),
                            barGroups: [
                              BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: data.predictedEfficiency30Days, color: AppTheme.brandBlue, width: 18)]),
                              BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: data.predictedEfficiency90Days, color: AppTheme.brandGreen, width: 18)]),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('0 = 30 Days, 1 = 90 Days', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppTheme.brandBlue,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: const Icon(Icons.auto_graph_outlined, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Predictive Maintenance', style: Theme.of(context).textTheme.titleLarge)),
            IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.all(Radius.circular(999))),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w900)),
    );
  }
}
