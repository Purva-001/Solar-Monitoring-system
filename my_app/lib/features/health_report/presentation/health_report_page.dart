import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../app/theme/app_theme.dart';
import '../../camera/presentation/camera_feed_card.dart';
import '../../camera/state/camera_feed_cubit.dart';
import '../../panel_snapshot/panel_health_markdown.dart';
import '../domain/health_report_models.dart';
import '../state/health_report_cubit.dart';
import '../state/health_report_state.dart';
import '../../../core/api/api_config.dart';
import 'package:http/http.dart' as http;

class HealthReportPage extends StatelessWidget {
  const HealthReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HealthReportCubit, HealthReportState>(
      builder: (context, state) {
        if (state is HealthReportLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is HealthReportError) {
          return Center(child: Text(state.message));
        }

        final loaded = state as HealthReportLoaded;
        final report = loaded.report;
        final weather = loaded.weather ?? const <String, dynamic>{};
        final readings = loaded.readings ?? const <String, dynamic>{};
        final expectedPowerW = 10.0;
        final outputPowerW = _pickReading(readings, 'P1') ?? report.sensorData.p1.value;
        final outputVsExpectedPct = expectedPowerW > 0 ? (outputPowerW / expectedPowerW) * 100 : 0.0;
        final confidencePct = (report.defectAnalysis.confidence.clamp(0, 1) * 100).toDouble();
        final healthScore = report.defectAnalysis.defect.toLowerCase() == 'none' ? 95.0 : math.max(10, 100 - confidencePct * 0.7);
        final statusText = healthScore >= 90 ? 'HEALTHY' : healthScore >= 75 ? 'NEEDS ATTENTION' : 'CRITICAL';
        final statusColor = healthScore >= 90 ? const Color(0xFF16A34A) : healthScore >= 75 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);
        final allMarkdown = report.healthReportMarkdown.trim();
        final defectLabel = report.defectAnalysis.defect.trim().isEmpty ? 'None' : report.defectAnalysis.defect.trim();
        final clean = isCleanDefect(report.defectAnalysis.defect, report.status);

        final summaryPick = report.aiSummaryMarkdown?.trim().isNotEmpty == true
            ? report.aiSummaryMarkdown!.trim()
            : (pickMarkdownSection(allMarkdown, const ['summary']) ?? (allMarkdown.isNotEmpty ? allMarkdown : null) ?? '');
        final summaryMd = sanitizeSummaryMarkdown(summaryPick, defectType: defectLabel);

        final rootMd = report.aiRootCauseMarkdown?.trim().isNotEmpty == true
            ? report.aiRootCauseMarkdown!.trim()
            : (pickMarkdownSection(allMarkdown, const ['root cause analysis', 'root cause']) ?? '');
        final rootCauseMd = rootMd.isNotEmpty ? rootMd : (clean ? defaultRootCauseClean : defaultRootCauseIssue);

        final recMd = report.aiRecommendationsMarkdown?.trim().isNotEmpty == true
            ? report.aiRecommendationsMarkdown!.trim()
            : (pickMarkdownSection(allMarkdown, const ['recommendations', 'recommended actions', 'recommended action']) ?? '');
        final recBase = recMd.isNotEmpty
            ? recMd
            : (allMarkdown.isNotEmpty ? allMarkdown : (clean ? defaultRecommendationsClean : defaultRecommendationsIssue));
        final recommendationsMd = truncateMarkdownLines(
          containsKbNotFound(allMarkdown) ? (clean ? defaultRecommendationsClean : defaultRecommendationsIssue) : recBase,
          maxLines: 18,
        );

        // Trigger servo motor when AI recommends cleaning
        if (_shouldTriggerServo(recommendationsMd)) {
          _triggerCleaningServo();
        }

        return RefreshIndicator(
          onRefresh: () => context.read<HealthReportCubit>().load(panelId: report.panelId),
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _WeatherStrip(weather: weather),
              const SizedBox(height: 10),
              _ReportHeader(
                panelId: report.panelId,
                timestampIso: report.timestampIso,
                onRerun: () => context.read<HealthReportCubit>().load(panelId: report.panelId, force: true),
              ),
              const SizedBox(height: 10),
              _PanelIdentificationCard(
                report: report,
                statusText: statusText,
                statusColor: statusColor,
                expectedPowerW: expectedPowerW,
                outputVsExpectedPct: outputVsExpectedPct,
                outputPowerW: outputPowerW,
              ),
              const SizedBox(height: 10),
              _MetricGrid(
                voltage: _pickReading(readings, 'V1') ?? report.sensorData.v1.value,
                current: _pickReading(readings, 'I') ?? report.sensorData.i.value,
                temperature: (weather['temperature_c'] as num?)?.toDouble() ?? 32.7,
              ),
              const SizedBox(height: 10),
              _PerformanceChart(expectedPowerW: expectedPowerW, outputPowerW: outputPowerW),
              const SizedBox(height: 10),
              if (report.geminiError != null && report.geminiError!.trim().isNotEmpty) ...[
                _WarningBanner(message: report.geminiError!.trim()),
                const SizedBox(height: 10),
              ],
              _MarkdownCard(
                title: 'AI Summary',
                icon: Icons.auto_awesome,
                markdown: summaryMd,
                emptyMessage: 'No AI content returned by API. Tap Re-run after configuring Gemini on the server.',
              ),
              const SizedBox(height: 10),
              _MarkdownCard(title: 'Recommendations', icon: Icons.check_circle_outline, markdown: recommendationsMd),
              const SizedBox(height: 10),
              BlocProvider(
                create: (_) => CameraFeedCubit()..start(),
                child: CameraFeedCard(panelId: report.panelId),
              ),
              const SizedBox(height: 10),
              _DiagnosisCard(defect: report.defectAnalysis.defect, confidencePct: confidencePct),
              const SizedBox(height: 10),
              _MarkdownCard(title: 'Root Cause Analysis', icon: Icons.account_tree_outlined, markdown: rootCauseMd, emptyMessage: 'No root cause returned by API'),
              const SizedBox(height: 10),
              const _TimelineCard(),
              const SizedBox(height: 10),
              const _KnowledgeCard(),
              const SizedBox(height: 10),
              if (clean)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FilledButton.icon(
                    onPressed: () async {
                      try {
                        await context.read<HealthReportCubit>().moveServo(angle: 90);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Servo moved successfully')));
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to move servo: $e')));
                      }
                    },
                    icon: const Icon(Icons.settings_remote),
                    label: const Text('Move Servo (clean)'),
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}

class _WeatherStrip extends StatelessWidget {
  const _WeatherStrip({required this.weather});
  final Map<String, dynamic> weather;

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, String value) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      );
    }

