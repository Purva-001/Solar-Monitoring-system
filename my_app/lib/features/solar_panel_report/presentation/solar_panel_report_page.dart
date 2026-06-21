import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../app/theme/app_theme.dart';
import '../../camera/presentation/camera_feed_card.dart';
import '../../camera/state/camera_feed_cubit.dart';
import '../../health_report/state/health_report_cubit.dart';
import '../../health_report/state/health_report_state.dart';

class SolarPanelReportPage extends StatelessWidget {
  const SolarPanelReportPage({super.key});

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

        final report = (state as HealthReportLoaded).report;

        final allMarkdown = report.healthReportMarkdown.toString().trim();
        final summaryMd = (report.aiSummaryMarkdown?.toString().trim().isNotEmpty ?? false)
            ? report.aiSummaryMarkdown.toString()
            : (_pickMarkdownSection(allMarkdown, const ['summary']) ?? allMarkdown);
        final rootCauseMd = (report.aiRootCauseMarkdown?.toString().trim().isNotEmpty ?? false)
            ? report.aiRootCauseMarkdown.toString()
            : (_pickMarkdownSection(allMarkdown, const ['root cause analysis', 'root cause']) ?? '');
        final recommendationsMd = (report.aiRecommendationsMarkdown?.toString().trim().isNotEmpty ?? false)
            ? report.aiRecommendationsMarkdown.toString()
            : (_pickMarkdownSection(allMarkdown, const ['recommendations', 'recommended actions']) ?? '');

        final w = MediaQuery.sizeOf(context).width;
        final isWide = w >= 1050;

        return Container(
          color: const Color(0xFFEFF6FF),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(
                panelId: report.panelId,
                onRefresh: () => context.read<HealthReportCubit>().load(panelId: report.panelId),
              ),
              const SizedBox(height: 12),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _PanelIdentificationCard(report: report)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          BlocProvider(
                            create: (_) => CameraFeedCubit()..start(),
                            child: CameraFeedCard(panelId: report.panelId),
                          ),
                          const SizedBox(height: 12),
                          _AiDiagnosisCard(report: report),
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                _PanelIdentificationCard(report: report),
                const SizedBox(height: 12),
                BlocProvider(
                  create: (_) => CameraFeedCubit()..start(),
                  child: CameraFeedCard(panelId: report.panelId),
                ),
                const SizedBox(height: 12),
                _AiDiagnosisCard(report: report),
              ],
              const SizedBox(height: 12),
              _AiSummaryCard(markdown: summaryMd),
              const SizedBox(height: 12),
              _RootCauseCard(report: report),
              const SizedBox(height: 12),
              _RecommendationsCard(markdown: recommendationsMd),
            ],
          ),
        );
      },
    );
  }
}

class _AiSummaryCard extends StatelessWidget {
  const _AiSummaryCard({required this.markdown});

  final String markdown;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, color: AppTheme.brandBlue),
                const SizedBox(width: 8),
                Text('AI Summary', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            if (markdown.trim().isEmpty)
              const Text('No AI content returned by API.', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800))
            else
              MarkdownBody(data: markdown),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.panelId, required this.onRefresh});

  final String panelId;
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
              child: const Icon(Icons.article_outlined, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Solar Panel Report', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _Pill(label: 'Panel: $panelId', bg: const Color(0xFFDCFCE7), fg: const Color(0xFF166534)),
                    ],
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandBlue,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
            ),
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

class _PanelIdentificationCard extends StatelessWidget {
  const _PanelIdentificationCard({required this.report});

  final dynamic report;

