import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_config.dart';
import '../data/panel_snapshot_repository.dart';
import '../domain/panel_health_snapshot.dart';
import '../panel_health_markdown.dart';

/// Post–QR scan health view aligned with React `HealthReport.js`: weather, identification,
/// live metrics, **ML diagnosis** (ONNX top‑k), camera, **root cause**, **AI summary**, **recommendations**.
class PanelQrReportPage extends StatefulWidget {
  const PanelQrReportPage({
    super.key,
    required this.panelId,
    this.pollInterval = const Duration(seconds: 5),
  });

  final String panelId;
  final Duration pollInterval;

  @override
  State<PanelQrReportPage> createState() => _PanelQrReportPageState();
}

class _PanelQrReportPageState extends State<PanelQrReportPage> {
  final _repo = PanelSnapshotRepository();
  Timer? _timer;
  PanelHealthSnapshot? _snapshot;
  Object? _lastError;
  bool _loading = true;
  bool _refreshingAi = false;
  int _imgIndex = 0;
  double _cameraZoom = 1;

  @override
  void initState() {
    super.initState();
    _load(forceAi: false);
    _timer = Timer.periodic(widget.pollInterval, (_) => _load(forceAi: false));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({required bool forceAi}) async {
    if (!mounted) return;
    if (forceAi) {
      setState(() => _refreshingAi = true);
    } else if (_snapshot == null) {
      setState(() => _loading = true);
    }
    try {
      final s = await _repo.fetchPanelBundle(widget.panelId, refreshAi: forceAi);
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
    // try common extensions in order; mobile app will attempt to load them from the server
    return [
      '$base/uploads/$panelId.jpeg',
      '$base/uploads/$panelId.jpg',
      '$base/uploads/$panelId.png',
    ];
  }

  Color _statusColor(String status) {
    final u = status.toLowerCase();
    if (u.contains('health')) return const Color(0xFF16A34A);
    if (u.contains('warn')) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  Color _confidenceColor(double pct) {
    if (pct >= 90) return const Color(0xFF16A34A);
    if (pct >= 70) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
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
    final rootMd = pickMarkdownSection(md, const ['root cause analysis', 'root cause']);
    final recMd = pickMarkdownSection(md, const ['recommendations', 'recommended actions', 'recommended action']);
    final clean = s != null && isCleanDefect(s.defect, s.status);
    final rootBody = (rootMd != null && rootMd.isNotEmpty)
        ? rootMd
        : (clean ? defaultRootCauseClean : defaultRootCauseIssue);
    final recBase = (recMd != null && recMd.isNotEmpty)
        ? recMd
        : (md.isNotEmpty ? md : (clean ? defaultRecommendationsClean : defaultRecommendationsIssue));
    final recShort = truncateMarkdownLines(
      containsKbNotFound(md) ? (clean ? defaultRecommendationsClean : defaultRecommendationsIssue) : recBase,
      maxLines: 18,
    );
    var summaryDisplay = summaryMd.isNotEmpty ? summaryMd : '';
    if (summaryDisplay.isEmpty && md.isEmpty && (s?.geminiError == null || s!.geminiError!.isEmpty)) {
      summaryDisplay = '## Summary\n\nRun **Re-run AI** after the backend is configured with Gemini. '
          'Until then, use **ML diagnosis** and **Recommendations** above.';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Panel health · ${widget.panelId}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        actions: [
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
          const SizedBox(width: 4),
        ],
      ),
      body: _loading && s == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(forceAi: false),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_lastError != null && s == null)
                    _ErrorBanner(message: _lastError.toString(), onRetry: () => _load(forceAi: false)),
                  if (_lastError != null && s != null) _OfflineHint(message: _lastError.toString()),
                  if (s != null) ...[
                    _WeatherStrip(weather: s.weatherRaw),
                    const SizedBox(height: 12),
                    _ReportTitleRow(
                      panelId: s.panelId,
                      lastUpdated: s.lastUpdatedSensor,
                      loadingStrip: _refreshingAi,
                    ),
                    if (s.geminiError != null && s.geminiError!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Material(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded, color: Colors.orange.shade800, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  s.geminiError!,
                                  style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w700, height: 1.35),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _PanelIdentificationCard(
                      snapshot: s,
                      statusColor: _statusColor(s.status),
                    ),
                    const SizedBox(height: 12),
                    _MetricsWrap(snapshot: s),
                    const SizedBox(height: 16),
                    Text(
                      'AI visual inspection',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    // If the backend doesn't provide image candidates, try app-only fallback images
                    Builder(builder: (context) {
                      final imageCandidates = s.imageCandidates.isNotEmpty ? s.imageCandidates : _fallbackImageCandidates(s.panelId);
                      return _CameraCard(
                        urls: imageCandidates,
                        index: _imgIndex,
                        zoom: _cameraZoom,
                        panelId: s.panelId,
                        onRotate: () => setState(() {
                          if (imageCandidates.isEmpty) return;
                          _imgIndex = (_imgIndex + 1) % imageCandidates.length;
                        }),
                        onZoomIn: () => setState(() => _cameraZoom = (_cameraZoom + 0.25).clamp(1.0, 2.5)),
                        onZoomOut: () => setState(() => _cameraZoom = (_cameraZoom - 0.25).clamp(1.0, 2.5)),
                        onZoomReset: () => setState(() => _cameraZoom = 1),
                      );
                    }),
                    const SizedBox(height: 12),
                    _MlDiagnosisCard(
                      snapshot: s,
                      confidenceColor: _confidenceColor(s.confidencePercent),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      icon: Icons.account_tree_outlined,
                      iconColor: const Color(0xFF16A34A),
                      title: 'Root cause analysis',
                      chipLabel: 'Probable cause',
                      child: MarkdownBody(data: rootBody),
                    ),
                    if (summaryDisplay.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _SectionCard(
                        icon: Icons.auto_awesome_outlined,
                        iconColor: const Color(0xFF16A34A),
                        title: 'AI summary',
                        child: MarkdownBody(data: summaryDisplay),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      _SectionCard(
                        icon: Icons.auto_awesome_outlined,
                        iconColor: const Color(0xFF94A3B8),
                        title: 'AI summary',
                        child: Text(
                          'No summary text returned. Check Gemini on the server or tap Re-run AI.',
                          style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600, height: 1.4),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _SectionCard(
                      icon: Icons.check_circle_outline,
                      iconColor: const Color(0xFF16A34A),
                      title: 'Recommendations',
                      child: MarkdownBody(data: recShort),
                    ),
                    if (s.suggestion.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _QuickActionLine(suggestion: s.suggestion),
                    ],
                    const SizedBox(height: 14),
                    _TelemetryFooter(snapshot: s),
                  ],
                ],
              ),
            ),
    );
  }
}

class _WeatherStrip extends StatelessWidget {
  const _WeatherStrip({required this.weather});
  final Map<String, dynamic> weather;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, String value) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          ],
        ),
      );
    }

    final city = (weather['city'] ?? 'Wardha').toString();
    final cond = (weather['condition'] ?? '—').toString();
    final tc = weather['temperature_c'];
    final temp = tc != null ? '${(tc is num ? tc.toDouble() : double.tryParse('$tc') ?? 0).toStringAsFixed(1)} °C' : '—';
    final hum = weather['humidity_percent'];
    final hums = hum != null ? '${(hum is num ? hum.round() : int.tryParse('$hum') ?? 0)}%' : '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(children: [
        cell('CITY', city),
        cell('WEATHER', cond),
        cell('TEMP', temp),
        cell('HUMIDITY', hums),
      ]),
    );
  }
}

