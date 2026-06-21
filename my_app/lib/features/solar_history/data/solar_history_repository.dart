import '../../../core/api/api_client.dart';
import '../domain/solar_history_models.dart';

class SolarHistoryRepository {
  SolarHistoryRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  static dynamic _unwrap(dynamic v) {
    if (v is Map && v.containsKey('value')) return v['value'];
    return v;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    final u = _unwrap(v);
    if (u is num) return u.toDouble();
    if (u is String) return double.tryParse(u);
    return null;
  }

  double? _toNonNegative(dynamic v) {
    final n = _toDouble(v);
    return n?.abs();
  }

  double? _pickVoltage(Map<String, dynamic> row, int channel) {
    final idx = channel - 1;
    final vk = 'V$channel';
    final vkLower = 'v$channel';

    List<dynamic>? asList(dynamic x) => x is List ? x : null;

    final voltagesAny = row['voltages'] ?? row['voltages_V'] ?? row['Voltage'];
    final vList = asList(row['voltage']) ?? asList(voltagesAny);
    if (vList != null && idx >= 0 && idx < vList.length) {
      final n = _toNonNegative(_unwrap(vList[idx]));
      if (n != null) return n;
    }

    final top = _unwrap(row[vk]) ?? _unwrap(row[vkLower]);
    if (top != null) return _toNonNegative(top);

    if (row['voltage'] is Map) {
      final vm = row['voltage']! as Map;
      final nk = vm[vk] ?? vm[vkLower] ?? vm['$channel'] ?? vm[channel];
      final nested = _unwrap(nk);
      if (nested != null) return _toNonNegative(nested);
    }
    final lkSnake = 'panel_${channel}_voltage';
    return _toNonNegative(row['panel${channel}voltage']) ?? _toNonNegative(row[lkSnake]);
  }

  double? _pickPowerRaw(Map<String, dynamic> row, int channel) {
    final idx = channel - 1;
    final pk = 'P$channel';
    final pkLower = 'p$channel';

    List<dynamic>? asList(dynamic x) => x is List ? x : null;
    final powersAny = row['powers'] ?? row['powers_W'];
    final pList = asList(row['power']) ?? asList(powersAny);
    if (pList != null && idx >= 0 && idx < pList.length) {
      final n = _toNonNegative(_unwrap(pList[idx]));
      if (n != null) return n;
    }

    final top = _unwrap(row[pk]) ?? _unwrap(row[pkLower]);
    if (top != null) return _toNonNegative(top);

    if (row['power'] is Map) {
      final pm = row['power']! as Map;
      final nk = pm[pk] ?? pm[pkLower] ?? pm['$channel'] ?? pm[channel];
      final nested = _unwrap(nk);
      if (nested != null) return _toNonNegative(nested);
    }
    final lkSnake = 'panel_${channel}_power';
    return _toNonNegative(row['panel${channel}power']) ?? _toNonNegative(row[lkSnake]);
  }

  List<dynamic>? _currentList(dynamic rowDyn) {
    if (rowDyn is! Map) return null;
    final row = Map<String, dynamic>.from(rowDyn);
    for (final k in ['I_mA_list', 'currents_mA', 'panel_current_mA', 'currents']) {
      final x = row[k];
      if (x is List && x.isNotEmpty) return x;
    }
    return null;
  }

  int? _toTimestampMs(Map<String, dynamic> row) {
    final candidate = row['tsMs'] ??
        row['timestampMs'] ??
        row['timestamp'] ??
        row['ts'] ??
        row['time'] ??
        row['datetime'] ??
        (row['V1'] is Map ? (row['V1']! as Map)['timestamp'] : null) ??
        (row['V4'] is Map ? (row['V4']! as Map)['timestamp'] : null) ??
        (row['P1'] is Map ? (row['P1']! as Map)['timestamp'] : null) ??
        (row['I'] is Map ? (row['I']! as Map)['timestamp'] : null);

    final n = (candidate is num)
        ? candidate.toDouble()
        : (candidate is String)
            ? double.tryParse(candidate)
            : null;
    if (n == null || !n.isFinite || n <= 0) return null;
    return n < 1e12 ? (n * 1000).round() : n.round();
  }

