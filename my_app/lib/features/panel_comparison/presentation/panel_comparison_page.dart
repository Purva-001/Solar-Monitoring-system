import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/metric_card.dart';
import '../state/panel_info_cubit.dart';
import '../state/panel_info_state.dart';

class PanelComparisonPage extends StatelessWidget {
  const PanelComparisonPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PanelInfoCubit()..load(),
      child: BlocBuilder<PanelInfoCubit, PanelInfoState>(
        builder: (context, state) {
          if (state is PanelInfoLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is PanelInfoError) {
            return Center(child: Text(state.message));
          }

          final info = (state as PanelInfoLoaded).info;
          final isCritical = info.requiresAnalysis;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(
                panelId: info.panelId,
                message: info.message,
                isCritical: isCritical,
                onRefresh: () => context.read<PanelInfoCubit>().load(panelId: info.panelId),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: MediaQuery.sizeOf(context).width >= 900 ? 3 : 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                children: [
                  MetricCard(title: 'V1', value: info.voltageV1.toStringAsFixed(2), unit: 'V', accent: AppTheme.brandBlue),
                  MetricCard(title: 'V2', value: info.voltageV2.toStringAsFixed(2), unit: 'V', accent: AppTheme.brandBlue),
                  MetricCard(title: 'V3', value: info.voltageV3.toStringAsFixed(2), unit: 'V', accent: AppTheme.brandBlue),
                  MetricCard(title: 'P1', value: info.powerP1.toStringAsFixed(2), unit: 'W', accent: Colors.orange),
                  MetricCard(title: 'P2', value: info.powerP2.toStringAsFixed(2), unit: 'W', accent: AppTheme.brandGreen),
                  MetricCard(title: 'P3', value: info.powerP3.toStringAsFixed(2), unit: 'W', accent: AppTheme.brandGreen),
                  MetricCard(title: 'I', value: info.currentI.toStringAsFixed(1), unit: 'mA', accent: AppTheme.brandBlue),
                ],
              ),
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
                      Text('Panel Comparison', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 10),
                      Text(
                        isCritical ? 'CRITICAL: Analysis required' : 'Normal: No analysis required',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: isCritical ? const Color(0xFFDC2626) : const Color(0xFF166534),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This page uses /api/panel/info like the website to compare current readings and flag abnormal behavior.',
                        style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.panelId, required this.message, required this.isCritical, required this.onRefresh});

  final String panelId;
  final String message;
  final bool isCritical;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final bg = isCritical ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7);
    final fg = isCritical ? const Color(0xFF991B1B) : const Color(0xFF166534);

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
              child: const Icon(Icons.compare_outlined, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Panel Comparison', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _Pill(label: 'Panel: $panelId', bg: const Color(0xFFE0F2FE), fg: const Color(0xFF075985)),
                      _Pill(label: isCritical ? 'Critical' : 'Healthy', bg: bg, fg: fg),
                      if (message.isNotEmpty) _Pill(label: message, bg: const Color(0xFFFFEDD5), fg: const Color(0xFF9A3412)),
                    ],
                  ),
                ],
              ),
            ),
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
