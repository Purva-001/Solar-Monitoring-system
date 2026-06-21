import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_config.dart';
import '../../panel_snapshot/presentation/genai_analysis_page.dart';

/// Comprehensive Health Report Dashboard
/// Shows overall system health, panel-by-panel status, and recommendations
class HealthReportPage extends StatefulWidget {
  const HealthReportPage({super.key, this.panelId});

  final String? panelId;

  @override
  State<HealthReportPage> createState() => _HealthReportPageState();
}

class _HealthReportPageState extends State<HealthReportPage> {
  late Future<_HealthReportData> _healthDataFuture;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    if (widget.panelId == null || widget.panelId!.isEmpty) {
      _loadHealthData();
    }
  }

  void _loadHealthData() {
    _healthDataFuture = _fetchHealthReportData();
  }

  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      _loadHealthData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Health data refreshed'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<_HealthReportData> _fetchHealthReportData() async {
    try {
      // Simulate API calls - replace with real endpoints
      final healthMetrics = await _fetchHealthMetrics();
      final panelDetails = await _fetchPanelDetails();
      final recommendations = await _fetchRecommendations();

      return _HealthReportData(
        metrics: healthMetrics,
        panels: panelDetails,
        recommendations: recommendations,
      );
    } catch (e) {
      throw Exception('Failed to load health data: $e');
    }
  }

  Future<_HealthMetrics> _fetchHealthMetrics() async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.getHealthMetricsUrl()),
        headers: {'Accept': 'application/json'},
      ).timeout(Duration(seconds: ApiConfig.httpRequestTimeoutSeconds));
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return _HealthMetrics(
          totalPanels: json['totalPanels'] ?? 0,
          healthyCount: json['healthyCount'] ?? 0,
          warningCount: json['warningCount'] ?? 0,
          criticalCount: json['criticalCount'] ?? 0,
          overallScore: (json['overallScore'] ?? 0.0).toDouble(),
          generatedAt: DateTime.parse(json['generatedAt'] ?? DateTime.now().toIso8601String()),
        );
      } else {
        throw Exception('Failed with status ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to fetch health metrics: $e');
    }
  }

  Future<List<_PanelDetail>> _fetchPanelDetails() async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.getHealthPanelsUrl()),
        headers: {'Accept': 'application/json'},
      ).timeout(Duration(seconds: ApiConfig.httpRequestTimeoutSeconds));
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final panelsList = json['panels'] as List;
        return panelsList.map((panel) => _PanelDetail(
          panelId: panel['panelId'] ?? '',
          name: panel['name'] ?? '',
          status: panel['status'] ?? 'unknown',
          voltage: (panel['voltage'] ?? 0.0).toDouble(),
          power: (panel['power'] ?? 0.0).toDouble(),
          current: (panel['current'] ?? 0.0).toDouble(),
          temperature: (panel['temperature'] ?? 0.0).toDouble(),
          efficiency: (panel['efficiency'] ?? 0.0).toDouble(),
        )).toList();
      } else {
        throw Exception('Failed with status ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to fetch panel details: $e');
    }
  }

  Future<List<String>> _fetchRecommendations() async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.getHealthRecommendationsUrl()),
        headers: {'Accept': 'application/json'},
      ).timeout(Duration(seconds: ApiConfig.httpRequestTimeoutSeconds));
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final recommendations = json['recommendations'] as List;
        return recommendations.map((r) => r.toString()).toList();
      } else {
        throw Exception('Failed with status ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to fetch recommendations: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // If a specific panel id is provided (e.g. via QR scan), show the GenAI analysis
    if (widget.panelId != null && widget.panelId!.isNotEmpty) {
      return GenaiAnalysisPage(panelId: widget.panelId);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'System Health Report',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: false,
        actions: [
          Tooltip(
            message: 'Refresh Data',
            child: IconButton(
              onPressed: _isRefreshing ? null : _refreshData,
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ),
          Tooltip(
            message: 'Export Report',
            child: IconButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Exporting health report...')),
                );
              },
              icon: const Icon(Icons.download),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: FutureBuilder<_HealthReportData>(
          future: _healthDataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: const Color(0xFFEF4444),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Error loading health data',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _refreshData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            if (!snapshot.hasData) {
              return const Center(
                child: Text('No data available'),
              );
            }

            final data = snapshot.data!;
            return Container(
              color: const Color(0xFFEFF6FF),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _OverallHealthCard(metrics: data.metrics),
                    const SizedBox(height: 16),
                    _HealthDistributionChart(metrics: data.metrics),
                    const SizedBox(height: 16),
                    _HealthMetricsGrid(metrics: data.metrics),
                    const SizedBox(height: 16),
                    Text(
                      'Panel Details (${data.panels.length})',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    ...(data.panels.map((panel) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PanelDetailCard(panel: panel),
                    ))),
                    const SizedBox(height: 16),
                    _RecommendationsCard(recommendations: data.recommendations),
                    const SizedBox(height: 16),
                    _SystemHealthTimelineCard(metrics: data.metrics),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HealthReportData {
  const _HealthReportData({
    required this.metrics,
    required this.panels,
    required this.recommendations,
  });

  final _HealthMetrics metrics;
  final List<_PanelDetail> panels;
  final List<String> recommendations;
}

class _HealthMetrics {
  const _HealthMetrics({
    required this.totalPanels,
    required this.healthyCount,
    required this.warningCount,
    required this.criticalCount,
    required this.overallScore,
    required this.generatedAt,
  });

  final int totalPanels;
  final int healthyCount;
  final int warningCount;
  final int criticalCount;
  final double overallScore;
  final DateTime generatedAt;

  int get healthyPct => ((healthyCount / totalPanels) * 100).round();
  int get warningPct => ((warningCount / totalPanels) * 100).round();
  int get criticalPct => ((criticalCount / totalPanels) * 100).round();

  String get healthStatus {
    if (overallScore >= 90) return 'Excellent';
    if (overallScore >= 75) return 'Good';
    if (overallScore >= 60) return 'Fair';
    return 'Poor';
  }

  Color get healthColor {
    if (overallScore >= 90) return const Color(0xFF22C55E);
    if (overallScore >= 75) return const Color(0xFFF59E0B);
    if (overallScore >= 60) return const Color(0xFF3B82F6);
    return const Color(0xFFEF4444);
  }
}

class _PanelDetail {
  const _PanelDetail({
    required this.panelId,
    required this.name,
    required this.status,
    required this.voltage,
    required this.power,
    required this.current,
    required this.temperature,
    required this.efficiency,
  });

  final String panelId;
  final String name;
  final String status;
  final double voltage;
  final double power;
  final double current;
  final double temperature;
  final double efficiency;

  Color get statusColor {
    switch (status) {
      case 'healthy':
        return const Color(0xFF22C55E);
      case 'warning':
        return const Color(0xFFF59E0B);
      case 'critical':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  String get statusLabel {
    switch (status) {
      case 'healthy':
        return 'Healthy';
      case 'warning':
        return 'Warning';
      case 'critical':
        return 'Critical';
      default:
        return 'Unknown';
    }
  }

  IconData get statusIcon {
    switch (status) {
      case 'healthy':
        return Icons.check_circle_rounded;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'critical':
        return Icons.error_outline_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }
}

class _OverallHealthCard extends StatelessWidget {
  const _OverallHealthCard({required this.metrics});

  final _HealthMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              metrics.healthColor.withValues(alpha: 0.05),
            ],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overall System Health',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Last updated: ${DateFormat('HH:mm:ss').format(metrics.generatedAt)}',
                        style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text(
                      metrics.overallScore.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: metrics.healthColor,
                      ),
                    ),
                    Text(
                      metrics.healthStatus,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: metrics.healthColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: metrics.overallScore / 100,
                minHeight: 12,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(metrics.healthColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthDistributionChart extends StatelessWidget {
  const _HealthDistributionChart({required this.metrics});

  final _HealthMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final sections = <PieChartSectionData>[
      PieChartSectionData(
        value: metrics.healthyPct.toDouble(),
        color: const Color(0xFF22C55E),
        radius: 16,
        showTitle: false,
      ),
      PieChartSectionData(
        value: metrics.warningPct.toDouble(),
        color: const Color(0xFFF59E0B),
        radius: 16,
        showTitle: false,
      ),
      PieChartSectionData(
        value: metrics.criticalPct.toDouble(),
        color: const Color(0xFFEF4444),
        radius: 16,
        showTitle: false,
      ),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Panel Health Distribution',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
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
                        '${metrics.totalPanels}',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Total Panels',
                        style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF64748B), fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                _DistributionLegend(
                  label: 'Healthy',
                  count: metrics.healthyCount,
                  percentage: metrics.healthyPct,
                  color: const Color(0xFF22C55E),
                ),
                _DistributionLegend(
                  label: 'Warning',
                  count: metrics.warningCount,
                  percentage: metrics.warningPct,
                  color: const Color(0xFFF59E0B),
                ),
                _DistributionLegend(
                  label: 'Critical',
                  count: metrics.criticalCount,
                  percentage: metrics.criticalPct,
                  color: const Color(0xFFEF4444),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DistributionLegend extends StatelessWidget {
  const _DistributionLegend({
    required this.label,
    required this.count,
    required this.percentage,
    required this.color,
  });

  final String label;
  final int count;
  final int percentage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.all(Radius.circular(999)),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
            Text(
              '$count ($percentage%)',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ],
    );
  }
}

class _HealthMetricsGrid extends StatelessWidget {
  const _HealthMetricsGrid({required this.metrics});

  final _HealthMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.0,
      children: [
        _MetricTile(
          icon: Icons.bolt_rounded,
          label: 'Total Panels',
          value: metrics.totalPanels.toString(),
          color: const Color(0xFF2563EB),
        ),
        _MetricTile(
          icon: Icons.check_circle_rounded,
          label: 'Healthy',
          value: metrics.healthyCount.toString(),
          color: const Color(0xFF22C55E),
        ),
        _MetricTile(
          icon: Icons.warning_amber_rounded,
          label: 'Warning',
          value: metrics.warningCount.toString(),
          color: const Color(0xFFF59E0B),
        ),
        _MetricTile(
          icon: Icons.error_outline_rounded,
          label: 'Critical',
          value: metrics.criticalCount.toString(),
          color: const Color(0xFFEF4444),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.all(Radius.circular(10)),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF64748B), fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelDetailCard extends StatelessWidget {
  const _PanelDetailCard({required this.panel});

  final _PanelDetail panel;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 4,
                  color: panel.statusColor,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                panel.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                panel.panelId,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.all(Radius.circular(999)),
                            color: panel.statusColor.withValues(alpha: 0.12),
                            border: Border.all(color: panel.statusColor.withValues(alpha: 0.45)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(panel.statusIcon, size: 14, color: panel.statusColor),
                              const SizedBox(width: 6),
                              Text(
                                panel.statusLabel,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: panel.statusColor,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 4,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.1,
                      children: [
                        _StatCell(label: 'V', value: '${panel.voltage.toStringAsFixed(1)}V'),
                        _StatCell(label: 'P', value: '${panel.power.toStringAsFixed(1)}W'),
                        _StatCell(label: 'I', value: '${panel.current.toStringAsFixed(2)}A'),
                        _StatCell(label: 'T', value: '${panel.temperature.toStringAsFixed(1)}°C'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Efficiency',
                          style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF64748B), fontSize: 11),
                        ),
                        Text(
                          '${panel.efficiency.toStringAsFixed(1)}%',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: panel.efficiency / 100,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          panel.efficiency > 90 ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), fontSize: 9),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _RecommendationsCard extends StatelessWidget {
  const _RecommendationsCard({required this.recommendations});

  final List<String> recommendations;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_rounded, color: AppTheme.brandGreen, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Recommendations',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(
              recommendations.length,
              (index) => Padding(
                padding: EdgeInsets.only(bottom: index < recommendations.length - 1 ? 10 : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4, right: 10),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF22C55E),
                          borderRadius: BorderRadius.all(Radius.circular(999)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        recommendations[index],
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Color(0xFF334155),
                        ),
                      ),
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

class _SystemHealthTimelineCard extends StatelessWidget {
  const _SystemHealthTimelineCard({required this.metrics});

  final _HealthMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history_rounded, color: AppTheme.brandGreen, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Report Generated',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              DateFormat('EEEE, MMMM d, yyyy - HH:mm:ss').format(metrics.generatedAt),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              'Next report will be generated in 24 hours',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
