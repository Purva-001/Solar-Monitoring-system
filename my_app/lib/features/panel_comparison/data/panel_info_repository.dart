import '../../../core/api/api_client.dart';
import '../domain/panel_comparison_models.dart';

class PanelInfoRepository {
  PanelInfoRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  double _toDouble(dynamic v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    if (v is Map && v['value'] is num) return (v['value'] as num).toDouble();
    return fallback;
  }

  Map _asMap(dynamic v) => v is Map ? v : const {};

  Future<PanelInfo> fetch({required String panelId}) async {
    final data = await _api.getJson('/api/panel/info', query: {'panel_id': panelId});
    if (data is! Map) throw Exception('Unexpected API response: expected object');

    final voltage = _asMap(data['voltage']);
    final power = _asMap(data['power']);

    return PanelInfo(
      panelId: (data['panel_id'] ?? data['id'] ?? panelId).toString(),
      voltageV1: _toDouble(voltage['V1']),
      voltageV2: _toDouble(voltage['V2']),
      voltageV3: _toDouble(voltage['V3']),
      powerP1: _toDouble(power['P1']),
      powerP2: _toDouble(power['P2']),
      powerP3: _toDouble(power['P3']),
      currentI: _toDouble(data['current']),
      requiresAnalysis: data['requires_analysis'] == true,
      message: (data['message'] ?? '').toString(),
    );
  }
}
