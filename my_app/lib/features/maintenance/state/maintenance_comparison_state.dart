import 'package:equatable/equatable.dart';

import '../domain/maintenance_models.dart';

sealed class MaintenanceComparisonState extends Equatable {
  const MaintenanceComparisonState();

  @override
  List<Object?> get props => [];
}

class MaintenanceComparisonLoading extends MaintenanceComparisonState {
  const MaintenanceComparisonLoading();
}

class MaintenanceComparisonLoaded extends MaintenanceComparisonState {
  const MaintenanceComparisonLoaded(this.data);

  final MaintenanceComparison data;

  @override
  List<Object?> get props => [data];
}

class MaintenanceComparisonRunning extends MaintenanceComparisonState {
  const MaintenanceComparisonRunning({
    required this.data,
    required this.countdownSeconds,
  });

  final MaintenanceComparison data;
  final int countdownSeconds;

  @override
  List<Object?> get props => [data, countdownSeconds];
}

class MaintenanceComparisonError extends MaintenanceComparisonState {
  const MaintenanceComparisonError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
