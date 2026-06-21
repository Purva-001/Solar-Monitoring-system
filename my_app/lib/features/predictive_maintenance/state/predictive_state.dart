import 'package:equatable/equatable.dart';

import '../domain/predictive_models.dart';

sealed class PredictiveMaintenanceState extends Equatable {
  const PredictiveMaintenanceState();

  @override
  List<Object?> get props => [];
}

class PredictiveMaintenanceLoading extends PredictiveMaintenanceState {
  const PredictiveMaintenanceLoading();
}

class PredictiveMaintenanceLoaded extends PredictiveMaintenanceState {
  const PredictiveMaintenanceLoaded(this.data);

  final PredictiveMaintenance data;

  @override
  List<Object?> get props => [data];
}

class PredictiveMaintenanceError extends PredictiveMaintenanceState {
  const PredictiveMaintenanceError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