    return _CardShell(
      child: Row(
        children: [
          tile('CITY', (weather['city'] ?? 'Wardha').toString()),
          tile('WEATHER', (weather['condition'] ?? 'Clear').toString()),
          tile('TEMP', '${((weather['temperature_c'] as num?)?.toDouble() ?? 32.7).toStringAsFixed(1)} °C'),
          tile('HUMIDITY', '${((weather['humidity_percent'] as num?)?.toDouble() ?? 20).toStringAsFixed(0)}%'),
        ],
      ),
    );
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({required this.panelId, required this.timestampIso, required this.onRerun});
  final String panelId;
  final String timestampIso;
  final VoidCallback onRerun;

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(timestampIso);
    final ts = dt == null ? timestampIso : dt.toLocal().toString().split('.').first;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Panel Health Report: $panelId', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Last updated: $ts', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.download_outlined), label: const Text('Export')),
              OutlinedButton.icon(onPressed: onRerun, icon: const Icon(Icons.analytics_outlined), label: const Text('Re-run')),
              FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.build), label: const Text('Schedule')),
            ],
          ),
        ],
      ),
    );
  }
}

class _PanelIdentificationCard extends StatelessWidget {
  const _PanelIdentificationCard({
    required this.report,
    required this.statusText,
    required this.statusColor,
    required this.expectedPowerW,
    required this.outputVsExpectedPct,
    required this.outputPowerW,
  });
  final HealthReport report;
  final String statusText;
  final Color statusColor;
  final double expectedPowerW;
  final double outputVsExpectedPct;
  final double outputPowerW;

