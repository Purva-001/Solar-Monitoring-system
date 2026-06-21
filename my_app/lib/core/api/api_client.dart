import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _parseBaseUri(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return Uri.parse('http://localhost:8000');

    // If user passed something like "localhost:5000" (no scheme), Uri.parse treats it as a path.
    final withScheme = v.contains('://') ? v : 'http://$v';
    final u = Uri.parse(withScheme);

    // Defensive fallback
    if (u.scheme.isEmpty || u.host.isEmpty) {
      return Uri.parse('http://localhost:8000');
    }
    return u;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final rawPath = path.trim();
    // Allow calling absolute URLs directly (e.g. https://...)
    if (rawPath.startsWith('http://') || rawPath.startsWith('https://')) {
      final u = Uri.parse(rawPath);
      return u.replace(queryParameters: query ?? u.queryParameters);
    }

    final base = _parseBaseUri(ApiConfig.effectiveBaseUrl);
    final normalizedPath = rawPath.startsWith('/') ? rawPath : '/$rawPath';
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: normalizedPath,
      queryParameters: query,
    );
  }

  Future<dynamic> getJson(String path, {Map<String, String>? query, Duration timeout = const Duration(seconds: 30)}) async {
    final res = await _client.get(_uri(path, query)).timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Request failed (${res.statusCode}): ${res.body}');
    }
    return jsonDecode(res.body);
  }

  Future<dynamic> postJson(
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final res = await _client
        .post(
          _uri(path, query),
          headers: const {'content-type': 'application/json'},
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Request failed (${res.statusCode}): ${res.body}');
    }
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }
}
