import 'package:equatable/equatable.dart';

import '../../solar_history/domain/solar_history_models.dart';

sealed class HistoricalAnalysisState extends Equatable {
  const HistoricalAnalysisState();

  @override
  List<Object?> get props => [];
}

class HistoricalAnalysisLoading extends HistoricalAnalysisState {
  const HistoricalAnalysisLoading();
}

class HistoricalAnalysisLoaded extends HistoricalAnalysisState {
  const HistoricalAnalysisLoaded({required this.assetId, required this.points, required this.lastUpdated});

  final String assetId;
  final List<SolarHistoryPoint> points;
  final DateTime lastUpdated;

  @override
  List<Object?> get props => [assetId, points, lastUpdated];
}

class HistoricalAnalysisError extends HistoricalAnalysisState {
  const HistoricalAnalysisError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
