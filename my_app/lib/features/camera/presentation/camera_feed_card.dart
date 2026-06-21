import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_config.dart';
import '../state/camera_feed_cubit.dart';
import '../state/camera_feed_state.dart';

class CameraFeedCard extends StatelessWidget {
  const CameraFeedCard({super.key, required this.panelId});

  final String panelId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CameraFeedCubit, CameraFeedState>(
      builder: (context, state) {
        final s = state as CameraFeedRunning;
        final feedUrl = _esp32LatestJpgUrl(s.tickMs);
        final fallback1 = _latestUploadFallbackUrl(s.tickMs);
        final fallback2 = _captureImageUrl('image1.jpg');
        final fallback3 = _captureImageUrl('image2.jpg');

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('AI Visual Inspection', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  IconButton(
                    onPressed: () => context.read<CameraFeedCubit>().zoomOut(),
                    icon: const Icon(Icons.remove),
                    tooltip: 'Zoom out',
                  ),
                  IconButton(
                    onPressed: () => context.read<CameraFeedCubit>().zoomIn(),
                    icon: const Icon(Icons.add),
                    tooltip: 'Zoom in',
                  ),
                  IconButton(
                    onPressed: () => context.read<CameraFeedCubit>().refreshNow(),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(14)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    color: const Color(0xFFF1F5F9),
                    child: Center(
                      child: Transform.scale(
                        scale: s.zoom,
                        child: _ImageWithFallback(
                          primaryUrl: feedUrl,
                          fallbackUrl: fallback1,
                          secondaryFallbackUrl: fallback2,
                          tertiaryFallbackUrl: fallback3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Panel: $panelId',
                      style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    'Zoom: ${s.zoom.toStringAsFixed(1)}x',
                    style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }
}

class _ImageWithFallback extends StatefulWidget {
  const _ImageWithFallback({
    required this.primaryUrl,
    required this.fallbackUrl,
    required this.secondaryFallbackUrl,
    this.tertiaryFallbackUrl,
  });

  final String primaryUrl;
  final String fallbackUrl;
  final String secondaryFallbackUrl;
  final String? tertiaryFallbackUrl;

  @override
  State<_ImageWithFallback> createState() => _ImageWithFallbackState();
}

class _ImageWithFallbackState extends State<_ImageWithFallback> {
  int _fallbackStep = 0;

  @override
  Widget build(BuildContext context) {
    final candidates = <String>[
      widget.primaryUrl,
      widget.fallbackUrl,
      widget.secondaryFallbackUrl,
      if (widget.tertiaryFallbackUrl != null) widget.tertiaryFallbackUrl!,
    ];
    final idx = _fallbackStep.clamp(0, candidates.length - 1);
    final url = candidates[idx];
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (context, _, __) {
        if (_fallbackStep < candidates.length - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _fallbackStep += 1);
          });
          return const SizedBox.shrink();
        }
        return const Center(
          child: Text(
            'Camera feed unavailable',
            style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800),
          ),
        );
      },
    );
  }
}

String _esp32LatestJpgUrl(int tickMs) {
  final raw = ApiConfig.esp32CameraUrl.trim();
  if (raw.isEmpty) return _latestUploadFallbackUrl(tickMs);
  final u = Uri.parse(raw);
  final qp = Map<String, String>.from(u.queryParameters);
  qp['t'] = tickMs.toString();
  return u.replace(queryParameters: qp).toString();
}

String _latestUploadFallbackUrl(int tickMs) {
  final base = Uri.parse(ApiConfig.fastApiBaseUrl);
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: '/api/camera/latest-upload',
    queryParameters: {'t': tickMs.toString()},
  ).toString();
}

String _captureImageUrl(String fileName) {
  final base = Uri.parse(ApiConfig.fastApiBaseUrl);
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: '/captures/$fileName',
  ).toString();
}
