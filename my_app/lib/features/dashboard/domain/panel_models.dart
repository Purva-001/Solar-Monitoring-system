import 'package:equatable/equatable.dart';

class PanelSummary extends Equatable {
  const PanelSummary({
    required this.id,
    required this.name,
    required this.location,
    required this.capacity,
    required this.currentOutput,
    required this.healthScore,
  });

  final String id;
  final String name;
  final String location;
  final double? capacity;
  final double? currentOutput;
  final double? healthScore;

  @override
  List<Object?> get props => [id, name, location, capacity, currentOutput, healthScore];
}
