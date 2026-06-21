import 'dart:convert';

/// QR may encode a plain panel id ([PANEL_001]) or a tiny JSON `{"panel_id":"PANEL_003"}`.
String? tryExtractPanelId(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  try {
    dynamic dec = jsonDecode(s);
    if (dec is List && dec.isNotEmpty) dec = dec.first;
    if (dec is Map) {
      final pid = dec['panel_id'] ?? dec['panelId'] ?? dec['id'];
      if (pid != null) {
        final t = pid.toString().trim();
        if (_looksLikePanelId(t)) return t;
      }
    }
  } catch (_) {}

  if (_looksLikePanelId(s)) return s;

  final m = RegExp(r'\b(PANEL[_\-]?\d+|PL01-B02-INV03-STR05-P0[1-4])\b', caseSensitive: false).firstMatch(s);
  if (m != null) return m.group(1)!.replaceAll(' ', '');
  return null;
}

bool _looksLikePanelId(String s) {
  final t = s.trim();
  if (t.isEmpty) return false;
  if (RegExp(r'^PANEL[_\-]?\d+$', caseSensitive: false).hasMatch(t)) return true;
  if (RegExp(r'^PL01-B02-INV03-STR05-P0[1-4]$', caseSensitive: false).hasMatch(t)) return true;
  return false;
}
