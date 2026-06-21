import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_config.dart';
import '../domain/maintenance_models.dart';
import '../state/maintenance_comparison_cubit.dart';
import '../state/maintenance_comparison_state.dart';

class MaintenanceComparisonPage extends StatefulWidget {
  const MaintenanceComparisonPage({super.key});

  @override
  State<MaintenanceComparisonPage> createState() => _MaintenanceComparisonPageState();
}

class _MaintenanceComparisonPageState extends State<MaintenanceComparisonPage> {
  final TextEditingController _panelIdController = TextEditingController(text: 'PL01-B02-INV03-STR05-P01');

  @override
  void dispose() {
    _panelIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MaintenanceComparisonCubit, MaintenanceComparisonState>(
      builder: (context, state) {
        if (state is MaintenanceComparisonLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is MaintenanceComparisonError) {
          return Center(child: Text(state.message));
        }

        final data = state is MaintenanceComparisonRunning ? state.data : (state as MaintenanceComparisonLoaded).data;
        final running = state is MaintenanceComparisonRunning;
        final countdown = running ? state.countdownSeconds : 0;
        final effectivePanelId = _panelIdController.text.trim().isEmpty ? data.panelId : _panelIdController.text.trim();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Header(
              controller: _panelIdController,
              panelId: effectivePanelId,
              channelIdx: data.channelIdx,
              completedAtIso: data.completedAtIso,
              running: running,
              onRefresh: () => context.read<MaintenanceComparisonCubit>().load(panelId: effectivePanelId),
              onRun: running ? null : () => context.read<MaintenanceComparisonCubit>().runWithStabilization(panelId: effectivePanelId),
            ),
            const SizedBox(height: 12),
            if (running)
              _CountdownCard(countdown: countdown)
            else
              const SizedBox.shrink(),
            if (running) const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final mobile = constraints.maxWidth < 900;
                if (mobile) {
                  return Column(
                    children: [
                      _BeforeCard(data: data),
                      const SizedBox(height: 12),
                      _AfterCard(data: data),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: _BeforeCard(data: data)),
                    const SizedBox(width: 12),
                    Expanded(child: _AfterCard(data: data)),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            _SummaryCard(data: data),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.panelId,
    required this.channelIdx,
    required this.running,
    required this.onRefresh,
    required this.onRun,
    this.completedAtIso,
  });

  final TextEditingController controller;
  final String panelId;
  final int channelIdx;
  final String? completedAtIso;
  final bool running;
  final VoidCallback onRefresh;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    Widget pill({required String label, required Color bg, required Color fg}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.all(Radius.circular(999))),
        child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w900)),
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
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppTheme.brandBlue,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: const Icon(Icons.build_circle_outlined, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Maintenance Comparison Analysis', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 320,
                        child: TextField(
                          controller: controller,
                          decoration: const InputDecoration(
                            labelText: 'Panel ID',
                            hintText: 'PL01-B02-INV03-STR05-P01',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      pill(label: 'Channel: P$channelIdx', bg: const Color(0xFFE0F2FE), fg: const Color(0xFF075985)),
                      if (completedAtIso != null && completedAtIso!.trim().isNotEmpty)
                        pill(label: 'Completed: ${completedAtIso!.trim()}', bg: const Color(0xFFE0F2FE), fg: const Color(0xFF075985)),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              onPressed: onRun,
              icon: const Icon(Icons.play_arrow),
              label: Text(running ? 'Running...' : 'Run'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandGreen,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.countdown});
  final int countdown;

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
            Text(
              'Running post-clean comparison... Stabilizing (${countdown}s)',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: ((30 - countdown) / 30).clamp(0.0, 1.0),
              minHeight: 10,
              borderRadius: const BorderRadius.all(Radius.circular(999)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeforeCard extends StatelessWidget {
  const _BeforeCard({required this.data});

  final MaintenanceComparison data;

  @override
  Widget build(BuildContext context) {
    return _SideCard(
      title: 'Before Cleaning',
      imageUrl: data.beforeImageUrl,
      fallbackImageUrl: _captureImageUrl('image1.jpg'),
      statusLabel: data.beforeStatus,
      statusBg: const Color(0xFFFEF3C7),
      statusFg: const Color(0xFF92400E),
      powerW: data.beforePowerW,
      deviationPct: data.beforeDeviationPct,
      powerAccent: Colors.orange,
      caption: null,
    );
  }
}

class _AfterCard extends StatelessWidget {
  const _AfterCard({required this.data});

  final MaintenanceComparison data;

  @override
  Widget build(BuildContext context) {
    return _SideCard(
      title: 'After Cleaning',
      imageUrl: data.afterImageUrl,
      fallbackImageUrl: _captureImageUrl('image2.jpg'),
      statusLabel: data.afterStatus,
      statusBg: const Color(0xFFDCFCE7),
      statusFg: const Color(0xFF166534),
      powerW: data.afterPowerW,
      deviationPct: data.afterDeviationPct,
      powerAccent: AppTheme.brandGreen,
      caption: (data.afterPowerWStored == null && data.liveChannelPowerW != null)
          ? 'Live reading from solar API (channel P${data.channelIdx})'
          : null,
    );
  }
}

class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.title,
    required this.imageUrl,
    required this.fallbackImageUrl,
    required this.statusLabel,
    required this.statusBg,
    required this.statusFg,
    required this.powerW,
    required this.deviationPct,
    required this.powerAccent,
    required this.caption,
  });

  final String title;
  final String? imageUrl;
  final String fallbackImageUrl;
  final String statusLabel;
  final Color statusBg;
  final Color statusFg;
  final double? powerW;
  final double deviationPct;
  final Color powerAccent;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

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
            const SizedBox(height: 12),
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ImageBox(imageUrl: imageUrl, fallbackImageUrl: fallbackImageUrl),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StatsBox(
                      powerW: powerW,
                      powerAccent: powerAccent,
                      statusLabel: statusLabel,
                      statusBg: statusBg,
                      statusFg: statusFg,
                      deviationPct: deviationPct,
                      caption: caption,
                    ),
                  ),
                ],
              )
            else ...[
              _ImageBox(imageUrl: imageUrl, fallbackImageUrl: fallbackImageUrl),
              const SizedBox(height: 12),
              _StatsBox(
                powerW: powerW,
                powerAccent: powerAccent,
                statusLabel: statusLabel,
                statusBg: statusBg,
                statusFg: statusFg,
                deviationPct: deviationPct,
                caption: caption,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImageBox extends StatelessWidget {
  const _ImageBox({required this.imageUrl, required this.fallbackImageUrl});
  final String? imageUrl;
  final String fallbackImageUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Image', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Container(
          height: 240,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            color: Colors.white,
          ),
          alignment: Alignment.center,
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            child: _ImageWithFallback(
              primaryUrl: imageUrl,
              fallbackUrl: fallbackImageUrl,
              secondaryFallbackUrl: _cameraFeedUrl(),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImageWithFallback extends StatefulWidget {
  const _ImageWithFallback({
    required this.primaryUrl,
    required this.fallbackUrl,
    required this.secondaryFallbackUrl,
  });

  final String? primaryUrl;
  final String fallbackUrl;
  final String secondaryFallbackUrl;

  @override
  State<_ImageWithFallback> createState() => _ImageWithFallbackState();
}

class _ImageWithFallbackState extends State<_ImageWithFallback> {
  int _fallbackStep = 0;

  @override
  Widget build(BuildContext context) {
    final candidates = <String>[
      if (widget.primaryUrl != null && widget.primaryUrl!.isNotEmpty) widget.primaryUrl!,
      widget.fallbackUrl,
      widget.secondaryFallbackUrl,
    ];
    final idx = _fallbackStep.clamp(0, candidates.length - 1);
    final url = candidates[idx];
    return Image.network(
      url,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (context, _, __) {
        if (_fallbackStep < candidates.length - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _fallbackStep += 1);
          });
          return const SizedBox.shrink();
        }
        return const Center(
          child: Text(
            'No image',
            style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF64748B)),
          ),
        );
      },
    );
  }
}

