import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/home_shell.dart';
import '../../../core/api/api_config.dart';
import '../data/panel_snapshot_repository.dart';
import '../domain/panel_health_snapshot.dart';
import '../panel_health_markdown.dart';

/// A lightweight page that shows only the GenAI analysis parts (summary, recommendations, suggestion).
class GenaiAnalysisPage extends StatefulWidget {
  const GenaiAnalysisPage({super.key, required this.panelId});

  final String? panelId;

  @override
  State<GenaiAnalysisPage> createState() => _GenaiAnalysisPageState();
}

class _GenaiAnalysisPageState extends State<GenaiAnalysisPage> {
  final _repo = PanelSnapshotRepository();
  PanelHealthSnapshot? _snapshot;
  Object? _lastError;
  bool _loading = true;
  bool _refreshingAi = false;
  int _imgIndex = 0;
  double _cameraZoom = 1.0;

  @override
  void initState() {
    super.initState();
    if (widget.panelId != null && widget.panelId!.isNotEmpty) _load(forceAi: false);
  }

  Future<void> _load({required bool forceAi}) async {
    if (!mounted) return;
    if (forceAi) setState(() => _refreshingAi = true);
    else if (_snapshot == null) setState(() => _loading = true);

    final pid = widget.panelId;
    if (pid == null || pid.isEmpty) {
      setState(() {
        _lastError = 'No panel selected';
        _loading = false;
        _refreshingAi = false;
      });
      return;
    }

    try {
      final s = await _repo.fetchPanelBundle(pid, refreshAi: forceAi);
      if (!mounted) return;
      setState(() {
        _snapshot = s;
        _lastError = null;
        _loading = false;
        _refreshingAi = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastError = e;
        _loading = false;
        _refreshingAi = false;
      });
    }
  }

  List<String> _fallbackImageCandidates(String panelId) {
    final base = ApiConfig.effectiveBaseUrl;
    return [
      '$base/uploads/$panelId.jpeg',
      '$base/uploads/$panelId.jpg',
      '$base/uploads/$panelId.png',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = _snapshot;
    final md = (s?.healthReportMarkdown ?? '').trim();
    final defectLabel = s?.defectDisplay ?? '—';
    final summaryMd = sanitizeSummaryMarkdown(
      pickMarkdownSection(md, const ['summary']) ?? (md.isNotEmpty ? md : null),
      defectType: defectLabel,
    );
    final recMd = pickMarkdownSection(md, const ['recommendations', 'recommended actions', 'recommended action']);
    final rootMd = pickMarkdownSection(md, const ['root cause analysis', 'root cause']);
    final clean = s != null && isCleanDefect(s!.defect, s.status);
    final rootBody = (rootMd != null && rootMd.isNotEmpty) ? rootMd : (clean ? defaultRootCauseClean : defaultRootCauseIssue);
    final recBase = (recMd != null && recMd.isNotEmpty)
        ? recMd
        : (md.isNotEmpty ? md : (clean ? defaultRecommendationsClean : defaultRecommendationsIssue));
    final recShort = truncateMarkdownLines(
      containsKbNotFound(md) ? (clean ? defaultRecommendationsClean : defaultRecommendationsIssue) : recBase,
      maxLines: 200,
    );

    var summaryDisplay = summaryMd.isNotEmpty ? summaryMd : '';
    if (summaryDisplay.isEmpty && md.isEmpty && (s?.geminiError == null || s!.geminiError!.isEmpty)) {
      summaryDisplay = '## Summary\n\nRun **Re-run AI** after the backend is configured with Gemini. Until then, use Recommendations.';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('GenAI analysis · ${widget.panelId}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Open QR Scan',
            onPressed: () => context.read<HomeShellCubit>().setIndex(1),
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            tooltip: 'Refresh data',
            onPressed: () => _load(forceAi: false),
            icon: const Icon(Icons.refresh_rounded),
          ),
          TextButton(
            onPressed: _refreshingAi ? null : () => _load(forceAi: true),
            child: _refreshingAi
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Re-run AI', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading && s == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(forceAi: false),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
                children: [
                  if (_lastError != null && s == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Material(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(_lastError.toString(), style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF9F1239))),
                              const SizedBox(height: 10),
                              FilledButton.icon(onPressed: () => _load(forceAi: false), icon: const Icon(Icons.cloud_sync_rounded), label: const Text('Retry')),
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (s != null) ...[
                    const SizedBox(height: 6),
                    Text('Gen AI analysis', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),

                    // 1) AI visual inspection
                    Text('AI visual inspection', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Builder(builder: (context) {
                      final imageCandidates = s.imageCandidates.isNotEmpty ? s.imageCandidates : _fallbackImageCandidates(s.panelId);
                      final url = imageCandidates.isEmpty ? null : imageCandidates[_imgIndex.clamp(0, imageCandidates.length - 1)];
                      return _CameraPreviewCard(
                        url: url,
                        zoom: _cameraZoom,
                        panelId: s.panelId,
                        hasMultiple: imageCandidates.length > 1,
                        onRotate: () => setState(() {
                          if (imageCandidates.isEmpty) return;
                          _imgIndex = (_imgIndex + 1) % imageCandidates.length;
                        }),
                        onZoomIn: () => setState(() => _cameraZoom = (_cameraZoom + 0.25).clamp(1.0, 2.5)),
                        onZoomOut: () => setState(() => _cameraZoom = (_cameraZoom - 0.25).clamp(1.0, 2.5)),
                        onZoomReset: () => setState(() => _cameraZoom = 1.0),
                      );
                    }),
                    const SizedBox(height: 12),

                    // 2) ML model output
                    _MlCard(snapshot: s),
                    const SizedBox(height: 12),

                    // 3) Probable root cause
                    _SimpleSectionCard(
                      icon: Icons.account_tree_outlined,
                      iconColor: const Color(0xFF16A34A),
                      title: 'Probable root cause',
                      child: MarkdownBody(data: rootBody),
                    ),
                    const SizedBox(height: 12),

                    // 4) Summary
                    _SimpleSectionCard(
                      icon: Icons.auto_awesome_outlined,
                      iconColor: const Color(0xFF16A34A),
                      title: 'AI summary',
                      child: MarkdownBody(data: summaryDisplay),
                    ),
                    const SizedBox(height: 12),

                    // 5) Recommendations
                    _SimpleSectionCard(
                      icon: Icons.check_circle_outline,
                      iconColor: const Color(0xFF16A34A),
                      title: 'Recommendations',
                      child: MarkdownBody(data: recShort),
                    ),
                    const SizedBox(height: 12),
                    if (s.suggestion.isNotEmpty) ...[
                      _SimpleSectionCard(
                        icon: Icons.tips_and_updates_outlined,
                        iconColor: const Color(0xFF0369A1),
                        title: 'Suggestion',
                        child: Text(s.suggestion, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

class _SimpleSectionCard extends StatelessWidget {
  const _SimpleSectionCard({required this.icon, required this.iconColor, required this.title, required this.child});

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: iconColor, size: 22), const SizedBox(width: 8), Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)))]),
        const SizedBox(height: 10),
        DefaultTextStyle.merge(style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600, height: 1.45), child: child),
      ]),
    );
  }
}

