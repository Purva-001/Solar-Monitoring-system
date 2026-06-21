import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/api/api_config.dart';
import '../domain/panel_health_snapshot.dart';

class PanelSnapshotRepository {
  PanelSnapshotRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _panelUri(String panelId, {bool refreshAi = false}) {
    var raw = ApiConfig.effectiveBaseUrl.trim();
    if (raw.isEmpty) raw = 'http://127.0.0.1:8000';
    if (!raw.contains('://')) raw = 'http://$raw';
    final base = Uri.parse(raw);
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/panel/${Uri.encodeComponent(panelId)}',
      queryParameters: refreshAi ? {'refresh_ai': '1'} : null,
    );
  }

  Future<PanelHealthSnapshot> fetchPanelBundle(String panelId, {bool refreshAi = false}) async {
    final uri = _panelUri(panelId, refreshAi: refreshAi);
    final res = await _client.get(uri).timeout(const Duration(seconds: 120));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw PanelSnapshotException(
        'HTTP ${res.statusCode}',
        body: res.body,
      );
    }
    final data = jsonDecode(res.body);
    if (data is! Map<String, dynamic>) {
      throw const PanelSnapshotException('Invalid JSON object');
    }
    return PanelHealthSnapshot.fromJson(data);
  }
}

class PanelSnapshotException implements Exception {
  const PanelSnapshotException(this.message, {this.body});

  final String message;
  final String? body;

  @override
  String toString() => body == null || body!.isEmpty ? message : '$message: $body';
}
