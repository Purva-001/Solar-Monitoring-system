import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../solar_history/domain/solar_history_models.dart';
import '../state/historical_cubit.dart';
import '../state/historical_state.dart';

class HistoricalAnalysisPage extends StatefulWidget {
  const HistoricalAnalysisPage({super.key});

  @override
  State<HistoricalAnalysisPage> createState() => _HistoricalAnalysisPageState();
}

class _HistoricalAnalysisPageState extends State<HistoricalAnalysisPage> {
  String _timeRange = '7d';
  String _resolution = '1h';

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HistoricalAnalysisCubit()..load(),
      child: BlocBuilder<HistoricalAnalysisCubit, HistoricalAnalysisState>(
        builder: (context, state) {
          if (state is HistoricalAnalysisLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is HistoricalAnalysisError) {
            return Center(child: Text(state.message));
          }

          final s = state as HistoricalAnalysisLoaded;
          final points = _downsampleForResolution(s.points, _resolution);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(
                assetId: s.assetId,
                lastUpdated: s.lastUpdated,
                onRefresh: () => context.read<HistoricalAnalysisCubit>().load(assetId: s.assetId),
              ),
              const SizedBox(height: 12),
              _FilterCard(
                assetId: s.assetId,
                timeRange: _timeRange,
                resolution: _resolution,
                onTimeRangeChanged: (v) => setState(() => _timeRange = v),
                onResolutionChanged: (v) => setState(() => _resolution = v),
              ),
              const SizedBox(height: 12),
              _VoltageVsTimeCard(
                assetId: s.assetId,
                points: _sliceByRange(points, _timeRange),
              ),
              const SizedBox(height: 12),
              _EfficiencyTrendCard(points: _sliceByRange(points, _timeRange)),
              const SizedBox(height: 12),
              _MaintenanceHistoryCard(assetId: s.assetId),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.assetId, required this.lastUpdated, required this.onRefresh});

  final String assetId;
  final DateTime lastUpdated;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: AppTheme.brandBlue,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: const Icon(Icons.insights_outlined, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Analysis & Historical Data', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ),
              IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'In-depth performance metrics, panel comparisons, and maintenance history logs.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B), fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _Pill(label: 'Asset: $assetId', bg: const Color(0xFFE0F2FE), fg: const Color(0xFF075985)),
              _Pill(
                label: 'Updated: ${DateFormat('yyyy-MM-dd HH:mm').format(lastUpdated)}',
                bg: const Color(0xFFDCFCE7),
                fg: const Color(0xFF166534),
              ),
            ],
          ),
        ],
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

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.assetId,
    required this.timeRange,
    required this.resolution,
    required this.onTimeRangeChanged,
    required this.onResolutionChanged,
  });

  final String assetId;
  final String timeRange;
  final String resolution;
  final ValueChanged<String> onTimeRangeChanged;
  final ValueChanged<String> onResolutionChanged;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<String>(
              initialValue: timeRange,
              decoration: const InputDecoration(labelText: 'Last', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: '24h', child: Text('24 Hours')),
                DropdownMenuItem(value: '7d', child: Text('7 Days')),
                DropdownMenuItem(value: '30d', child: Text('30 Days')),
              ],
              onChanged: (v) {
                if (v != null) onTimeRangeChanged(v);
              },
            ),
          ),
          SizedBox(
            width: 180,
            child: TextFormField(
              initialValue: assetId,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Device', border: OutlineInputBorder()),
            ),
          ),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              initialValue: resolution,
              decoration: const InputDecoration(labelText: 'Resolution', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: '15m', child: Text('15 Min')),
                DropdownMenuItem(value: '1h', child: Text('1 Hour')),
                DropdownMenuItem(value: '1d', child: Text('1 Day')),
              ],
              onChanged: (v) {
                if (v != null) onResolutionChanged(v);
              },
            ),
          ),
          OutlinedButton(onPressed: () {}, child: const Text('Add Filter')),
        ],
      ),
    );
  }
}

class _VoltageVsTimeCard extends StatelessWidget {
  const _VoltageVsTimeCard({required this.assetId, required this.points});
  final String assetId;
  final List<SolarHistoryPoint> points;