  SolarHistoryPoint normalizeSnapshotRow(Map<String, dynamic> row, int tsMs) {
    final v1 = _pickVoltage(row, 1);
    final v2 = _pickVoltage(row, 2);
    final v3 = _pickVoltage(row, 3);
    final v4 = _pickVoltage(row, 4);

    final rowIMa = _toDouble(_unwrap(row['I']));
    final rowMaAbs = (rowIMa != null && rowIMa.isFinite) ? rowIMa.abs() : null;

    final ci = _currentList(row);
    final rawI1 = ci != null && ci.isNotEmpty ? ci[0] : row['I1'];
    final rawI2 = ci != null && ci.length > 1 ? ci[1] : row['I2'];
    final rawI3 = ci != null && ci.length > 2 ? ci[2] : row['I3'];
    final rawI4 = ci != null && ci.length > 3 ? ci[3] : row['I4'];

    final hasPanelCurrents = [rawI1, rawI2, rawI3, rawI4].any((x) => x != null);

    double chanMa(dynamic raw) {
      if (hasPanelCurrents) {
        return _toNonNegative(_unwrap(raw)) ?? 0.0;
      }
      return rowMaAbs ?? 0.0;
    }

    final i1Ma = chanMa(rawI1);
    final i2Ma = chanMa(rawI2);
    final i3Ma = chanMa(rawI3);
    final i4Ma = chanMa(rawI4);

    final i1A = i1Ma / 1000.0;
    final i2A = i2Ma / 1000.0;
    final i3A = i3Ma / 1000.0;
    final i4A = i4Ma / 1000.0;

    double? derivedPower(int ch, double? v, double iA) {
      final raw = _pickPowerRaw(row, ch);
      if (raw != null) return raw;
      if (v != null && v.isFinite && iA.isFinite && iA.abs() > 1e-12) {
        return v.abs() * iA.abs();
      }
      return null;
    }

    final p1 = derivedPower(1, v1, i1A);
    final p2 = derivedPower(2, v2, i2A);
    final p3 = derivedPower(3, v3, i3A);
    final p4 = derivedPower(4, v4, i4A);

    final totalA = i1A + i2A + i3A + i4A;
    final totalMa = (rowMaAbs != null && rowMaAbs > 0) ? rowMaAbs : (totalA * 1000.0);

    return SolarHistoryPoint(
      tsMs: tsMs,
      v1: v1,
      v2: v2,
      v3: v3,
      v4: v4,
      p1: p1,
      p2: p2,
      p3: p3,
      p4: p4,
      i: totalMa > 0 ? totalMa : null,
      i1Ma: i1Ma,
      i2Ma: i2Ma,
      i3Ma: i3Ma,
      i4Ma: i4Ma,
    );
  }

  /// Latest live row from `GET /api/solar-iv-pv` → `AWS_API_ENDPOINT` (same as React I–V / P–V).
  Future<SolarHistoryPoint?> fetchLatestIvPvPoint() async {
    try {
      final data = await _api.getJson('/api/solar-iv-pv');
      Map<String, dynamic>? m;
      if (data is Map) {
        m = Map<String, dynamic>.from(data);
      } else if (data is List && data.isNotEmpty) {
        final last = data.last;
        if (last is Map) m = Map<String, dynamic>.from(last);
      }
      if (m == null) return null;
      final ts = _toTimestampMs(m) ?? DateTime.now().millisecondsSinceEpoch;
      return normalizeSnapshotRow(m, ts);
    } catch (_) {
      return null;
    }
  }

  /// Proxied through FastAPI `GET /api/solar-history` → `AWS_SOLAR_HISTORY_ENDPOINT`.
  Future<List<SolarHistoryPoint>> fetchSolarHistory({required String assetId}) async {
    final data = await _api.getJson('/api/solar-history', query: {'assetId': assetId});
    if (data is! List) {
      throw Exception('Unexpected API response: expected a list');
    }

    final points = <SolarHistoryPoint>[];
    for (final row in data) {
      if (row is! Map) continue;
      final m = Map<String, dynamic>.from(row);
      final ts = _toTimestampMs(m);
      if (ts == null) continue;
      points.add(normalizeSnapshotRow(m, ts));
    }

    points.sort((a, b) => a.tsMs.compareTo(b.tsMs));
    return points;
  }
}
