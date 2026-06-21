import 'package:equatable/equatable.dart';

class PredictiveMaintenance extends Equatable {
  const PredictiveMaintenance({
    required this.panelId,
    required this.maintenancePriority,
    required this.trend,
    required this.predictedEfficiency30Days,
    required this.predictedEfficiency90Days,
    required this.nextMaintenanceRecommendedDays,
    required this.timestampIso,
  });

  final String panelId;
  final String maintenancePriority;
  final String trend;
  final double predictedEfficiency30Days;
  final double predictedEfficiency90Days;
  final int nextMaintenanceRecommendedDays;
  final String timestampIso;

  @override
  List<Object?> get props => [
        panelId,
        maintenancePriority,
        trend,
        predictedEfficiency30Days,
        predictedEfficiency90Days,
        nextMaintenanceRecommendedDays,
        timestampIso,
      ];
}