  @override
  Widget build(BuildContext context) {
    final maxPower = [report.sensorData.p1.value, report.sensorData.p2.value, report.sensorData.p3.value]
        .map((e) => (e as num).toDouble())
        .fold<double>(0, (p, n) => n.abs() > p ? n.abs() : p);

    final statusLower = (report.status as String).toLowerCase();
    final isHealthy = statusLower.contains('normal') || statusLower.contains('healthy');

    final statusBg = isHealthy ? const Color(0xFFDCFCE7) : const Color(0xFFFFEDD5);
    final statusFg = isHealthy ? const Color(0xFF166534) : const Color(0xFF9A3412);

    Widget row(String k, String v) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155)))),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                v,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      );
    }

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
            Row(
              children: [
                const Icon(Icons.verified_outlined, color: AppTheme.brandGreen),
                const SizedBox(width: 8),
                Text('Panel Identification & Status', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(14)),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                color: const Color(0xFFF8FAFC),
              ),
              child: Column(
                children: [
                  row('Panel ID', report.panelId.toString()),
                  const Divider(height: 1),
                  row('Operating State', report.status.toString()),
                  const Divider(height: 1),
                  row('Max Power Output', '${maxPower.toStringAsFixed(2)} W'),
                  const Divider(height: 1),
                  row('Power Trigger', report.powerTrigger.status.toString()),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Pill(label: isHealthy ? 'HEALTHY' : 'ATTENTION', bg: statusBg, fg: statusFg),
                _Pill(label: report.powerTrigger.message.toString(), bg: const Color(0xFFFFEDD5), fg: const Color(0xFF9A3412)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AiDiagnosisCard extends StatelessWidget {
  const _AiDiagnosisCard({required this.report});

  final dynamic report;

  @override
  Widget build(BuildContext context) {
    final defect = report.defectAnalysis.defect.toString().trim().isEmpty ? 'None' : report.defectAnalysis.defect.toString();
    final conf = (report.defectAnalysis.confidence as num).toDouble().clamp(0.0, 1.0);
    final confPct = (conf * 100);

    Color bar;
    if (confPct >= 80) {
      bar = const Color(0xFFF59E0B);
    } else {
      bar = AppTheme.brandBlue;
    }

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
            Row(
              children: [
                const Icon(Icons.psychology_alt_outlined, color: AppTheme.brandBlue),
                const SizedBox(width: 8),
                Text('AI Diagnosis', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            row('Defect Type', defect),
            const SizedBox(height: 10),
            const Text('Confidence', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155))),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              child: LinearProgressIndicator(
                value: conf.toDouble(),
                minHeight: 10,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(bar),
              ),
            ),
            const SizedBox(height: 6),
            Text('${confPct.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  Widget row(String k, String v) {
    return Row(
      children: [
        Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF334155)))),
        const SizedBox(width: 10),
        Expanded(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900))),
      ],
    );
  }
}

class _RootCauseCard extends StatelessWidget {
  const _RootCauseCard({required this.report});

  final dynamic report;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_tree_outlined, color: AppTheme.brandGreen),
                const SizedBox(width: 8),
                Text('Root Cause Analysis', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            MarkdownBody(
              data: md.trim().isNotEmpty ? md : 'No root cause returned by AI.',
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendationsCard extends StatelessWidget {
  const _RecommendationsCard({required this.markdown});

  final String markdown;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.build_outlined, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Text('Recommendations', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            if (markdown.trim().isEmpty)
              const Text('No recommendations returned by AI.', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800))
            else
              MarkdownBody(data: markdown),
          ],
        ),
      ),
    );
  }
}

String? _pickMarkdownSection(String markdown, List<String> titles) {
  if (markdown.trim().isEmpty) return null;
  final lowerTitles = titles.map((e) => e.toLowerCase().trim()).toSet();
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  int? start;
  int? level;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final match = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line);
    if (match == null) continue;
    final headingLevel = match.group(1)!.length;
    final title = match.group(2)!.trim().toLowerCase();
    if (start == null && lowerTitles.contains(title)) {
      start = i;
      level = headingLevel;
      continue;
    }
    if (start != null && headingLevel <= (level ?? 6)) {
      return lines.sublist(start, i).join('\n').trim();
    }
  }
  if (start != null) return lines.sublist(start).join('\n').trim();
  return null;
}
