import '../../../core/api/api_client.dart';
import '../domain/panel_models.dart';

class PanelsRepository {
  PanelsRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  Future<List<PanelSummary>> fetchPanels() async {
    final data = await _api.getJson('/api/panels/all');
    if (data is! List) {
      throw Exception('Unexpected API response: expected array');
    }

    final panels = <PanelSummary>[];
    for (final row in data) {
      if (row is! Map) continue;
      final id = (row['id'] ?? row['panel_id'] ?? '').toString();
      if (id.isEmpty) continue;

      panels.add(
        PanelSummary(
          id: id,
          name: (row['name'] ?? id).toString(),
          location: (row['location'] ?? '').toString(),
          capacity: _toDouble(row['capacity']),
          currentOutput: _toDouble(row['current_output'] ?? row['currentOutput']),
          healthScore: _toDouble(row['health_score'] ?? row['healthScore']),
        ),
      );
    }
    return panels;
  }
}