class _ReportTitleRow extends StatelessWidget {
  const _ReportTitleRow({
    required this.panelId,
    required this.lastUpdated,
    required this.loadingStrip,
  });
  final String panelId;
  final String lastUpdated;
  final bool loadingStrip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Panel health report: $panelId',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, fontSize: 20),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sensors: $lastUpdated',
                style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
        if (loadingStrip) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 3),
        ],
      ],
    );
  }
}

class _PanelIdentificationCard extends StatelessWidget {
  const _PanelIdentificationCard({required this.snapshot, required this.statusColor});
  final PanelHealthSnapshot snapshot;
  final Color statusColor;

  String _operatingLabel() {
    final u = snapshot.status.toLowerCase();
    if (u.contains('health')) return 'Normal';
    if (u.contains('warn')) return 'Warning';
    return 'Fault';
  }

  String _healthLabel() {
    final sc = snapshot.healthScore;
    if (sc >= 90) return 'HEALTHY';
    if (sc >= 75) return 'NEEDS ATTENTION';
    return 'CRITICAL';
  }

  @override
  Widget build(BuildContext context) {
    final sid = snapshot.stringId.isNotEmpty ? snapshot.stringId : '—';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_outlined, color: AppTheme.brandGreen, size: 22),
              const SizedBox(width: 8),
              Text('Panel identification & status', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            ],
          ),
          const Divider(height: 20),
          _kv('Panel ID', snapshot.panelId),
          _kv('String / channel', '$sid · Ch ${snapshot.channelIndex}'),
          if (snapshot.panelAliasScanned != snapshot.panelId) _kv('Scanned as', snapshot.panelAliasScanned),
          _kv('Rated power (expected)', '40 W'),
          _kv('Output vs expected', snapshot.power > 0 ? '${((snapshot.power / 40) * 100).clamp(0, 999).toStringAsFixed(0)}%' : '—'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CURRENT HEALTH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: statusColor)),
                      const SizedBox(height: 4),
                      Text(_healthLabel(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: statusColor)),
                      Text('Score ${snapshot.healthScore}% · ${_operatingLabel()}', style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MAX POWER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey.shade600)),
                      const SizedBox(height: 4),
                      Text('${snapshot.power.toStringAsFixed(2)} W', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      Text('Live channel', style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 118, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF475569), fontSize: 12))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
        ],
      ),
    );
  }
}

