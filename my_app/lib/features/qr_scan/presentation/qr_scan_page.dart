import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/api/api_config.dart';
import '../../../core/panel_qr.dart';
import '../../panel_snapshot/presentation/panel_qr_report_page.dart';
import '../../panel_snapshot/presentation/genai_analysis_page.dart';

/// Matches backend / web: |I| > 50 → milliamps, else amps.
double _currentToAmps(num raw) {
  final x = raw.abs().toDouble();
  final v = raw.toDouble();
  return x > 50 ? v / 1000.0 : v;
}

class _IvChannel {
  const _IvChannel({
    required this.index,
    required this.voltage,
    required this.currentAmps,
    required this.powerW,
    required this.rawCurrent,
    required this.fromMilliamps,
  });

  final int index;
  final double voltage;
  final double currentAmps;
  final double powerW;
  final num rawCurrent;
  final bool fromMilliamps;
}

class _QrParseResult {
  const _QrParseResult({
    this.headline,
    required this.lines,
    this.error,
    this.ivChannels,
  });

  final String? headline;
  final List<String> lines;
  final String? error;
  final List<_IvChannel>? ivChannels;
}

_QrParseResult _parseQrPayload(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const _QrParseResult(lines: [], error: 'Empty QR payload.');
  }

  final direct = num.tryParse(trimmed);
  if (direct != null) {
    return _QrParseResult(headline: 'Reading', lines: [direct.toString()], error: null);
  }

  dynamic decoded;
  try {
    decoded = jsonDecode(trimmed);
  } catch (_) {
    return _QrParseResult(lines: [], error: 'Payload is not valid JSON.');
  }

  if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
    decoded = decoded.first;
  }

  if (decoded is! Map) {
    return const _QrParseResult(lines: [], error: 'Expected a JSON object (or array of one object).');
  }

  final map = Map<String, dynamic>.from(decoded);

  for (final key in ['sensor_value', 'sensorValue', 'value', 'reading', 'sensor']) {
    final v = map[key];
    if (v == null) continue;
    if (v is num) {
      return _QrParseResult(headline: 'Sensor', lines: ['$v'], error: null);
    }
    final p = num.tryParse(v.toString());
    if (p != null) {
      return _QrParseResult(headline: 'Sensor', lines: [p.toString()], error: null);
    }
  }

  final hasIv = ['I1', 'V1', 'I2', 'V2', 'I3', 'V3', 'I4', 'V4'].any(map.containsKey);
  if (hasIv) {
    final lines = <String>[];
    final channels = <_IvChannel>[];
    double? firstPower;

    for (var i = 1; i <= 4; i++) {
      final ik = 'I$i';
      final vk = 'V$i';
      if (!map.containsKey(ik) && !map.containsKey(vk)) continue;

      final iv = map[ik];
      final vv = map[vk];
      if (iv == null || vv == null) continue;

      final iNum = num.tryParse(iv.toString());
      final vNum = num.tryParse(vv.toString());
      if (iNum == null || vNum == null) continue;

      final fromMa = iNum.abs() > 50;
      final ia = _currentToAmps(iNum);
      final vd = vNum.toDouble();
      final p = ia * vd;
      if (i == 1) firstPower = p;

      channels.add(_IvChannel(
        index: i,
        voltage: vd,
        currentAmps: ia,
        powerW: p,
        rawCurrent: iNum,
        fromMilliamps: fromMa,
      ));

      final iLabel = fromMa ? '${iNum.toString()} mA → ${ia.toStringAsFixed(3)} A' : '${ia.toStringAsFixed(3)} A';

      lines.add('Channel $i: ${vd.toStringAsFixed(2)} V · $iLabel');
      lines.add('  Power ≈ ${p.toStringAsFixed(4)} W');
    }

    if (lines.isEmpty) {
      return const _QrParseResult(lines: [], error: 'IV keys present but could not read numeric I/V pairs.');
    }

    final head = firstPower != null
        ? 'Est. power (ch 1): ${firstPower.toStringAsFixed(4)} W'
        : 'Solar IV readings';

    return _QrParseResult(headline: head, lines: lines, error: null, ivChannels: channels);
  }

  return _QrParseResult(
    lines: [],
    error: 'No known sensor fields (value / IV channels I1·V1 …) found.',
  );
}

