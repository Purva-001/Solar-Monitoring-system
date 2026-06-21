import 'package:equatable/equatable.dart';

import '../domain/health_report_models.dart';

sealed class HealthReportState extends Equatable {
  const HealthReportState();

  @override
  List<Object?> get props => [];
}

class HealthReportLoading extends HealthReportState {
  const HealthReportLoading();
}

class HealthReportLoaded extends HealthReportState {
  const HealthReportLoaded({
    required this.report,
    this.weather,
    this.readings,
  });

  final HealthReport report;
  final Map<String, dynamic>? weather;
  final Map<String, dynamic>? readings;

  @override
  List<Object?> get props => [report, weather, readings];
}

class HealthReportError extends HealthReportState {
  const HealthReportError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
