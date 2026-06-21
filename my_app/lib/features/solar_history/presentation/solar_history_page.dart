import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import '../../../app/theme/app_theme.dart';
import '../domain/solar_history_models.dart';
import '../state/solar_history_cubit.dart';
import '../state/solar_history_state.dart';

class SolarHistoryPage extends StatefulWidget {
  const SolarHistoryPage({super.key});

  @override
  State<SolarHistoryPage> createState() => _SolarHistoryPageState();
}

class _SolarHistoryPageState extends State<SolarHistoryPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final current = context.read<SolarHistoryCubit>().state;
      final assetId = current is SolarHistoryLoaded ? current.assetId : 'SolarPanel_01';
      context.read<SolarHistoryCubit>().load(assetId: assetId, silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SolarHistoryCubit, SolarHistoryState>(
      builder: (context, state) {
        if (state is SolarHistoryLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is SolarHistoryError) {
          return _ErrorView(message: state.message);
        }

        final s = state as SolarHistoryLoaded;
        final curveSource = s.ivPvPoint ?? (s.points.isEmpty ? null : s.points.last);
        final iv = _spreadDuplicateX(_latestIvCurve(curveSource));
        final pv = _spreadDuplicateX(_latestPvCurve(curveSource));
        final curveSubtitle =
            curveSource != null && s.ivPvPoint != null
                ? 'From live snapshot (/api/solar-iv-pv → AWS)'
                : 'From last solar-history row (set AWS_SOLAR_HISTORY_ENDPOINT); live snapshot unavailable';

        return RefreshIndicator(
          onRefresh: () => context.read<SolarHistoryCubit>().load(assetId: s.assetId),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(assetId: s.assetId, lastUpdated: s.lastUpdated),
              const SizedBox(height: 12),
              _XYCurveCard(
                title: 'I-V Curve',
                subtitle: 'Current (mA) vs Voltage (V). $curveSubtitle',
                lineName: 'Current',
                color: AppTheme.brandBlue,
                points: iv,
                yUnit: 'mA',
                xUnit: 'V',
              ),
              const SizedBox(height: 12),
              _XYCurveCard(
                title: 'P-V Curve',
                subtitle: 'Power (W) vs Voltage (V). $curveSubtitle',
                lineName: 'Power',
                color: AppTheme.brandGreen,
                points: pv,
                yUnit: 'W',
                xUnit: 'V',
              ),
              const SizedBox(height: 12),
              _TrendCard(
                title: 'Voltage (V)',
                subtitle: 'Historical voltage readings (AWS solar history)',
                points: s.points,
                lines: const [
                  _LineDef(name: 'V1', color: AppTheme.brandBlue, selector: _pickV1),
                  _LineDef(name: 'V2', color: Color(0xFF38BDF8), selector: _pickV2),
                  _LineDef(name: 'V3', color: Color(0xFF0EA5E9), selector: _pickV3),
                  _LineDef(name: 'V4', color: Color(0xFF0369A1), selector: _pickV4),
                ],
                yUnit: 'V',
              ),
              const SizedBox(height: 12),
              _TrendCard(
                title: 'Power (W)',
                subtitle: 'Historical power readings (AWS solar history)',
                points: s.points,
                lines: const [
                  _LineDef(name: 'P1', color: Color(0xFFF59E0B), selector: _pickP1),
                  _LineDef(name: 'P2', color: AppTheme.brandGreen, selector: _pickP2),
                  _LineDef(name: 'P3', color: Color(0xFF16A34A), selector: _pickP3),
                  _LineDef(name: 'P4', color: Color(0xFF15803D), selector: _pickP4),
                ],
                yUnit: 'W',
              ),
              const SizedBox(height: 12),
              _TrendCard(
                title: 'Current (mA)',
                subtitle: 'Historical current readings',
                points: s.points,
                lines: const [
                  _LineDef(name: 'I', color: Color(0xFF2563EB), selector: _pickI),
                ],
                yUnit: 'mA',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.assetId, required this.lastUpdated});

  final String assetId;
  final DateTime lastUpdated;

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
              child: const Icon(Icons.insights, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Solar History', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _Pill(label: 'Asset: $assetId', bg: const Color(0xFFE0F2FE), fg: const Color(0xFF075985)),
                      _Pill(
                        label: 'Updated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(lastUpdated)}',
                        bg: const Color(0xFFDCFCE7),
                        fg: const Color(0xFF166534),
                      ),
                    ],
                  )
                ],
              ),
            ),
            IconButton(
              onPressed: () => context.read<SolarHistoryCubit>().load(assetId: assetId),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            )
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

