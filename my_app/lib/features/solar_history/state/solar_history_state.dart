import 'package:equatable/equatable.dart';

import '../domain/solar_history_models.dart';

sealed class SolarHistoryState extends Equatable {
  const SolarHistoryState();

  @override
  List<Object?> get props => [];
}

class SolarHistoryLoading extends SolarHistoryState {
  const SolarHistoryLoading();
}

class SolarHistoryLoaded extends SolarHistoryState {
  const SolarHistoryLoaded({
    required this.assetId,
    required this.points,
    required this.lastUpdated,
    this.ivPvPoint,
  });

  final String assetId;
  final List<SolarHistoryPoint> points;
  final DateTime lastUpdated;
  /// Live readings from `/api/solar-iv-pv` (AWS live endpoint); drives I–V / P–V like the React dashboard.
  final SolarHistoryPoint? ivPvPoint;

  @override
  List<Object?> get props => [assetId, points, lastUpdated, ivPvPoint];
}

class SolarHistoryError extends SolarHistoryState {
  const SolarHistoryError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
