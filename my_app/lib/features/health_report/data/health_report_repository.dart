import 'dart:math';

import '../../../core/api/api_client.dart';
import '../domain/health_report_models.dart';

class HealthReportRepository {
  HealthReportRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  double _asDouble(dynamic v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    if (v is Map && v['value'] is num) return (v['value'] as num).toDouble();
    if (v is Map && v['value'] is String) return double.tryParse(v['value'] as String) ?? fallback;
    return fallback;
  }

  int _asTs(dynamic v) {
    final n = (v is num)
        ? v.toDouble()
        : (v is String)
            ? double.tryParse(v)
            : null;
    if (n == null || !n.isFinite || n <= 0) {
      return DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
    final tsMs = n < 1e12 ? (n * 1000).round() : n.round();
    return tsMs ~/ 1000;
  }

  Reading _readingFrom(dynamic raw, {Reading? fallback}) {
    if (raw is Map) {
      final value = _asDouble(raw['value'], fallback: fallback?.value ?? 0);
      final ts = _asTs(raw['timestamp'] ?? raw['ts'] ?? raw['time'] ?? raw['datetime']);
      return Reading(value: value, timestamp: ts);
    }

    return Reading(
      value: _asDouble(raw, fallback: fallback?.value ?? 0),
      timestamp: fallback?.timestamp ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
    );
  }

  dynamic _pickNested(Map data, List<List<String>> paths) {
    for (final path in paths) {
      dynamic cur = data;
      var ok = true;
      for (final k in path) {
        if (cur is Map && cur.containsKey(k)) {
          cur = cur[k];
        } else {
          ok = false;
          break;
        }
      }
      if (ok && cur != null) return cur;
    }
    return null;
  }

  String? _asOptionalText(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  SensorData _parseSensorData(dynamic sensorDataRaw) {
    final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (sensorDataRaw is! Map) {
      const z = Reading(value: 0, timestamp: 0);
      return SensorData(v1: z, v2: z, v3: z, p1: z, p2: z, p3: z, i: z);
    }

    final m = sensorDataRaw;

    Reading pick(String key, {List<List<String>>? extraPaths}) {
      final raw = _pickNested(m, [
        [key],
        ...?extraPaths,
      ]);
      final fb = Reading(value: 0, timestamp: nowTs);
      return _readingFrom(raw, fallback: fb);
    }

    final v1 = pick('V1', extraPaths: [
      ['voltage', 'V1'],
    ]);
    final v2 = pick('V2', extraPaths: [
      ['voltage', 'V2'],
    ]);
    final v3 = pick('V3', extraPaths: [
      ['voltage', 'V3'],
    ]);

    final p1 = pick('P1', extraPaths: [
      ['power', 'P1'],
    ]);
    final p2 = pick('P2', extraPaths: [
      ['power', 'P2'],
    ]);
    final p3 = pick('P3', extraPaths: [
      ['power', 'P3'],
    ]);

    final i = pick('I', extraPaths: [
      ['current'],
      ['current', 'I'],
    ]);

    return SensorData(v1: v1, v2: v2, v3: v3, p1: p1, p2: p2, p3: p3, i: i);
  }

  DefectAnalysis _parseDefectAnalysis(dynamic raw) {
    if (raw is! Map) {
      return const DefectAnalysis(defect: 'Unknown', confidence: 0, topPredictions: []);
    }

    final defect = (raw['defect'] ?? '').toString().trim();
    final confidence = _asDouble(raw['confidence'], fallback: 0);

    final preds = <TopPrediction>[];
    final tp = raw['top_predictions'];
    if (tp is List) {
      for (final p in tp) {
        if (p is Map) {
          final label = (p['label'] ?? p['name'] ?? '').toString();
          final score = _asDouble(p['score'] ?? p['confidence'], fallback: 0);
          if (label.isNotEmpty) preds.add(TopPrediction(label: label, score: score));
        }
      }
    }

    return DefectAnalysis(
      defect: defect.isEmpty ? 'Unknown' : defect,
      confidence: max(0, min(1, confidence)),
      topPredictions: preds,
    );
  }

  PowerTrigger _parsePowerTrigger(dynamic raw, SensorData sensor) {
    if (raw is Map) {
      return PowerTrigger(
        p1Value: _asDouble(raw['p1_value'], fallback: sensor.p1.value),
        p2Value: _asDouble(raw['p2_value'], fallback: sensor.p2.value),
        p3Value: _asDouble(raw['p3_value'], fallback: sensor.p3.value),
        threshold: _asDouble(raw['threshold'], fallback: 5.0),
        status: (raw['status'] ?? 'UNKNOWN').toString(),
        message: (raw['message'] ?? '').toString(),
      );
    }

    const threshold = 5.0;
    final below = [sensor.p1.value, sensor.p2.value, sensor.p3.value].any((v) => v < threshold);
    return PowerTrigger(
      p1Value: sensor.p1.value,
      p2Value: sensor.p2.value,
      p3Value: sensor.p3.value,
      threshold: threshold,
      status: below ? 'TRIGGERED' : 'NORMAL',
      message: below ? 'Power (P1/P2/P3) is below 5.0W' : 'Power (P1/P2/P3) is not below 5.0W',
    );
  }

  Future<HealthReport> fetchHealthReport({required String panelId, bool force = false}) async {
    final query = <String, String>{'panel_id': panelId};
    if (force) query['force'] = '1';
    final data = await _api.getJson('/api/panel/health-report', query: query, timeout: const Duration(seconds: 120));
    if (data is! Map) {
      throw Exception('Unexpected API response: expected object');
    }

    final sensorRaw = data['sensor_data'];
    final sensor = _parseSensorData(sensorRaw);

    final defect = _parseDefectAnalysis(data['defect_analysis']);
    final powerTrigger = _parsePowerTrigger(data['power_trigger'], sensor);

    return HealthReport(
      status: (data['status'] ?? '').toString(),
      analysisTriggered: (data['analysis_triggered'] == true) || (data['analysisTriggered'] == true),
      panelId: (data['panel_id'] ?? panelId).toString(),
      timestampIso: (data['timestamp'] ?? DateTime.now().toIso8601String()).toString(),
      powerTrigger: powerTrigger,
      defectAnalysis: defect,
      knowledgeContext: (data['knowledge_context'] ?? '').toString(),
      healthReportMarkdown: (data['health_report'] ?? '').toString(),
      aiSummaryMarkdown: _asOptionalText(data['ai_summary_markdown']),
      aiRecommendationsMarkdown: _asOptionalText(data['ai_recommendations_markdown']),
      aiRootCauseMarkdown: _asOptionalText(data['ai_root_cause_markdown']),
      sensorData: sensor,
      geminiError: data['gemini_error']?.toString(),
    );
  }

  Future<Map<String, dynamic>?> fetchWeatherWardha() async {
    final data = await _api.getJson('/api/weather/wardha', timeout: const Duration(seconds: 30));
    if (data is Map<String, dynamic>) return data;
    return null;
  }

  Future<Map<String, dynamic>?> fetchReadings({required String panelId}) async {
    final data = await _api.getJson(
      '/api/panel/readings',
      query: {'panel_id': panelId},
      timeout: const Duration(seconds: 30),
    );
    if (data is Map<String, dynamic>) return data;
    return null;
  }
}
