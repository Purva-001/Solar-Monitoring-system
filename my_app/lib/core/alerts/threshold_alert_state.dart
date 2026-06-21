import 'package:equatable/equatable.dart';

class ThresholdAlert extends Equatable {
  const ThresholdAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.occurredAt,
  });

  final String id;
  final String title;
  final String message;
  final ThresholdSeverity severity;
  final DateTime occurredAt;

  @override
  List<Object?> get props => [id, title, message, severity, occurredAt];
}

enum ThresholdSeverity { info, warning, critical }

sealed class ThresholdAlertState extends Equatable {
  const ThresholdAlertState();

  @override
  List<Object?> get props => [];
}

class ThresholdAlertIdle extends ThresholdAlertState {
  const ThresholdAlertIdle();
}

class ThresholdAlertEmitted extends ThresholdAlertState {
  const ThresholdAlertEmitted(this.alert);

  final ThresholdAlert alert;

  @override
  List<Object?> get props => [alert];
}
