import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../domain/maintenance_models.dart';

class MaintenanceComparisonRepository {
  MaintenanceComparisonRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;
  final Uri _base = Uri.parse(ApiConfig.fastApiBaseUrl);

  static const double _ratedPanelW = 40.0;

  int channelIndexForPanel(String panelId) {
    final id = panelId.toUpperCase();
    if (id.contains('-P04')) return 4;
    if (id.contains('-P03')) return 3;
    if (id.contains('-P02')) return 2;
    return 1;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    if (v is Map && v['value'] is num) return (v['value'] as num).toDouble();
    if (v is Map && v['value'] is String) return double.tryParse(v['value'] as String);
    return null;
  }

  double? _powerFromHealthReport(dynamic healthReport, int channelIdx) {
    if (healthReport is! Map) return null;
    final sd = healthReport['sensor_data'];
    if (sd is! Map) return null;
    final key = 'P$channelIdx';
    final p = sd[key] ?? ((sd['power'] is Map) ? (sd['power'] as Map)[key] : null);
    return _toDouble(p);
  }

  double _deviationUnderRated(double? w) {
    if (w == null) return 0;
    final n = w.toDouble();
    if (!n.isFinite) return 0;
    final pct = ((_ratedPanelW - n) / _ratedPanelW) * 100.0;
    if (pct < 0) return 0;
    return pct;
  }

  String _healthLabelFromW(double? w) {
    if (w == null) return '—';
    return w >= 5 ? 'Healthy' : 'Faulty';
  }

  String? _toAbsoluteUrl(dynamic rawUrl) {
    final s = rawUrl?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    final u = Uri.tryParse(s);
    if (u != null && u.hasScheme) return u.toString();
    if (!s.startsWith('/')) {
      return _base.replace(path: '/$s').toString();
    }
    return _base.replace(path: s).toString();
  }

  double? _channelPowerFromSnapshot(Map payload, int channelIdx, String phase) {
    final key = 'panel${channelIdx}power_$phase';
    return _toDouble(payload[key]);
  }

  MaintenanceComparison mapFromPayload({
    required Map payload,
    required String panelId,
    required int channelIdx,
    double? liveChannelPowerW,
  }) {
    final before = (payload['before'] is Map) ? (payload['before'] as Map) : const {};
    final after = (payload['after'] is Map) ? (payload['after'] as Map) : const {};

    final beforePower = _channelPowerFromSnapshot(payload, channelIdx, 'before') ??
        _channelPowerFromSnapshot(before, channelIdx, 'before') ??
        _powerFromHealthReport(before['health_report'], channelIdx) ??
        _toDouble(before['power_before']) ??
        _toDouble(payload['power_before']);

    final afterPowerStored = _channelPowerFromSnapshot(payload, channelIdx, 'after') ??
        _channelPowerFromSnapshot(after, channelIdx, 'after') ??
        _powerFromHealthReport(after['health_report'], channelIdx) ??
        _toDouble(after['power_after']) ??
        _toDouble(payload['power_after']);

    final beforeImageUrl = _toAbsoluteUrl(before['image_url'] ?? (before['image'] is Map ? (before['image'] as Map)['url'] : null) ?? payload['before_image_url']);
    final afterImageUrl = _toAbsoluteUrl(after['image_url'] ?? (after['image'] is Map ? (after['image'] as Map)['url'] : null) ?? payload['after_image_url']);

    final beforeStatus = _healthLabelFromW(beforePower);
    final afterStatus = _healthLabelFromW(afterPowerStored ?? liveChannelPowerW);

    return MaintenanceComparison(
      panelId: (payload['panel_id'] ?? panelId).toString(),
      channelIdx: channelIdx,
      beforePowerW: beforePower,
      afterPowerWStored: afterPowerStored,
      liveChannelPowerW: liveChannelPowerW,
      beforeStatus: beforeStatus,
      afterStatus: afterStatus,
      beforeDeviationPct: _deviationUnderRated(beforePower),
      afterDeviationPct: _deviationUnderRated(afterPowerStored ?? liveChannelPowerW),
      completedAtIso: payload['timestamp']?.toString(),
      beforeImageUrl: beforeImageUrl,
      afterImageUrl: afterImageUrl,
    );
  }

  Future<double?> fetchLiveChannelPowerW({required String panelId, required int channelIdx}) async {
    try {
      final data = await _api.getJson('/api/panel/readings', query: {'panel_id': panelId});
      if (data is! Map) return null;
      final legacy = data['panel${channelIdx}power'];
      final fromPowerMap = (data['power'] is Map) ? (data['power'] as Map)['P$channelIdx'] : null;
      final fromTop = data['P$channelIdx'];
      return _toDouble(legacy) ?? _toDouble(fromPowerMap) ?? _toDouble(fromTop);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> fetchBeforeRaw({required String panelId}) async {
    final data = await _api.getJson('/api/panel/comparison/before', query: {'panel_id': panelId});
    if (data is! Map) {
      throw Exception('Unexpected API response: expected object');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> captureBeforeRaw({required String panelId}) async {
    final data = await _api.postJson('/api/panel/comparison/before', query: {'panel_id': panelId}, timeout: const Duration(seconds: 60));
    if (data is! Map) {
      throw Exception('Unexpected API response: expected object');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> fetchLatestRaw({required String panelId}) async {
    final data = await _api.getJson('/api/panel/comparison/latest', query: {'panel_id': panelId});
    if (data is! Map) {
      throw Exception('Unexpected API response: expected object');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> runComparisonRaw({required String panelId}) async {
    final data = await _api.postJson('/api/panel/comparison/run', query: {'panel_id': panelId}, timeout: const Duration(seconds: 120));
    if (data is! Map) {
      throw Exception('Unexpected API response: expected object');
    }
    return Map<String, dynamic>.from(data);
  }
}
