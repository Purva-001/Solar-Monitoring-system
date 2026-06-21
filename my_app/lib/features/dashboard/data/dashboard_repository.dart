import '../../../core/api/api_client.dart';
import '../domain/dashboard_models.dart';
import '../domain/panel_models.dart';
import 'panels_repository.dart';

class DashboardRepository {
  DashboardRepository({ApiClient? apiClient})
      : _api = apiClient ?? ApiClient(),
        _panels = PanelsRepository(apiClient: apiClient);

  final ApiClient _api;
  final PanelsRepository _panels;

  double _toDouble(dynamic v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    if (v is Map && v['value'] is num) return (v['value'] as num).toDouble();
    if (v is Map && v['value'] is String) return double.tryParse(v['value'] as String) ?? fallback;
    return fallback;
  }

  static dynamic _unwrap(dynamic v) {
    if (v is Map && v.containsKey('value')) return v['value'];
    return v;
  }

  double _pickVoltage(Map data, int channel) {
    final vk = 'V$channel';
    final lk = 'panel${channel}voltage';
    final top = _unwrap(data[vk]);
    if (top != null) return _toDouble(top);
    if (data['voltage'] is Map) {
      final nested = _unwrap((data['voltage'] as Map)[vk]);
      if (nested != null) return _toDouble(nested);
    }
    return _toDouble(data[lk]);
  }

  double _pickPower(Map data, int channel) {
    final pk = 'P$channel';
    final lk = 'panel${channel}power';
    final top = _unwrap(data[pk]);
    if (top != null) return _toDouble(top);
    if (data['power'] is Map) {
      final nested = _unwrap((data['power'] as Map)[pk]);
      if (nested != null) return _toDouble(nested);
    }
    return _toDouble(data[lk]);
  }

  double _pickCurrentA(Map data, int channel) {
    final ik = 'I$channel';
    final lk = 'panel${channel}current';
    final top = _unwrap(data[ik]);
    if (top != null) return _toDouble(top);
    return _toDouble(data[lk]);
  }

  int _panelChannelCount(Map data) {
    var n = 0;
    for (var i = 1; i <= 4; i++) {
      final pk = 'P$i';
      final lk = 'panel${i}power';
      final hasTop = data[pk] != null;
      final hasPow = data['power'] is Map && (data['power'] as Map)[pk] != null;
      final hasLeg = data[lk] != null;
      if (hasTop || hasPow || hasLeg) n++;
    }
    if (n == 0) return 4;
    return n;
  }

  int? _historyRowTsMs(Map row) {
    final candidate = row['tsMs'] ??
        row['timestampMs'] ??
        row['timestamp'] ??
        row['ts'] ??
        row['time'] ??
        row['datetime'] ??
        (row['V1'] is Map ? (row['V1'] as Map)['timestamp'] : null) ??
        (row['P1'] is Map ? (row['P1'] as Map)['timestamp'] : null) ??
        (row['I'] is Map ? (row['I'] as Map)['timestamp'] : null);

    final n = (candidate is num)
        ? candidate.toDouble()
        : (candidate is String)
            ? double.tryParse(candidate)
            : null;
    if (n == null || !n.isFinite || n <= 0) return null;
    return n < 1e12 ? (n * 1000).round() : n.round();
  }

  double _historyRowTotalW(Map row) {
    double pick(String pk) {
      final top = _unwrap(row[pk]);
      if (top != null) return _toDouble(top);
      if (row['power'] is Map) {
        final v = _unwrap((row['power'] as Map)[pk]);
        if (v != null) return _toDouble(v);
      }
      final ch = int.tryParse(pk.substring(1)) ?? 0;
      if (ch > 0) return _toDouble(row['panel${ch}power']);
      return 0;
    }

    return pick('P1').abs() + pick('P2').abs() + pick('P3').abs() + pick('P4').abs();
  }

  /// Historical total power (W) from FastAPI proxy to `AWS_SOLAR_HISTORY_ENDPOINT`.
  Future<List<PowerPoint>> fetchPowerTrendFromHistory({String assetId = 'SolarPanel_01'}) async {
    final data = await _api.getJson('/api/solar-history', query: {'assetId': assetId});
    if (data is! List) return [];

    final out = <PowerPoint>[];
    for (final e in data) {
      if (e is! Map) continue;
      final row = Map<String, dynamic>.from(e);
      final ts = _historyRowTsMs(row);
      if (ts == null) continue;
      out.add(PowerPoint(tsMs: ts, w: double.parse(_historyRowTotalW(row).toStringAsFixed(2))));
    }
    out.sort((a, b) => a.tsMs.compareTo(b.tsMs));
    return out;
  }

  Future<DashboardReadings> fetchReadings({String panelId = 'PL01-B02-INV03-STR05-P01'}) async {
    final data = await _api.getJson('/api/panel/readings', query: {'panel_id': panelId});
    if (data is! Map) throw Exception('Unexpected readings response');

    final p1v = _pickVoltage(data, 1);
    final p2v = _pickVoltage(data, 2);
    final p3v = _pickVoltage(data, 3);
    final p4v = _pickVoltage(data, 4);

    final p1p = _pickPower(data, 1);
    final p2p = _pickPower(data, 2);
    final p3p = _pickPower(data, 3);
    final p4p = _pickPower(data, 4);

    final p1c = _pickCurrentA(data, 1);
    final p2c = _pickCurrentA(data, 2);
    final p3c = _pickCurrentA(data, 3);
    final p4c = _pickCurrentA(data, 4);

    final c1Ma = p1c * 1000;
    final c2Ma = p2c * 1000;
    final c3Ma = p3c * 1000;
    final c4Ma = p4c * 1000;
    final totalCurrentMa = c1Ma.abs() + c2Ma.abs() + c3Ma.abs() + c4Ma.abs();

    return DashboardReadings(
      v1: p1v,
      v2: p2v,
      v3: p3v,
      v4: p4v,
      p1: p1p,
      p2: p2p,
      p3: p3p,
      p4: p4p,
      c1: c1Ma,
      c2: c2Ma,
      c3: c3Ma,
      c4: c4Ma,
      current: totalCurrentMa,
      timestampIso: DateTime.now().toIso8601String(),
      panelChannelCount: _panelChannelCount(data),
    );
  }

  Future<List<PanelSummary>> fetchPanels() => _panels.fetchPanels();
}
