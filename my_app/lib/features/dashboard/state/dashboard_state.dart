import 'package:equatable/equatable.dart';

import '../domain/dashboard_models.dart';
import '../domain/panel_models.dart';

sealed class DashboardState extends Equatable {
  const DashboardState();

  @override
  List<Object?> get props => [];
}

class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

class DashboardLoaded extends DashboardState {
  const DashboardLoaded({required this.panels, required this.readings, required this.powerSeries, required this.lastUpdated});

  final List<PanelSummary> panels;
  final DashboardReadings readings;
  final List<PowerPoint> powerSeries;
  final DateTime lastUpdated;

  @override
  List<Object?> get props => [panels, readings, powerSeries, lastUpdated];
}

class DashboardError extends DashboardState {
  const DashboardError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
