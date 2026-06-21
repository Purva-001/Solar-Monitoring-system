import 'package:equatable/equatable.dart';

sealed class CameraFeedState extends Equatable {
  const CameraFeedState();

  @override
  List<Object?> get props => [];
}

class CameraFeedRunning extends CameraFeedState {
  const CameraFeedRunning({required this.tickMs, required this.zoom});

  final int tickMs;
  final double zoom;

  @override
  List<Object?> get props => [tickMs, zoom];
}
