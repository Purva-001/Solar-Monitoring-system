import 'package:equatable/equatable.dart';

class PanelInfo extends Equatable {
  const PanelInfo({
    required this.panelId,
    required this.voltageV1,
    required this.voltageV2,
    required this.voltageV3,
    required this.powerP1,
    required this.powerP2,
    required this.powerP3,
    required this.currentI,
    required this.requiresAnalysis,
    required this.message,
  });

  final String panelId;
  final double voltageV1;
  final double voltageV2;
  final double voltageV3;
  final double powerP1;
  final double powerP2;
  final double powerP3;
  final double currentI;
  final bool requiresAnalysis;
  final String message;

  @override
  List<Object?> get props => [
        panelId,
        voltageV1,
        voltageV2,
        voltageV3,
        powerP1,
        powerP2,
        powerP3,
        currentI,
        requiresAnalysis,
        message,
      ];
}