class _CameraPreviewCard extends StatelessWidget {
  const _CameraPreviewCard({required this.url, required this.zoom, required this.panelId, required this.hasMultiple, required this.onRotate, required this.onZoomIn, required this.onZoomOut, required this.onZoomReset});

  final String? url;
  final double zoom;
  final String panelId;
  final bool hasMultiple;
  final VoidCallback onRotate;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFF0B1222)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 0),
          child: Row(children: [
            const Icon(Icons.photo_camera_outlined, color: Color(0xFF86EFAC), size: 20),
            const SizedBox(width: 6),
            const Expanded(child: Text('Latest capture', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13))),
            IconButton(onPressed: onZoomOut, icon: const Icon(Icons.remove, color: Colors.white70, size: 20)),
            IconButton(onPressed: onZoomIn, icon: const Icon(Icons.add, color: Colors.white70, size: 20)),
            IconButton(onPressed: onZoomReset, icon: const Icon(Icons.center_focus_strong, color: Colors.white70, size: 20)),
            TextButton(onPressed: hasMultiple ? onRotate : null, child: const Text('Next', style: TextStyle(color: Color(0xFF93C5FD), fontWeight: FontWeight.w800))),
          ]),
        ),
        AspectRatio(
          aspectRatio: 16 / 10,
          child: Stack(fit: StackFit.expand, children: [
            if (url == null)
              const Center(child: Icon(Icons.hide_image_outlined, color: Colors.white38, size: 48))
            else
              Transform.scale(
                scale: zoom,
                alignment: Alignment.center,
                child: Image.network(
                  url!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  cacheWidth: 960,
                  loadingBuilder: (context, child, prog) {
                    if (prog == null) return child;
                    return const Center(child: CircularProgressIndicator(color: Colors.white54));
                  },
                  errorBuilder: (_, __, ___) => const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Image failed — tap Next', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700), textAlign: TextAlign.center))),
                ),
              ),
            Positioned(
              left: 10,
              bottom: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white24)),
                child: Text('Panel: $panelId · Zoom ${zoom.toStringAsFixed(2)}x', style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _MlCard extends StatelessWidget {
  const _MlCard({required this.snapshot});
  final PanelHealthSnapshot snapshot;

  Color _confidenceColor(double pct) {
    if (pct >= 90) return const Color(0xFF16A34A);
    if (pct >= 70) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final pct = snapshot.confidencePercent;
    final onnx = snapshot.onnxModelName.isNotEmpty ? snapshot.onnxModelName : 'ONNX classifier';
    final color = _confidenceColor(pct);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.psychology_outlined, color: AppTheme.brandGreen.withValues(alpha: 0.95)), const SizedBox(width: 8), Text('AI diagnosis (ML)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900))]),
        const SizedBox(height: 6),
        Text(onnx, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w700)),
        const Divider(height: 18),
        const Text('DEFECT TYPE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
        const SizedBox(height: 4),
        Text(snapshot.defectDisplay, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 12),
        const Text('CONFIDENCE (primary class)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: (pct / 100).clamp(0, 1), minHeight: 9, color: color, backgroundColor: const Color(0xFFE2E8F0)))),
          const SizedBox(width: 10),
          Text('${pct.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 15)),
        ]),
        if (snapshot.topPredictions.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('TOP PREDICTIONS (ONNX)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
          const SizedBox(height: 8),
          ...snapshot.topPredictions.map((p) {
            if (p.label.isEmpty) return const SizedBox.shrink();
            final sp = p.scorePercent.clamp(0, 100);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))), Text('${sp.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.grey.shade700))]),
                const SizedBox(height: 4),
                ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: (sp / 100).clamp(0, 1), minHeight: 6, color: const Color(0xFF0EA5E9), backgroundColor: const Color(0xFFE2E8F0))),
              ]),
            );
          }).toList(),
        ],
        const SizedBox(height: 10),
        Text('Use the Recommendations section below for technician actions.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600, height: 1.4)),
      ]),
    );
  }
}
