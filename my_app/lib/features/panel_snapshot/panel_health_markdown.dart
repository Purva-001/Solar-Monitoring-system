// Mirrors React `HealthReport.js`: markdown section picking and fallbacks for QR report screen.

String? pickMarkdownSection(String? markdown, List<String> titles) {
  final md = markdown?.trim() ?? '';
  if (md.isEmpty) return null;
  final wanted = titles.map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();
  final lines = md.replaceAll('\r\n', '\n').split('\n');

  bool isHeading(String line) => RegExp(r'^#{1,6}\s+').hasMatch(line);
  int headingLevel(String line) => RegExp(r'^(#{1,6})\s+').firstMatch(line)?.group(1)?.length ?? 0;
  String headingTitle(String line) => line.replaceFirst(RegExp(r'^#{1,6}\s+'), '').trim().toLowerCase();

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!isHeading(line)) continue;
    if (!wanted.contains(headingTitle(line))) continue;
    final level = headingLevel(line);
    var end = lines.length;
    for (var j = i + 1; j < lines.length; j++) {
      if (!isHeading(lines[j])) continue;
      if (headingLevel(lines[j]) <= level) {
        end = j;
        break;
      }
    }
    final chunk = lines.sublist(i, end).join('\n').trim();
    return chunk.isEmpty ? null : chunk;
  }
  return null;
}

String truncateMarkdownLines(String? md, {int maxLines = 16}) {
  if (md == null || md.trim().isEmpty) return '';
  final lines = md.replaceAll('\r\n', '\n').split('\n');
  if (lines.length <= maxLines) return md.trim();
  return '${lines.take(maxLines).join('\n').trim()}\n\n...';
}

String sanitizeSummaryMarkdown(String? md, {required String defectType}) {
  if (md == null || md.isEmpty) return '';
  final d = defectType.trim().toLowerCase();
  final hasNoDefect = d == 'none' || d.isEmpty || d == 'clean';
  if (!hasNoDefect) return md;
  return md.replaceAllMapped(
    RegExp(r'\|\s*\*\*Defect Detected\*\*\s*\|\s*clean\s*\|', caseSensitive: false),
    (_) => '| **Defect Detected** | None |',
  );
}

bool containsKbNotFound(String? md) {
  if (md == null) return false;
  return RegExp(r'not\s+found\s+in\s+retrieved\s+knowledge', caseSensitive: false).hasMatch(md);
}

bool isCleanDefect(String? defect, String? condition) {
  final t = '${defect ?? ''} ${condition ?? ''}'.toLowerCase();
  return t.contains('clean') || t.contains('none');
}

const String defaultRecommendationsClean = '''## Recommendations

- Continue monitoring for 24 hours
- Schedule routine cleaning if dust is visible
- Re-scan after next peak sun window''';

const String defaultRecommendationsIssue = '''## Recommendations

- Inspect panel surface for dust/soiling and clean if needed
- Check connectors and junction box for heating/loose contact
- Re-scan and compare confidence after maintenance''';

const String defaultRootCauseClean = '''## Root Cause Analysis

No defect detected in the latest scan. Minor variation may be due to temporary weather/irradiance changes or sensor noise.''';

const String defaultRootCauseIssue = '''## Root Cause Analysis

The detected defect may be caused by surface soiling/dust buildup, localized heating (hotspot), or a connector/junction issue leading to reduced effective output.''';