class _MetricsWrap extends StatelessWidget {
  const _MetricsWrap({required this.snapshot});
  final PanelHealthSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final n = w >= 520 ? 4 : 2;
        final gap = 8.0;
        final cellW = (w - gap * (n - 1)) / n;
        final temp = snapshot.temperatureC != null ? snapshot.temperatureC!.toStringAsFixed(1) : '—';

        Widget cell(String title, String value, String unit, Color color) {
          return SizedBox(
            width: cellW,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                        const SizedBox(width: 4),
                        Text(unit, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF94A3B8), fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: (double.tryParse(value) ?? 0) / 100,
                      minHeight: 5,
                      color: color,
                      backgroundColor: const Color(0xFFE2E8F0),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            cell('VOLTAGE (VOC)', snapshot.voltage.toStringAsFixed(3), 'V', const Color(0xFF16A34A)),
            cell('CURRENT (ISC)', snapshot.current.toStringAsFixed(3), 'A', const Color(0xFF16A34A)),
            cell('POWER', snapshot.power.toStringAsFixed(2), 'W', const Color(0xFF0EA5E9)),
            cell('TEMPERATURE', temp, '°C', const Color(0xFFF59E0B)),
          ],
        );
      },
    );
  }
}

class _CameraCard extends StatelessWidget {
  const _CameraCard({
    required this.urls,
    required this.index,
    required this.zoom,
    required this.panelId,
    required this.onRotate,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
  });

  final List<String> urls;
  final int index;
  final double zoom;
  final String panelId;
  final VoidCallback onRotate;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;

