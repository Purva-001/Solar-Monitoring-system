import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../camera/presentation/camera_view_page.dart';
import '../../health_report/presentation/health_report_dashboard_page.dart';
import '../domain/dashboard_models.dart';
import '../domain/panel_models.dart';
import '../state/dashboard_cubit.dart';
import '../state/dashboard_state.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, state) {
        if (state is DashboardLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is DashboardError) {
          return Center(child: Text(state.message));
        }

        final s = state as DashboardLoaded;
        final panels = s.panels;
        final readings = s.readings;

        final kpis = _buildKpis(readings: readings);
        final health = _buildHealthDist(readings);

        return Container(
          color: const Color(0xFFEFF6FF),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TopHeader(
                lastUpdated: s.lastUpdated,
                onRefresh: () => context.read<DashboardCubit>().refreshNow(),
                onViewCamera: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CameraViewPage()),
                ),
                onViewHealthReport: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HealthReportPage()),
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  final crossAxisCount = w >= 1200 ? 5 : (w >= 900 ? 3 : 2);
                  final childAspectRatio = w < 420 ? 1.85 : 2.15;
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: childAspectRatio,
                    ),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: kpis.length,
                    itemBuilder: (context, i) => _KpiCard(kpi: kpis[i]),
                  );
                },
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  final isWide = w >= 1050;
                  final children = <Widget>[
                    Expanded(
                      flex: 2,
                      child: _PowerTrendCard(powerSeries: s.powerSeries),
                    ),
                    const SizedBox(width: 12, height: 12),
                    Expanded(
                      child: _HealthDistributionCard(health: health, totalPanels: readings.panelChannelCount),
                    ),
                  ];

                  if (isWide) {
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
                  }
                  return Column(
                    children: [
                      _PowerTrendCard(powerSeries: s.powerSeries),
                      const SizedBox(height: 12),
                      _HealthDistributionCard(health: health, totalPanels: readings.panelChannelCount),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Text('Solar Panels (${panels.length})', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  final crossAxisCount = w >= 1200 ? 3 : (w >= 760 ? 2 : 1);
                  // Single column: avoid GridView row height (width/ratio) — it leaves a tall empty band under each card.
                  if (crossAxisCount == 1) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < panels.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          _PanelCard(panel: panels[i], readings: readings),
                        ],
                      ],
                    );
                  }
                  // Multi-column: tighter cells so paired rows do not reserve excess vertical space.
                  final childAspectRatio = crossAxisCount >= 3 ? 2.05 : 1.95;
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: childAspectRatio,
                    ),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: panels.length,
                    itemBuilder: (context, i) => _PanelCard(panel: panels[i], readings: readings),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class KpiItem {
  const KpiItem({required this.label, required this.value, required this.icon, required this.color});

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

List<KpiItem> _buildKpis({required DashboardReadings readings}) {
  String cls(double p) {
    final ap = p.abs();
    if (ap >= 5) return 'healthy';
    if (ap >= 1) return 'warning';
    return 'critical';
  }

  final classes = [cls(readings.p1), cls(readings.p2), cls(readings.p3), cls(readings.p4)];
  final healthy = classes.where((c) => c == 'healthy').length;
  final warning = classes.where((c) => c == 'warning').length;
  final critical = classes.where((c) => c == 'critical').length;

  return [
    KpiItem(label: 'Total Panels', value: readings.panelChannelCount.toString(), icon: Icons.grid_view_rounded, color: const Color(0xFF2563EB)),
    KpiItem(label: 'Active', value: healthy.toString(), icon: Icons.bolt_rounded, color: const Color(0xFF22C55E)),
    KpiItem(label: 'Warning', value: warning.toString(), icon: Icons.warning_amber_rounded, color: const Color(0xFFF59E0B)),
    KpiItem(label: 'Critical', value: critical.toString(), icon: Icons.error_outline_rounded, color: const Color(0xFFEF4444)),
    KpiItem(label: 'Total Power', value: '${readings.totalPowerW.toStringAsFixed(2)} W', icon: Icons.bolt_rounded, color: const Color(0xFF16A34A)),
  ];
}

({int healthyPct, int warningPct, int criticalPct}) _buildHealthDist(DashboardReadings readings) {
  String cls(double p) {
    final ap = p.abs();
    if (ap >= 5) return 'healthy';
    if (ap >= 1) return 'warning';
    return 'critical';
  }

  final classes = [cls(readings.p1), cls(readings.p2), cls(readings.p3), cls(readings.p4)];
  final healthy = classes.where((c) => c == 'healthy').length;
  final warning = classes.where((c) => c == 'warning').length;
  final critical = classes.where((c) => c == 'critical').length;
  final total = readings.panelChannelCount < 1 ? 1 : readings.panelChannelCount;

  return (
    healthyPct: ((healthy / total) * 100).round(),
    warningPct: ((warning / total) * 100).round(),
    criticalPct: ((critical / total) * 100).round(),
  );
}

enum _PanelPowerTier { healthy, warning, critical }

_PanelPowerTier _powerTierFromW(double powerW) {
  final ap = powerW.abs();
  if (ap >= 5) return _PanelPowerTier.healthy;
  if (ap >= 1) return _PanelPowerTier.warning;
  return _PanelPowerTier.critical;
}

({String label, Color accent, Color chipBg, Color chipFg, IconData icon}) _tierStyle(_PanelPowerTier tier) {
  return switch (tier) {
    _PanelPowerTier.healthy => (
        label: 'Healthy',
        accent: const Color(0xFF22C55E),
        chipBg: const Color(0xFFDCFCE7),
        chipFg: const Color(0xFF166534),
        icon: Icons.check_circle_rounded,
      ),
    _PanelPowerTier.warning => (
        label: 'Warning',
        accent: const Color(0xFFF59E0B),
        chipBg: const Color(0xFFFEF3C7),
        chipFg: const Color(0xFF92400E),
        icon: Icons.warning_amber_rounded,
      ),
    _PanelPowerTier.critical => (
        label: 'Critical',
        accent: const Color(0xFFEF4444),
        chipBg: const Color(0xFFFEE2E2),
        chipFg: const Color(0xFF991B1B),
        icon: Icons.error_outline_rounded,
      ),
  };
}

double _branchCurrentMa(DashboardReadings r, int? channel) {
  double raw = 0;
  if (channel == 1) {
    raw = r.c1 ?? 0;
  } else if (channel == 2) {
    raw = r.c2 ?? 0;
  } else if (channel == 3) {
    raw = r.c3 ?? 0;
  } else if (channel == 4) {
    raw = r.c4 ?? 0;
  }
  if (raw.abs() > 1e-3) return raw;
  var v = r.v1;
  var p = r.p1;
  if (channel == 2) {
    v = r.v2;
    p = r.p2;
  } else if (channel == 3) {
    v = r.v3;
    p = r.p3;
  } else if (channel == 4) {
    v = r.v4;
    p = r.p4;
  }
  if (v.abs() < 1e-6) return 0;
  return (p / v) * 1000;
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.lastUpdated,
    required this.onRefresh,
    required this.onViewCamera,
    required this.onViewHealthReport,
  });

  final DateTime lastUpdated;
  final VoidCallback onRefresh;
  final VoidCallback onViewCamera;
  final VoidCallback onViewHealthReport;

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('GreenEnergy Park A', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(
                    'Last updated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(lastUpdated)}',
                    style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Tooltip(
                  message: 'View Camera',
                  child: IconButton(
                    onPressed: onViewCamera,
                    icon: const Icon(Icons.camera_alt_rounded),
                    tooltip: 'View Camera Feed',
                  ),
                ),
                Tooltip(
                  message: 'Refresh Data',
                  child: IconButton(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.kpi});

  final KpiItem kpi;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        padding: const EdgeInsets.all(12),
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
              decoration: BoxDecoration(color: kpi.color.withValues(alpha: 0.12), borderRadius: const BorderRadius.all(Radius.circular(12))),
              child: Icon(kpi.icon, color: kpi.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    kpi.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    kpi.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _PowerTrendCard extends StatelessWidget {
  const _PowerTrendCard({required this.powerSeries});

  final List<PowerPoint> powerSeries;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - (60 * 60 * 1000);
    final filtered = powerSeries.where((p) => p.tsMs >= cutoff).toList(growable: false);

    final spots = <FlSpot>[];
    for (var i = 0; i < filtered.length; i++) {
      final p = filtered[i];
      spots.add(FlSpot(i.toDouble(), p.w));
    }

    double minY = 0;
    double maxY = 10;
    if (filtered.isNotEmpty) {
      final vals = filtered.map((e) => e.w).toList();
      minY = vals.reduce((a, b) => a < b ? a : b);
      maxY = vals.reduce((a, b) => a > b ? a : b);
      final pad = (maxY - minY) * 0.1;
      minY = (minY - pad).clamp(0, double.infinity);
      maxY = maxY + pad + 1;
    }

    final yInterval = ((maxY - minY) / 4).clamp(0.25, double.infinity);
    final yDecimals = yInterval < 1 ? 2 : (yInterval < 5 ? 1 : 0);

    return Card(
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
            Text('Power Trend (Last 1 Hour)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  gridData: const FlGridData(show: true),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      axisNameWidget: const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Time', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                      ),
                      axisNameSize: 22,
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: filtered.length <= 1 ? 1 : (filtered.length / 4).ceilToDouble(),
                        getTitlesWidget: (value, meta) {
                          final i = value.round();
                          if (i < 0 || i >= filtered.length) return const SizedBox.shrink();
                          final dt = DateTime.fromMillisecondsSinceEpoch(filtered[i].tsMs);
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(DateFormat('HH:mm').format(dt), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      axisNameWidget: const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Text('Power (W)', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                      ),
                      axisNameSize: 22,
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(yDecimals),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                            textAlign: TextAlign.right,
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: true, border: Border.all(color: const Color(0xFFE5E7EB))),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      barWidth: 3,
                      color: AppTheme.brandGreen,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: true, color: AppTheme.brandGreen.withValues(alpha: 0.10)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthDistributionCard extends StatelessWidget {
  const _HealthDistributionCard({required this.health, required this.totalPanels});

  final ({int healthyPct, int warningPct, int criticalPct}) health;
  final int totalPanels;

  @override
  Widget build(BuildContext context) {
    final sections = <PieChartSectionData>[
      PieChartSectionData(value: health.healthyPct.toDouble(), color: const Color(0xFF22C55E), radius: 16, showTitle: false),
      PieChartSectionData(value: health.warningPct.toDouble(), color: const Color(0xFFF59E0B), radius: 16, showTitle: false),
      PieChartSectionData(value: health.criticalPct.toDouble(), color: const Color(0xFFEF4444), radius: 16, showTitle: false),
    ];

    final dominant = <({String label, int pct, Color color})>[
      (label: 'Healthy', pct: health.healthyPct, color: const Color(0xFF22C55E)),
      (label: 'Warning', pct: health.warningPct, color: const Color(0xFFF59E0B)),
      (label: 'Critical', pct: health.criticalPct, color: const Color(0xFFEF4444)),
    ]..sort((a, b) => b.pct.compareTo(a.pct));
    final top = dominant.first;

    final allLegendItems = <({String label, String value, Color color, int pct})>[ 
      (label: 'Healthy', value: '${health.healthyPct}%', color: const Color(0xFF22C55E), pct: health.healthyPct),
      (label: 'Warning', value: '${health.warningPct}%', color: const Color(0xFFF59E0B), pct: health.warningPct),
      (label: 'Critical', value: '${health.criticalPct}%', color: const Color(0xFFEF4444), pct: health.criticalPct),
    ];
    final legendItems = allLegendItems.where((e) => e.pct > 0).toList(growable: false);
    final effectiveLegendItems = legendItems.isEmpty ? allLegendItems : legendItems;

    return Card(
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
            Text('Health Distribution', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sections: sections,
                      centerSpaceRadius: 56,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${top.pct}%',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: top.color),
                      ),
                      const SizedBox(height: 2),
                      Text(top.label, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                      const SizedBox(height: 2),
                      Text('Panels: $totalPanels', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final item in effectiveLegendItems) _LegendDot(label: item.label, value: item.value, color: item.color),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.all(Radius.circular(999)))),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.panel, required this.readings});

  final PanelSummary panel;
  final DashboardReadings readings;

  int? _panelNumber() {
    final id = panel.id;
    if (id.contains('-P01')) return 1;
    if (id.contains('-P02')) return 2;
    if (id.contains('-P03')) return 3;
    if (id.contains('-P04')) return 4;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pNum = _panelNumber();
    final voltage = pNum == 1
        ? readings.v1
        : pNum == 2
            ? readings.v2
            : pNum == 3
                ? readings.v3
                : pNum == 4
                    ? readings.v4
                    : readings.v1;
    final power = pNum == 1
        ? readings.p1
        : pNum == 2
            ? readings.p2
            : pNum == 3
                ? readings.p3
                : pNum == 4
                    ? readings.p4
                    : (panel.currentOutput ?? 0);
    final currentMa = _branchCurrentMa(readings, pNum);
    final tier = _powerTierFromW(power);
    final style = _tierStyle(tier);

    return LayoutBuilder(
      builder: (context, constraints) {
        const pad = EdgeInsets.fromLTRB(19, 10, 12, 10);
        final innerW = (constraints.maxWidth - pad.horizontal).clamp(1.0, double.infinity);
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: constraints.maxWidth,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.all(Radius.circular(18)),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(17)),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 5,
                        decoration: BoxDecoration(
                          color: style.accent,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(17),
                            bottomLeft: Radius.circular(17),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: pad,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: innerW,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      panel.name,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: const Color(0xFF0F172A),
                                            letterSpacing: -0.2,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: const BorderRadius.all(Radius.circular(8)),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        child: Text(
                                          panel.id,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF475569),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.all(Radius.circular(999)),
                                  color: style.chipBg,
                                  border: Border.all(color: style.accent.withValues(alpha: 0.45)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(style.icon, size: 16, color: style.chipFg),
                                    const SizedBox(width: 6),
                                    Text(
                                      style.label,
                                      style: TextStyle(fontWeight: FontWeight.w900, color: style.chipFg, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _PanelStatTile(
                                  icon: Icons.bolt_rounded,
                                  label: 'Voltage',
                                  value: '${voltage.toStringAsFixed(2)} V',
                                  tint: AppTheme.brandBlue,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _PanelStatTile(
                                  icon: Icons.flash_on_rounded,
                                  label: 'Power',
                                  value: '${power.toStringAsFixed(2)} W',
                                  tint: const Color(0xFF16A34A),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _PanelStatTile(
                                  icon: Icons.electric_meter_rounded,
                                  label: 'Current',
                                  value: '${currentMa.toStringAsFixed(1)} mA',
                                  tint: const Color(0xFF7C3AED),
                                ),
                              ),
                            ],
                          ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PanelStatTile extends StatelessWidget {
  const _PanelStatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: tint),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF64748B),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