  @override
  Widget build(BuildContext context) {
    Widget row(String k, String v) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(k, style: const TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w800))),
            const SizedBox(width: 8),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      );
    }

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, color: AppTheme.brandGreen),
              const SizedBox(width: 8),
              Text('Panel Identification & Status', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          row('Panel ID', report.panelId),
          row('Operating State', report.status),
          row('Expected Output', '${expectedPowerW.toStringAsFixed(0)} W'),
          row('Output vs Expected', '${outputVsExpectedPct.toStringAsFixed(0)}%'),
          row('Max Power Output', '${outputPowerW.toStringAsFixed(1)} W'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.voltage, required this.current, required this.temperature});
  final double voltage;
  final double current;
  final double temperature;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final crossAxisCount = w < 420 ? 2 : 3;
        final childAspectRatio = w < 420 ? 1.35 : 1.18;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: childAspectRatio,
          children: [
            _MetricCell(title: 'VOLTAGE (VOC)', value: voltage.toStringAsFixed(1), unit: 'V', color: const Color(0xFF16A34A)),
            _MetricCell(title: 'CURRENT (ISC)', value: current.toStringAsFixed(1), unit: 'A', color: const Color(0xFF16A34A)),
            _MetricCell(title: 'TEMPERATURE', value: temperature.toStringAsFixed(1), unit: '°C', color: const Color(0xFFF59E0B)),
          ],
        );
      },
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.title, required this.value, required this.unit, required this.color});
  final String title;
  final String value;
  final String unit;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return _CardShell(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                const SizedBox(width: 4),
                Text(unit, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF475569))),
              ],
            ),
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: math.min(1, (double.tryParse(value) ?? 0) / 100), minHeight: 5, color: color, backgroundColor: const Color(0xFFE2E8F0)),
          ),
        ],
      ),
    );
  }
}

class _PerformanceChart extends StatelessWidget {
  const _PerformanceChart({required this.expectedPowerW, required this.outputPowerW});
  final double expectedPowerW;
  final double outputPowerW;
  @override
  Widget build(BuildContext context) {
    final barsExpected = <FlSpot>[const FlSpot(0, 10), FlSpot(1, expectedPowerW)];
    final barsOutput = <FlSpot>[const FlSpot(0, 0), FlSpot(1, outputPowerW)];
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Performance Charts', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          SizedBox(
            height: 170,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true),
                titlesData: const FlTitlesData(
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                minX: 0,
                maxX: 1,
                minY: 0,
                lineBarsData: [
                  LineChartBarData(isCurved: true, color: const Color(0xFF16A34A), spots: barsExpected, barWidth: 3),
                  LineChartBarData(isCurved: true, color: AppTheme.brandBlue, spots: barsOutput, barWidth: 3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosisCard extends StatelessWidget {
  const _DiagnosisCard({required this.defect, required this.confidencePct});
  final String defect;
  final double confidencePct;
  @override
  Widget build(BuildContext context) {
    final color = confidencePct >= 90 ? const Color(0xFF16A34A) : confidencePct >= 70 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AI Diagnosis', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text('DEFECT TYPE', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800)),
          Text(defect.isEmpty ? 'None' : defect, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          const Text('CONFIDENCE', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: confidencePct / 100, minHeight: 8, color: color, backgroundColor: const Color(0xFFE2E8F0)),
          const SizedBox(height: 4),
          Text('${confidencePct.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _MarkdownCard extends StatelessWidget {
  const _MarkdownCard({
    required this.title,
    required this.icon,
    required this.markdown,
    this.emptyMessage = 'No AI content returned by API',
  });
  final String title;
  final IconData icon;
  final String markdown;
  final String emptyMessage;
  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: AppTheme.brandGreen), const SizedBox(width: 8), Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))]),
          const SizedBox(height: 10),
          if (markdown.trim().isEmpty)
            Text(
              emptyMessage,
              style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
            )
          else
            MarkdownBody(data: markdown),
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard();
  @override
  Widget build(BuildContext context) {
    final rows = const [
      ['12 Feb', 'Dust detected', 'Cleaned', '+18% power', 'Kunal', 'WO-000123', 'Resolved'],
      ['20 Mar', 'Crack suspected', 'Inspection', 'Stable', 'Kunal', 'WO-000124', 'Monitor'],
    ];
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Defect & Maintenance Timeline', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Event')),
                DataColumn(label: Text('Action')),
                DataColumn(label: Text('Result')),
                DataColumn(label: Text('Technician')),
                DataColumn(label: Text('Work-order ID')),
                DataColumn(label: Text('Resolution')),
              ],
              rows: rows.map((r) => DataRow(cells: r.map((c) => DataCell(Text(c, style: const TextStyle(fontWeight: FontWeight.w700)))).toList())).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _KnowledgeCard extends StatelessWidget {
  const _KnowledgeCard();
  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Documents & Knowledge (RAG integration)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: () {}, child: const Text('Datasheet PDF')),
              OutlinedButton(onPressed: () {}, child: const Text('Cleaning SOP')),
              OutlinedButton(onPressed: () {}, child: const Text('Warranty')),
              OutlinedButton(onPressed: () {}, child: const Text('Troubleshooting')),
            ],
          ),
          const SizedBox(height: 10),
          const TextField(
            decoration: InputDecoration(
              labelText: 'AI query',
              hintText: 'What is safe cleaning method for this panel model?',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFFF8FAFC), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: const Text(
              'Use deionized water and a soft microfiber cloth. Avoid abrasive brushes, strong solvents, and high-pressure jets.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, this.padding = const EdgeInsets.all(12)});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: child,
    );
  }
}

