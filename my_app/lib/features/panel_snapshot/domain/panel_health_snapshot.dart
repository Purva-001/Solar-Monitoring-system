import 'package:equatable/equatable.dart';

class MlTopPrediction extends Equatable {
  const MlTopPrediction({required this.label, required this.score});

  final String label;
  final double score;

  factory MlTopPrediction.fromJson(dynamic e) {
    if (e is! Map) return const MlTopPrediction(label: '', score: 0);
    final m = Map<String, dynamic>.from(e);
    final label = (m['label'] ?? m['name'] ?? '').toString();
    final s = m['score'] ?? m['confidence'];
    final score = s is num ? s.toDouble() : double.tryParse('$s') ?? 0;
    return MlTopPrediction(label: label, score: score);
  }

  double get scorePercent => (score <= 1.001 && score >= 0) ? score * 100 : score;

  @override
  List<Object?> get props => [label, score];
}

class PanelHealthSnapshot extends Equatable {
  const PanelHealthSnapshot({
    required this.panelId,
    required this.panelAliasScanned,
    required this.stringId,
    required this.channelIndex,
    required this.voltage,
    required this.current,
    required this.power,
    required this.temperatureC,
    required this.defect,
    required this.confidence,
    required this.healthScore,
    required this.suggestion,
    required this.status,
    required this.lastUpdatedSensor,
    required this.lastUpdatedAi,
    required this.imageCandidates,
    required this.readingsRaw,
    required this.weatherRaw,
    required this.geminiError,
    required this.healthReportMarkdown,
    required this.awsConfigured,
    required this.readingsSource,
    required this.topPredictions,
    required this.onnxModelName,
  });

  final String panelId;
  final String panelAliasScanned;
  final String stringId;
  final int channelIndex;
  final double voltage;
  final double current;
  final double power;
  final double? temperatureC;
  final String defect;
  final double confidence;
  final int healthScore;
  final String suggestion;
  final String status;
  final String lastUpdatedSensor;
  final String lastUpdatedAi;
  final List<String> imageCandidates;
  final Map<String, dynamic> readingsRaw;
  final Map<String, dynamic> weatherRaw;
  final String? geminiError;
  final String? healthReportMarkdown;
  final bool awsConfigured;
  final String? readingsSource;
  final List<MlTopPrediction> topPredictions;
  final String onnxModelName;

  /// Primary defect label for UI (matches React `defect.type`).
  String get defectDisplay {
    final d = defect.trim();
    if (d.isEmpty) return '—';
    return d;
  }

  /// Model confidence as 0–100 for progress bars (ONNX probability).
  double get confidencePercent {
    final c = confidence;
    if (c <= 1.001 && c >= 0) return (c * 100).clamp(0, 100);
    return c.clamp(0, 100);
  }

  factory PanelHealthSnapshot.fromJson(Map<String, dynamic> j) {
    final imgs = j['image_candidates'];
    final list = <String>[];
    if (imgs is List) {
      for (final e in imgs) {
        if (e != null) list.add(e.toString());
      }
    }
    final single = j['image_url']?.toString();
    if (single != null && single.isNotEmpty && !list.contains(single)) {
      list.insert(0, single);
    }

    final tp = <MlTopPrediction>[];
    dynamic rawTop = j['defect_analysis'];
    if (rawTop is Map && rawTop['top_predictions'] is List) {
      for (final e in rawTop['top_predictions'] as List) {
        tp.add(MlTopPrediction.fromJson(e));
      }
    } else if (j['top_predictions'] is List) {
      for (final e in j['top_predictions'] as List) {
        tp.add(MlTopPrediction.fromJson(e));
      }
    }

    return PanelHealthSnapshot(
      panelId: (j['panel_id'] ?? '').toString(),
      panelAliasScanned: (j['panel_alias_scanned'] ?? j['panel_id'] ?? '').toString(),
      stringId: (j['string_id'] ?? '').toString(),
      channelIndex: _asInt(j['channel_index'], 1),
      voltage: _asDouble(j['voltage']),
      current: _asDouble(j['current']),
      power: _asDouble(j['power']),
      temperatureC: j['temperature_c'] == null ? null : _asDouble(j['temperature_c']),
      defect: (j['defect'] ?? 'Unknown').toString(),
      confidence: _asDouble(j['confidence']),
      healthScore: _asInt(j['health_score'], 0),
      suggestion: (j['suggestion'] ?? '').toString(),
      status: (j['status'] ?? 'Warning').toString(),
      lastUpdatedSensor: (j['last_updated_sensor'] ?? j['last_updated'] ?? '').toString(),
      lastUpdatedAi: (j['last_updated_ai_snapshot'] ?? '').toString(),
      imageCandidates: list,
      readingsRaw: j['readings'] is Map<String, dynamic> ? Map<String, dynamic>.from(j['readings'] as Map) : {},
      weatherRaw: j['weather'] is Map<String, dynamic> ? Map<String, dynamic>.from(j['weather'] as Map) : {},
      geminiError: j['gemini_error']?.toString(),
      healthReportMarkdown: j['health_report_markdown']?.toString(),
      awsConfigured: j['aws_endpoint_configured'] == true,
      readingsSource: j['readings_source']?.toString(),
      topPredictions: tp,
      onnxModelName: (j['onnx_model'] ?? '').toString(),
    );
  }

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static int _asInt(dynamic v, int d) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? d;
    return d;
  }

  @override
  List<Object?> get props => [panelId, lastUpdatedSensor, healthScore, defect, power, topPredictions.length];
}
