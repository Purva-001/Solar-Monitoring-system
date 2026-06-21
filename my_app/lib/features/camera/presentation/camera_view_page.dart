import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_config.dart';
import '../state/camera_feed_cubit.dart';
import '../state/camera_feed_state.dart';
import 'camera_feed_card.dart';

class CameraViewPage extends StatelessWidget {
  const CameraViewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CameraFeedCubit(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'AI Visual Inspection',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          centerTitle: false,
        ),
        body: Container(
          color: const Color(0xFFEFF6FF),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CameraFeedSection(),
                const SizedBox(height: 20),
                _CameraControlsSection(),
                const SizedBox(height: 20),
                _CameraInfoSection(),
                const SizedBox(height: 20),
                _CameraHistorySection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraFeedSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CameraFeedCubit, CameraFeedState>(
      builder: (context, state) {
        if (state is CameraFeedRunning) {
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                color: Colors.white,
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Live Camera Feed',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.45)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 8, color: Color(0xFF22C55E)),
                            SizedBox(width: 6),
                            Text(
                              'LIVE',
                              style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF166534), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(14)),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Container(
                        color: const Color(0xFFF1F5F9),
                        child: Center(
                          child: Transform.scale(
                            scale: state.zoom,
                            child: _CameraImage(
                              feedUrl: ApiConfig.getCameraFeedUrl(state.tickMs),
                              panelId: 'Panel-P01',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Panel: Panel-P01',
                        style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Zoom: ${state.zoom.toStringAsFixed(1)}x',
                        style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _CameraControlsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Camera Controls',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ControlButton(
                  label: 'Zoom In',
                  icon: Icons.add_circle_outline_rounded,
                  color: AppTheme.brandGreen,
                  onPressed: () => context.read<CameraFeedCubit>().zoomIn(),
                ),
                _ControlButton(
                  label: 'Zoom Out',
                  icon: Icons.remove_circle_outline_rounded,
                  color: const Color(0xFF2563EB),
                  onPressed: () => context.read<CameraFeedCubit>().zoomOut(),
                ),
                _ControlButton(
                  label: 'Refresh Feed',
                  icon: Icons.refresh_rounded,
                  color: const Color(0xFFF59E0B),
                  onPressed: () => context.read<CameraFeedCubit>().refreshNow(),
                ),
                _ControlButton(
                  label: 'Reset Zoom',
                  icon: Icons.fit_screen_rounded,
                  color: const Color(0xFF7C3AED),
                  onPressed: () => context.read<CameraFeedCubit>().resetZoom(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            BlocBuilder<CameraFeedCubit, CameraFeedState>(
              builder: (context, state) {
                if (state is CameraFeedRunning) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Zoom Level',
                            style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
                          ),
                          Text(
                            '${state.zoom.toStringAsFixed(2)}x',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: (state.zoom - 1.0) / 4.0,
                          minHeight: 8,
                          backgroundColor: const Color(0xFFE2E8F0),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            state.zoom > 2.0 ? const Color(0xFFF59E0B) : AppTheme.brandGreen,
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            border: Border.all(color: color.withValues(alpha: 0.3)),
            color: color.withValues(alpha: 0.08),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraInfoSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Camera Information',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 16),
            _InfoRow(label: 'Panel ID', value: 'Panel-P01'),
            const SizedBox(height: 12),
            _InfoRow(label: 'Status', value: 'Active'),
            const SizedBox(height: 12),
            _InfoRow(label: 'Resolution', value: '1920x1080 (16:9)'),
            const SizedBox(height: 12),
            _InfoRow(label: 'Refresh Rate', value: '1 frame/sec'),
            const SizedBox(height: 12),
            _InfoRow(label: 'Last Update', value: DateTime.now().toString().split('.')[0]),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
        ),
      ],
    );
  }
}

class _CameraHistorySection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Captures',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 5,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.only(right: index < 4 ? 12 : 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 120,
                        color: const Color(0xFFF1F5F9),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.image_rounded,
                              size: 32,
                              color: const Color(0xFF64748B),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${DateTime.now().subtract(Duration(minutes: index * 5)).hour}:${DateTime.now().subtract(Duration(minutes: index * 5)).minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraImage extends StatefulWidget {
  const _CameraImage({
    required this.feedUrl,
    required this.panelId,
  });

  final String feedUrl;
  final String panelId;

  @override
  State<_CameraImage> createState() => _CameraImageState();
}

class _CameraImageState extends State<_CameraImage> {
  @override
  Widget build(BuildContext context) {
    return Image.network(
      widget.feedUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: const Color(0xFFF1F5F9),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.no_photography,
                size: 48,
                color: const Color(0xFF94A3B8),
              ),
              const SizedBox(height: 12),
              const Text(
                'Camera Feed Unavailable',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Check camera connection',
                style: TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
