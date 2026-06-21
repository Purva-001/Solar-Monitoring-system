import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'camera_feed_state.dart';

class CameraFeedCubit extends Cubit<CameraFeedState> {
  CameraFeedCubit({int refreshMs = 5000})
      : _refreshMs = refreshMs,
        super(CameraFeedRunning(tickMs: DateTime.now().millisecondsSinceEpoch, zoom: 1.0));

  final int _refreshMs;
  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: _refreshMs), (_) {
      final s = state;
      if (s is CameraFeedRunning) {
        emit(CameraFeedRunning(tickMs: DateTime.now().millisecondsSinceEpoch, zoom: s.zoom));
      }
    });
  }

  void refreshNow() {
    final s = state;
    if (s is CameraFeedRunning) {
      emit(CameraFeedRunning(tickMs: DateTime.now().millisecondsSinceEpoch, zoom: s.zoom));
    }
  }

  void setZoom(double value) {
    final s = state;
    if (s is CameraFeedRunning) {
      final next = value.clamp(1.0, 3.0);
      emit(CameraFeedRunning(tickMs: s.tickMs, zoom: next));
    }
  }

  void zoomIn() {
    final s = state;
    if (s is CameraFeedRunning) {
      setZoom(s.zoom + 0.2);
    }
  }

  void zoomOut() {
    final s = state;
    if (s is CameraFeedRunning) {
      setZoom(s.zoom - 0.2);
    }
  }

  void resetZoom() {
    final s = state;
    if (s is CameraFeedRunning) {
      emit(CameraFeedRunning(tickMs: s.tickMs, zoom: 1.0));
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