double? _pickReading(Map<String, dynamic> readings, String key) {
  final raw = readings[key];
  if (raw is num) return raw.toDouble();
  if (raw is Map && raw['value'] is num) return (raw['value'] as num).toDouble();
  if (key == 'V1') {
    final v = readings['panel1voltage'];
    if (v is num) return v.toDouble();
    if (v is Map && v['value'] is num) return (v['value'] as num).toDouble();
  }
  if (key == 'P1') {
    final p = readings['panel1power'];
    if (p is num) return p.toDouble();
    if (p is Map && p['value'] is num) return (p['value'] as num).toDouble();
  }
  if (key == 'I') {
    final c = readings['current'];
    if (c is num) return c.toDouble();
    final i1 = readings['panel1current'];
    final i2 = readings['panel2current'];
    final i3 = readings['panel3current'];
    if (i1 is num || i2 is num || i3 is num) {
      final s = (i1 is num ? i1.toDouble().abs() : 0.0) +
          (i2 is num ? i2.toDouble().abs() : 0.0) +
          (i3 is num ? i3.toDouble().abs() : 0.0);
      return s;
    }
  }
  if (key == 'P1' && readings['power'] is Map && (readings['power']['P1'] is num)) {
    return (readings['power']['P1'] as num).toDouble();
  }
  if (key == 'V1' && readings['voltage'] is Map && (readings['voltage']['V1'] is num)) {
    return (readings['voltage']['V1'] as num).toDouble();
  }
  return null;
}

/// Returns true when the recommendation markdown mentions cleaning actions.
bool _shouldTriggerServo(String recommendationsMd) {
  if (recommendationsMd.trim().isEmpty) return false;
  final text = recommendationsMd.toLowerCase();
  return RegExp(r'\bclean(ing)?\b').hasMatch(text) ||
      RegExp(r'\bwipe\b.{0,40}\bsurface\b').hasMatch(text) ||
      RegExp(r'\bremove\b.{0,40}\bdust\b').hasMatch(text);
}

/// Fire-and-forget: move servo to cleaning position, wait, then return to rest.
void _triggerCleaningServo() {
  final onUrl = ApiConfig.getServoUrl(true);
  final offUrl = ApiConfig.getServoUrl(false);
  final delaySeconds = ApiConfig.esp32ServoAutoOffSeconds;

  // Move servo to cleaning position (pos=180)
  http.get(Uri.parse(onUrl)).timeout(const Duration(seconds: 2)).then((_) {
    // After delay, return servo to rest position (pos=0)
    if (delaySeconds > 0) {
      Future.delayed(Duration(seconds: delaySeconds), () {
        http.get(Uri.parse(offUrl)).timeout(const Duration(seconds: 2)).catchError((_) => http.Response('', 500));
      });
    }
  }).catchError((_) {
    // ESP32 unreachable — silently ignore
  });
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.orange.shade800, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w800, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
