import 'package:equatable/equatable.dart';

class SolarHistoryPoint extends Equatable {
  const SolarHistoryPoint({
    required this.tsMs,
    required this.v1,
    required this.v2,
    required this.v3,
    required this.v4,
    required this.p1,
    required this.p2,
    required this.p3,
    required this.p4,
    required this.i,
    required this.i1Ma,
    required this.i2Ma,
    required this.i3Ma,
    required this.i4Ma,
  });

  final int tsMs;
  final double? v1;
  final double? v2;
  final double? v3;
  final double? v4;
  final double? p1;
  final double? p2;
  final double? p3;
  final double? p4;
  /// Total current for aggregate chart (milliamps).
  final double? i;
  /// Per-channel current (mA) when API sends I1–I4; used for I–V snapshots.
  final double? i1Ma;
  final double? i2Ma;
  final double? i3Ma;
  final double? i4Ma;

  @override
  List<Object?> get props => [tsMs, v1, v2, v3, v4, p1, p2, p3, p4, i, i1Ma, i2Ma, i3Ma, i4Ma];
}
