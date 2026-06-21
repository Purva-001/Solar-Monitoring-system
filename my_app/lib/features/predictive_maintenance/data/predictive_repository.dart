import '../../../core/api/api_client.dart';
import '../domain/predictive_models.dart';

class PredictiveMaintenanceRepository {
  PredictiveMaintenanceRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  double _toDouble(dynamic v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  int _toInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  Future<PredictiveMaintenance> fetch({required String panelId}) async {
    final data = await _api.getJson('/api/panel/predictive-maintenance', query: {'panel_id': panelId});
    if (data is! Map) throw Exception('Unexpected API response: expected object');

    return PredictiveMaintenance(
      panelId: (data['panel_id'] ?? panelId).toString(),
      maintenancePriority: (data['maintenance_priority'] ?? '').toString(),
      trend: (data['trend'] ?? '').toString(),
      predictedEfficiency30Days: _toDouble(data['predicted_efficiency_30days'], fallback: 0),
      predictedEfficiency90Days: _toDouble(data['predicted_efficiency_90days'], fallback: 0),
      nextMaintenanceRecommendedDays: _toInt(data['next_maintenance_recommended_days'], fallback: 0),
      timestampIso: (data['timestamp'] ?? '').toString(),
    );
  }
}