class _StatsBox extends StatelessWidget {
  const _StatsBox({
    required this.powerW,
    required this.powerAccent,
    required this.statusLabel,
    required this.statusBg,
    required this.statusFg,
    required this.deviationPct,
    required this.caption,
  });

  final double? powerW;
  final Color powerAccent;
  final String statusLabel;
  final Color statusBg;
  final Color statusFg;
  final double deviationPct;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Power (W)', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(
          powerW == null ? '—' : powerW!.toStringAsFixed(2),
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 34, color: powerAccent),
        ),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(caption!, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 14),
        const Text('Health Status', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: statusBg, borderRadius: const BorderRadius.all(Radius.circular(999))),
          child: Text(statusLabel, style: TextStyle(color: statusFg, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 16),
        const Text('Deviation %', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text('${deviationPct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});

  final MaintenanceComparison data;

  @override
  Widget build(BuildContext context) {
    final imp = data.improvementPct;
    final resolution = imp > 10
        ? 'Resolved'
        : imp >= 3
            ? 'Monitor'
            : 'Escalate';
    final resolutionColor = imp > 10
        ? AppTheme.brandGreen
        : imp >= 3
            ? Colors.orange
            : Colors.redAccent;
    final completed = data.completedAtIso;
    final progress = imp.isFinite ? imp.clamp(0, 100) / 100.0 : 0.0;
    final pb = data.beforePowerW;
    final pa = data.afterPowerW;
    final diffW = (pb != null && pa != null) ? (pa - pb) : null;

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
            Text('Comparison Summary', style: Theme.of(context).textTheme.titleMedium),
            if (completed != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: const BoxDecoration(color: Color(0xFFE0F2FE), borderRadius: BorderRadius.all(Radius.circular(999))),
                child: Text(
                  'Completed: ${DateTime.tryParse(completed)?.toLocal().toString().split('.').first ?? completed}',
                  style: const TextStyle(color: Color(0xFF075985), fontWeight: FontWeight.w900),
                ),
              ),
            ],
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, c) {
                final isWide = c.maxWidth >= 900;
                final children = <Widget>[
                  Expanded(
                    child: _SummaryMetric(
                      title: 'Power Difference (W)',
                      value: diffW == null ? '—' : diffW.toStringAsFixed(2),
                    ),
                  ),
                  const SizedBox(width: 12, height: 12),
                  Expanded(
                    child: _ImprovementMetric(
                      improvementPct: imp,
                      progress: progress,
                    ),
                  ),
                  const SizedBox(width: 12, height: 12),
                  Expanded(
                    child: _ResolutionMetric(
                      resolution: resolution,
                      color: resolutionColor,
                    ),
                  ),
                ];

                if (isWide) {
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _SummaryMetric(title: 'Power Difference (W)', value: diffW == null ? '—' : diffW.toStringAsFixed(2)),
                  const SizedBox(height: 12),
                  _ImprovementMetric(improvementPct: imp, progress: progress),
                  const SizedBox(height: 12),
                  _ResolutionMetric(resolution: resolution, color: resolutionColor),
                ]);
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Energy Recovered (Wh): ', style: TextStyle(fontWeight: FontWeight.w900)),
                Text(data.energyRecoveredWh.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 34)),
        ],
      ),
    );
  }
}

class _ImprovementMetric extends StatelessWidget {
  const _ImprovementMetric({required this.improvementPct, required this.progress});
  final double improvementPct;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Improvement %', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
          const SizedBox(height: 8),
          Text('${improvementPct.toStringAsFixed(2)}%', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 34)),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            backgroundColor: const Color(0xFFE5E7EB),
            color: AppTheme.brandGreen,
          ),
        ],
      ),
    );
  }
}

class _ResolutionMetric extends StatelessWidget {
  const _ResolutionMetric({required this.resolution, required this.color});
  final String resolution;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Verification Status', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: const BorderRadius.all(Radius.circular(999))),
            child: Text(resolution, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

String _captureImageUrl(String fileName) {
  final base = Uri.parse(ApiConfig.fastApiBaseUrl);
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: '/captures/$fileName',
  ).toString();
}

String _cameraFeedUrl() {
  final base = Uri.parse(ApiConfig.fastApiBaseUrl);
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: '/api/camera/feed',
    queryParameters: {'t': DateTime.now().millisecondsSinceEpoch.toString()},
  ).toString();
}
