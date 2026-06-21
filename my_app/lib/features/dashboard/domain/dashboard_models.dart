import 'package:equatable/equatable.dart';

class DashboardReadings extends Equatable {
  const DashboardReadings({
    required this.v1,
    required this.v2,
    required this.v3,
    required this.v4,
    required this.p1,
    required this.p2,
    required this.p3,
    required this.p4,
    this.c1,
    this.c2,
    this.c3,
    this.c4,
    required this.current,
    required this.timestampIso,
    required this.panelChannelCount,
  });

  final double v1;
  final double v2;
  final double v3;
  final double v4;
  final double p1;
  final double p2;
  final double p3;
  final double p4;
  /// Per-string branch current in milliamps (from API `panelNcurrent` when available).
  /// Nullable so stale instances after hot reload (or partial payloads) do not throw on web.
  final double? c1;
  final double? c2;
  final double? c3;
  final double? c4;
  /// Total string current in milliamps (sum of branch currents).
  final double current;
  final String timestampIso;
  /// Channels present in the payload (1–4); defaults to 4 when none detected (React parity).
  final int panelChannelCount;

  double get totalPowerW => (p1.abs() + p2.abs() + p3.abs() + p4.abs());

  @override
  List<Object?> get props =>
      [v1, v2, v3, v4, p1, p2, p3, p4, c1, c2, c3, c4, current, timestampIso, panelChannelCount];
}

class PowerPoint extends Equatable {
  const PowerPoint({required this.tsMs, required this.w});

  final int tsMs;
  final double w;

  @override
  List<Object?> get props => [tsMs, w];
}