  @override
  Widget build(BuildContext context) {
    final url = urls.isEmpty ? null : urls[index.clamp(0, urls.length - 1)];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0F172A)),
        color: const Color(0xFF0B1222),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 0),
            child: Row(
              children: [
                const Icon(Icons.photo_camera_outlined, color: Color(0xFF86EFAC), size: 20),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Latest capture / live feed', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                ),
                IconButton(onPressed: onZoomOut, icon: const Icon(Icons.remove, color: Colors.white70, size: 20)),
                IconButton(onPressed: onZoomIn, icon: const Icon(Icons.add, color: Colors.white70, size: 20)),
                IconButton(onPressed: onZoomReset, icon: const Icon(Icons.center_focus_strong, color: Colors.white70, size: 20)),
                TextButton(
                  onPressed: urls.length < 2 ? null : onRotate,
                  child: const Text('Next', style: TextStyle(color: Color(0xFF93C5FD), fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url == null)
                  const Center(child: Icon(Icons.hide_image_outlined, color: Colors.white38, size: 48))
                else
                  Transform.scale(
                    scale: zoom,
                    alignment: Alignment.center,
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      cacheWidth: 960,
                      loadingBuilder: (context, child, prog) {
                        if (prog == null) return child;
                        return const Center(child: CircularProgressIndicator(color: Colors.white54));
                      },
                      errorBuilder: (_, __, ___) => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Image failed — tap Next', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      'Panel: $panelId · Zoom ${zoom.toStringAsFixed(2)}x',
                      style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MlDiagnosisCard extends StatelessWidget {
  const _MlDiagnosisCard({required this.snapshot, required this.confidenceColor});
  final PanelHealthSnapshot snapshot;
  final Color confidenceColor;

  @override
  Widget build(BuildContext context) {
    final pct = snapshot.confidencePercent;
    final onnx = snapshot.onnxModelName.isNotEmpty ? snapshot.onnxModelName : 'ONNX classifier';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined, color: AppTheme.brandGreen.withValues(alpha: 0.95)),
              const SizedBox(width: 8),
              Text('AI diagnosis (ML)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 4),
          Text(onnx, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w700)),
          const Divider(height: 18),
          const Text('DEFECT TYPE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
          const SizedBox(height: 4),
          Text(snapshot.defectDisplay, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 12),
          const Text('CONFIDENCE (primary class)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: (pct / 100).clamp(0, 1),
                    minHeight: 9,
                    color: confidenceColor,
                    backgroundColor: const Color(0xFFE2E8F0),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('${pct.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.w900, color: confidenceColor, fontSize: 15)),
            ],
          ),
          if (snapshot.topPredictions.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('TOP PREDICTIONS (ONNX)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
            const SizedBox(height: 8),
            ...snapshot.topPredictions.map((p) {
              if (p.label.isEmpty) return const SizedBox.shrink();
              final sp = p.scorePercent.clamp(0, 100);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                        Text('${sp.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.grey.shade700)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (sp / 100).clamp(0, 1),
                        minHeight: 6,
                        color: const Color(0xFF0EA5E9),
                        backgroundColor: const Color(0xFFE2E8F0),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 10),
          Text(
            'Use the Recommendations section below for technician actions.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
    this.chipLabel,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;
  final String? chipLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
            ],
          ),
          if (chipLabel != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(99)),
              child: Text(chipLabel!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF166534))),
            ),
          ],
          const SizedBox(height: 10),
          DefaultTextStyle.merge(
            style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600, height: 1.45),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _QuickActionLine extends StatelessWidget {
  const _QuickActionLine({required this.suggestion});
  final String suggestion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.tips_and_updates_outlined, color: Colors.blue.shade800, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quick action', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.blue.shade900)),
                const SizedBox(height: 4),
                Text(suggestion, style: TextStyle(fontWeight: FontWeight.w700, color: Colors.blueGrey.shade800, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TelemetryFooter extends StatelessWidget {
  const _TelemetryFooter({required this.snapshot});
  final PanelHealthSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final src = snapshot.awsConfigured ? (snapshot.readingsSource ?? 'aws') : 'fallback';
    return Text(
      'Telemetry: $src · AI snapshot: ${snapshot.lastUpdatedAi}',
      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(message, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF9F1239))),
              const SizedBox(height: 10),
              FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.cloud_sync_rounded), label: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineHint extends StatelessWidget {
  const _OfflineHint({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: Color(0xFF64748B), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Refresh failed (showing last data): $message',
              style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