  @override
  Widget build(BuildContext context) {
    final spotsPanel = <FlSpot>[];
    final spotsInv = <FlSpot>[];
    final minMax = _YMinMax();
    for (var i = 0; i < points.length; i += 1) {
      final p = points[i];
      final panelV = p.v1 ?? p.v2 ?? p.v3 ?? p.v4;
      final inv = _mean([p.v1, p.v2, p.v3, p.v4]);
      if (panelV != null) {
        spotsPanel.add(FlSpot(i.toDouble(), panelV));
        minMax.track(panelV);
      }
      if (inv != null) {
        spotsInv.add(FlSpot(i.toDouble(), inv));
        minMax.track(inv);
      }
    }

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Voltage vs Time Analysis',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Device: $assetId',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: points.isEmpty ? 1 : (points.length - 1).toDouble(),
                minY: minMax.minY,
                maxY: minMax.maxY,
                gridData: FlGridData(show: true, horizontalInterval: ((minMax.maxY - minMax.minY) / 4).clamp(0.1, 9999)),
                borderData: FlBorderData(show: true, border: Border.all(color: const Color(0xFFE5E7EB))),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(1), style: const TextStyle(fontSize: 10)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: _bottomInterval(points.length),
                      getTitlesWidget: (value, meta) {
                        final idx = value.round();
                        if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                        final dt = DateTime.fromMillisecondsSinceEpoch(points[idx].tsMs).toLocal();
                        return SideTitleWidget(axisSide: meta.axisSide, child: Text(DateFormat('HH:mm').format(dt), style: const TextStyle(fontSize: 10)));
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(spots: spotsPanel, isCurved: true, color: const Color(0xFF22C55E), barWidth: 3, dotData: const FlDotData(show: false)),
                  LineChartBarData(
                    spots: spotsInv,
                    isCurved: true,
                    color: AppTheme.brandBlue,
                    barWidth: 2.2,
                    dashArray: const [5, 4],
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EfficiencyTrendCard extends StatelessWidget {
  const _EfficiencyTrendCard({required this.points});
  final List<SolarHistoryPoint> points;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i += 1) {
      final p = points[i];
      final totalPower = _sum([p.p1, p.p2, p.p3, p.p4]);
      final totalVoltage = _sum([p.v1, p.v2, p.v3, p.v4]);
      final currentA = ((p.i ?? 0) / 1000.0);
      if (totalPower == null || totalVoltage == null || totalVoltage <= 0 || currentA <= 0) continue;
      final rawEff = (totalPower / (totalVoltage * currentA)) * 100;
      final clamped = rawEff.clamp(0, 100).toDouble();
      spots.add(FlSpot(i.toDouble(), clamped));
    }

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Efficiency Trends (%)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
              TextButton(onPressed: () {}, child: const Text('View Full Metrics')),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: points.isEmpty ? 1 : (points.length - 1).toDouble(),
                minY: 0,
                maxY: 100,
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: true, border: Border.all(color: const Color(0xFFE5E7EB))),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 38,
                      interval: 20,
                      getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 10)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: _bottomInterval(points.length),
                      getTitlesWidget: (value, meta) {
                        final idx = value.round();
                        if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                        final dt = DateTime.fromMillisecondsSinceEpoch(points[idx].tsMs).toLocal();
                        return SideTitleWidget(axisSide: meta.axisSide, child: Text(DateFormat('HH:mm').format(dt), style: const TextStyle(fontSize: 10)));
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: const Color(0xFF22C55E),
                    barWidth: 2.6,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF22C55E).withValues(alpha: 0.26),
                          const Color(0xFF22C55E).withValues(alpha: 0.03),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaintenanceHistoryCard extends StatelessWidget {
  const _MaintenanceHistoryCard({required this.assetId});
  final String assetId;
  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Maintenance History (Static)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            'Showing sample maintenance events for $assetId.',
            style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _historyItem('2026-01-22', 'Cleaning completed. Output normalized.'),
          _historyItem('2026-01-08', 'Visual inspection: minor dust accumulation noted.'),
          _historyItem('2025-12-18', 'Inverter connection check passed.'),
        ],
      ),
    );
  }

  Widget _historyItem(String date, String detail) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(date, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(detail, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        color: Colors.white,
      ),
      child: child,
    );
  }
}

List<SolarHistoryPoint> _sliceByRange(List<SolarHistoryPoint> points, String range) {
  if (points.isEmpty) return points;
  final now = points.last.tsMs;
  int spanMs;
  switch (range) {
    case '24h':
      spanMs = 24 * 60 * 60 * 1000;
      break;
    case '30d':
      spanMs = 30 * 24 * 60 * 60 * 1000;
      break;
    case '7d':
    default:
      spanMs = 7 * 24 * 60 * 60 * 1000;
  }
  final minTs = now - spanMs;
  final sliced = points.where((p) => p.tsMs >= minTs).toList(growable: false);
  return sliced.isEmpty ? points : sliced;
}

List<SolarHistoryPoint> _downsampleForResolution(List<SolarHistoryPoint> points, String resolution) {
  if (points.length <= 2) return points;
  final stepMinutes = switch (resolution) {
    '15m' => 15,
    '1d' => 24 * 60,
    _ => 60,
  };
  final stepMs = stepMinutes * 60 * 1000;
  final out = <SolarHistoryPoint>[];
  int? bucketStart;
  for (final p in points) {
    if (bucketStart == null || (p.tsMs - bucketStart) >= stepMs) {
      out.add(p);
      bucketStart = p.tsMs;
    }
  }
  return out.length < 2 ? points : out;
}

double _bottomInterval(int len) {
  if (len <= 4) return 1;
  if (len <= 10) return 2;
  if (len <= 20) return 4;
  return (len / 5).floorToDouble();
}

double? _mean(List<double?> vals) {
  final list = vals.whereType<double>().toList(growable: false);
  if (list.isEmpty) return null;
  return list.reduce((a, b) => a + b) / list.length;
}

double? _sum(List<double?> vals) {
  final list = vals.whereType<double>().toList(growable: false);
  if (list.isEmpty) return null;
  return list.reduce((a, b) => a + b);
}

class _YMinMax {
  double min = double.infinity;
  double max = -double.infinity;
  void track(double v) {
    if (v < min) min = v;
    if (v > max) max = v;
  }

  bool get _empty => min == double.infinity || max == -double.infinity;
  double get paddedMin => _empty ? 0 : min - (max - min) * 0.1;
  double get paddedMax => _empty ? 1 : max + (max - min) * 0.1;
  double get minY => _empty ? 0 : (paddedMin < 0 ? 0 : paddedMin);
  double get maxY => _empty ? 1 : (paddedMax == paddedMin ? paddedMax + 1 : paddedMax);
}