class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  String? _raw;
  _QrParseResult? _lastParse;

  @override
  void initState() {
    super.initState();
    // URL comes from `ApiConfig.fastApiBaseUrl` / `--dart-define=FASTAPI_BASE_URL=...` only.
    ApiConfig.runtimeBaseOverride = '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!mounted) return;

    final barcode = capture.barcodes.firstWhere(
      (b) => (b.rawValue ?? '').trim().isNotEmpty,
      orElse: () => const Barcode(rawValue: null),
    );

    final raw = barcode.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    final parsed = _parseQrPayload(raw);

    setState(() {
      _raw = raw;
      _lastParse = parsed;
    });
  }

  static const _scannerBg = Color(0xFF0C1222);
  static const _accent = Color(0xFF0EA5E9);
  static const _sheetTop = Color(0xFFE8EEF4);
  static const _sheetBg = Color(0xFFF8FAFC);

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _scannerBg,
      body: Column(
        children: [
          Expanded(
            flex: 12,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: _scannerBg,
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                  ),
                ),
                // Bottom fade so the sheet edge feels connected, not harsh.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 56,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _scannerBg.withValues(alpha: 0),
                          _scannerBg.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 36),
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.25),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            _ScannerIconButton(
                              icon: Icons.flash_on_rounded,
                              tooltip: 'Torch',
                              onPressed: () => _controller.toggleTorch(),
                            ),
                            const Spacer(),
                            _ScannerIconButton(
                              icon: Icons.cameraswitch_rounded,
                              tooltip: 'Switch camera',
                              onPressed: () => _controller.switchCamera(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                            ),
                            child: const Text(
                              'Align the QR code inside the frame',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 12,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_sheetTop, _sheetBg],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 6),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Scan result',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: _lastParse == null && _raw == null
                          ? _EmptyScanHint(bottomInset: bottomInset)
                          : SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
                              child: _ScanResultContent(
                                parse: _lastParse,
                                raw: _raw,
                                panelIdGuess: tryExtractPanelId(_raw ?? ''),
                                onOpenReport: (panelId) {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PanelQrReportPage(panelId: panelId),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerIconButton extends StatelessWidget {
  const _ScannerIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 22),
        padding: const EdgeInsets.all(10),
      ),
    );
  }
}

class _EmptyScanHint extends StatelessWidget {
  const _EmptyScanHint({required this.bottomInset});

  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final compact = h < 260;
        final iconSize = compact ? 40.0 : 48.0;
        final titleSize = compact ? 16.0 : 17.0;
        final bodySize = compact ? 12.0 : 13.0;

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12 + bottomInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: h > 0 ? h : 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.medical_information_rounded,
                  size: iconSize,
                  color: const Color(0xFF16A34A).withValues(alpha: 0.75),
                ),
                SizedBox(height: compact ? 8 : 12),
                Text(
                  'Health report',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: titleSize + 1,
                    color: Colors.grey.shade900,
                  ),
                ),
                SizedBox(height: compact ? 6 : 8),
                Text(
                  'Scan a panel QR code to open the full report.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                    fontSize: bodySize,
                    height: 1.35,
                  ),
                ),
                SizedBox(height: compact ? 8 : 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 10 : 12),
                    child: SelectableText(
                      'PANEL_001\nor\n{"I1": 122, "V1": 0.16}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.blueGrey.shade800,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScanResultContent extends StatelessWidget {
  const _ScanResultContent({
    required this.parse,
    required this.raw,
    required this.panelIdGuess,
    required this.onOpenReport,
  });

  final _QrParseResult? parse;
  final String? raw;
  final String? panelIdGuess;
  final ValueChanged<String> onOpenReport;

  @override
  Widget build(BuildContext context) {
    final p = parse;
    final channels = p?.ivChannels;
    final panelId = panelIdGuess ?? (raw != null ? tryExtractPanelId(raw!) : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (panelId != null) ...[
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => onOpenReport(panelId),
            icon: const Icon(Icons.medical_information_rounded),
            label: const Text('OPEN FULL HEALTH REPORT', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GenaiAnalysisPage(panelId: panelId))),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('OPEN GENAI ANALYSIS', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 14),
          Text(
            'Panel id: $panelId',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 12),
        ],
        if (p?.headline != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              p!.headline!,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        if (p?.error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p!.error!,
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (channels != null && channels.isNotEmpty) ...[
          const SizedBox(height: 4),
          ...channels.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ChannelMetricCard(channel: c),
              )),
        ] else if (p?.lines.isNotEmpty == true) ...[
          const SizedBox(height: 4),
          ...p!.lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                line,
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
        if (raw != null) ...[
          const SizedBox(height: 14),
          Text(
            'Raw payload',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: SelectableText(
              raw!,
              style: TextStyle(
                color: Colors.blueGrey.shade800,
                fontWeight: FontWeight.w500,
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.45,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChannelMetricCard extends StatelessWidget {
  const _ChannelMetricCard({required this.channel});

  final _IvChannel channel;

  @override
  Widget build(BuildContext context) {
    final c = channel;
    final iStr = c.fromMilliamps
        ? '${c.rawCurrent} mA (${c.currentAmps.toStringAsFixed(3)} A)'
        : '${c.currentAmps.toStringAsFixed(3)} A';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Channel ${c.index}',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              color: Colors.grey.shade700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MetricChip(
                  label: 'Voltage',
                  value: '${c.voltage.toStringAsFixed(2)} V',
                  icon: Icons.bolt_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricChip(
                  label: 'Current',
                  value: iStr,
                  icon: Icons.electric_bolt_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Power (est.)',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
                Text(
                  '${c.powerW.toStringAsFixed(4)} W',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: Color(0xFF0369A1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: Color(0xFF0F172A),
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
