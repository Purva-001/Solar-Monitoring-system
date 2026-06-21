import 'package:equatable/equatable.dart';

class MaintenanceComparison extends Equatable {
  const MaintenanceComparison({
    required this.panelId,
    required this.channelIdx,
    required this.beforePowerW,
    required this.afterPowerWStored,
    required this.liveChannelPowerW,
    required this.beforeStatus,
    required this.afterStatus,
    required this.beforeDeviationPct,
    required this.afterDeviationPct,
    this.completedAtIso,
    this.beforeImageUrl,
    this.afterImageUrl,
  });

  final String panelId;
  /// Channel index 1–4 derived from panel ID suffix (-P01..-P04).
  final int channelIdx;
  final double? beforePowerW;
  /// Stored after-cleaning power from comparison snapshots (nullable; may be missing before first run).
  final double? afterPowerWStored;
  /// Latest live power reading (W) for the selected channel (nullable if polling fails).
  final double? liveChannelPowerW;
  final String beforeStatus;
  final String afterStatus;
  final double beforeDeviationPct;
  final double afterDeviationPct;
  final String? completedAtIso;
  final String? beforeImageUrl;
  final String? afterImageUrl;

  double? get afterPowerW => afterPowerWStored ?? liveChannelPowerW;

  double get improvementPct {
    final pb = beforePowerW;
    final pa = afterPowerW;
    if (pb == null || pa == null) return 0;
    if (pb.abs() < 1e-9) return 0;
    return ((pa - pb) / pb) * 100;
  }

  double get energyRecoveredWh {
    final pb = beforePowerW;
    final pa = afterPowerW;
    if (pb == null || pa == null) return 0;
    return pa - pb;
  }

  /// React parity: Resolved > 10%, Monitor >= 3%, else Escalate.
  String get verificationStatus {
    final imp = improvementPct;
    if (imp > 10) return 'Resolved';
    if (imp >= 3) return 'Monitor';
    return 'Escalate';
  }

  @override
  List<Object?> get props => [
        panelId,
        channelIdx,
        beforePowerW,
        afterPowerWStored,
        liveChannelPowerW,
        beforeStatus,
        afterStatus,
        beforeDeviationPct,
        afterDeviationPct,
        completedAtIso,
        beforeImageUrl,
        afterImageUrl,
      ];
}