class _XYCurveCard extends StatelessWidget {
  const _XYCurveCard({
    required this.title,
    required this.subtitle,
    required this.lineName,
    required this.color,
    required this.points,
    required this.yUnit,
    required this.xUnit,
  });

  final String title;
  final String subtitle;
  final String lineName;
  final Color color;
  final List<_XYPoint> points;
  final String yUnit;
  final String xUnit;

  @override
  Widget build(BuildContext context) {
    final series = <FlSpot>[];
    final yValues = <double>[];
    for (var i = 0; i < points.length; i += 1) {
      series.add(FlSpot(points[i].x, points[i].y));
      yValues.add(points[i].y);
    }
    final minY = yValues.isEmpty ? 0.0 : yValues.reduce((a, b) => a < b ? a : b);
    final maxY = yValues.isEmpty ? 1.0 : yValues.reduce((a, b) => a > b ? a : b);
    final yPad = ((maxY - minY).abs() * 0.15).clamp(0.1, 1000000.0);
    final chartMinY = 0.0;
    final chartMaxY = (maxY + yPad) <= chartMinY ? (chartMinY + 1.0) : (maxY + yPad);

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
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: LineChart(
                LineChartData(
                  minX: points.isEmpty ? 0 : points.first.x,
                  maxX: points.isEmpty ? 1 : points.last.x,
                  minY: chartMinY,
                  maxY: chartMaxY,
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: true, border: Border.all(color: const Color(0xFFE5E7EB))),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        interval: ((points.isEmpty ? 1 : (points.last.x - points.first.x)) / 3).clamp(0.01, 99999999),
                        getTitlesWidget: (value, meta) => Text('${value.toStringAsFixed(2)} $xUnit', style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        interval: ((chartMaxY - chartMinY) / 4).clamp(0.1, 99999999),
                        getTitlesWidget: (value, meta) => Text('${value.toStringAsFixed(0)} $yUnit', style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: series,
                      isCurved: true,
                      color: color,
                      barWidth: 3,
                      dotData: FlDotData(show: points.length <= 4),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (touchedSpot) => const Color(0xFF0F172A),
                      getTooltipItems: (touchedSpots) => touchedSpots
                          .map(
                            (s) => LineTooltipItem(
                              '$lineName\n${s.y.toStringAsFixed(2)} $yUnit @ ${s.x.toStringAsFixed(4)} $xUnit',
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title,
    required this.subtitle,
    required this.points,
    required this.lines,
    required this.yUnit,
  });
  final String title;
  final String subtitle;
  final List<SolarHistoryPoint> points;
  final List<_LineDef> lines;
  final String yUnit;

  @override
  Widget build(BuildContext context) {
    final lineBars = <LineChartBarData>[];
    final yValues = <double>[];
    for (final line in lines) {
      final spots = <FlSpot>[];
      for (var i = 0; i < points.length; i += 1) {
        final y = line.selector(points[i]);
        if (y == null) continue;
        spots.add(FlSpot(i.toDouble(), y));
        yValues.add(y);
      }
      lineBars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: line.color,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
        ),
      );
    }

    final minY = yValues.isEmpty ? 0.0 : yValues.reduce((a, b) => a < b ? a : b);
    final maxY = yValues.isEmpty ? 1.0 : yValues.reduce((a, b) => a > b ? a : b);
    final yPad = ((maxY - minY).abs() * 0.15).clamp(0.1, 1000000.0);
    final chartMinY = 0.0;
    final chartMaxY = (maxY + yPad) <= chartMinY ? (chartMinY + 1.0) : (maxY + yPad);
    final intervalX = points.length <= 4 ? 1.0 : (points.length / 5).floorToDouble();

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
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: lines
                  .map(
                    (l) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: l.color, borderRadius: BorderRadius.circular(999))),
                        const SizedBox(width: 6),
                        Text(l.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 260,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: points.isEmpty ? 1 : (points.length - 1).toDouble(),
                  minY: chartMinY,
                  maxY: chartMaxY,
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: true, border: Border.all(color: const Color(0xFFE5E7EB))),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        interval: intervalX,
                        getTitlesWidget: (value, meta) {
                          final i = value.round();
                          if (i < 0 || i >= points.length) return const SizedBox.shrink();
                          final dt = DateTime.fromMillisecondsSinceEpoch(points[i].tsMs).toLocal();
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(DateFormat('HH:mm').format(dt), style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 46,
                        interval: ((chartMaxY - chartMinY) / 4).clamp(0.1, 1000000.0),
                        getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(yUnit == 'mA' ? 0 : 1), style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                  ),
                  lineBarsData: lineBars,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _XYPoint {
  const _XYPoint({required this.x, required this.y});
  final double x;
  final double y;
}

/// When two channels share nearly the same voltage, fl_chart draws one dot; nudge X slightly.
List<_XYPoint> _spreadDuplicateX(List<_XYPoint> raw) {
  if (raw.length < 2) return raw;
  final sorted = [...raw]..sort((a, b) => a.x.compareTo(b.x));
  const eps = 0.025;
  final out = <_XYPoint>[];
  double lastX = -1e9;
  for (final p in sorted) {
    var x = p.x;
    if ((x - lastX).abs() < eps) {
      x = lastX + eps;
    }
    out.add(_XYPoint(x: x, y: p.y));
    lastX = x;
  }
  return out;
}

class _LineDef {
  const _LineDef({required this.name, required this.color, required this.selector});
  final String name;
  final Color color;
  final double? Function(SolarHistoryPoint) selector;
}

double _ivCurrentMa(SolarHistoryPoint row, double? branchMa) => branchMa ?? row.i ?? 0;

List<_XYPoint> _latestIvCurve(SolarHistoryPoint? latest) {
  if (latest == null) return const [];
  final pts = [
    _xyIv(latest.v1, _ivCurrentMa(latest, latest.i1Ma)),
    _xyIv(latest.v2, _ivCurrentMa(latest, latest.i2Ma)),
    _xyIv(latest.v3, _ivCurrentMa(latest, latest.i3Ma)),
    _xyIv(latest.v4, _ivCurrentMa(latest, latest.i4Ma)),
  ].whereType<_XYPoint>().toList()
    ..sort((a, b) => a.x.compareTo(b.x));
  return pts;
}

List<_XYPoint> _latestPvCurve(SolarHistoryPoint? latest) {
  if (latest == null) return const [];
  final pts = [
    _xy(latest.v1, latest.p1),
    _xy(latest.v2, latest.p2),
    _xy(latest.v3, latest.p3),
    _xy(latest.v4, latest.p4),
  ].whereType<_XYPoint>().toList()
    ..sort((a, b) => a.x.compareTo(b.x));
  return pts;
}

_XYPoint? _xyIv(double? voltageV, double currentMa) {
  if (voltageV == null || !voltageV.isFinite) return null;
  return _XYPoint(x: voltageV.abs(), y: currentMa.abs());
}

_XYPoint? _xy(double? x, double? y) {
  if (x == null || y == null) return null;
  return _XYPoint(x: x.abs(), y: y.abs());
}

double? _safeAbs(double? v) => v?.abs();

double? _pickV1(SolarHistoryPoint p) => _safeAbs(p.v1);
double? _pickV2(SolarHistoryPoint p) => _safeAbs(p.v2);
double? _pickV3(SolarHistoryPoint p) => _safeAbs(p.v3);
double? _pickV4(SolarHistoryPoint p) => _safeAbs(p.v4);
double? _pickP1(SolarHistoryPoint p) => _safeAbs(p.p1);
double? _pickP2(SolarHistoryPoint p) => _safeAbs(p.p2);
double? _pickP3(SolarHistoryPoint p) => _safeAbs(p.p3);
double? _pickP4(SolarHistoryPoint p) => _safeAbs(p.p4);
double? _pickI(SolarHistoryPoint p) => _safeAbs(p.i);
