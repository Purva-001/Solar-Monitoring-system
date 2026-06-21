import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/dashboard/domain/dashboard_models.dart';
import 'threshold_alert_state.dart';

typedef _Rule = ({
  String key,
  double Function(DashboardReadings) select,
  double? warnAbove,
  double? criticalAbove,
  double? criticalBelowOrEq,
  String unit,
});

class ThresholdAlertCubit extends Cubit<ThresholdAlertState> {
  ThresholdAlertCubit() : super(const ThresholdAlertIdle());

  final Map<String, int> _lastEmittedAtMsByKey = <String, int>{};

  static const int _cooldownMs = 60 * 1000;

  static const double _zeroEpsilon = 0.000001;

  final List<_Rule> _rules = <_Rule>[
    (key: 'v1_zero', select: (r) => r.v1, warnAbove: null, criticalAbove: null, criticalBelowOrEq: _zeroEpsilon, unit: 'V'),
    (key: 'v2_zero', select: (r) => r.v2, warnAbove: null, criticalAbove: null, criticalBelowOrEq: _zeroEpsilon, unit: 'V'),
  ];

  void onReadings(DashboardReadings readings) {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    for (final rule in _rules) {
      final v = rule.select(readings);
      final absV = v.abs();

      ThresholdSeverity? severity;
      if (rule.criticalBelowOrEq != null && absV <= rule.criticalBelowOrEq!) {
        severity = ThresholdSeverity.critical;
      } else if (rule.criticalAbove != null && absV >= rule.criticalAbove!) {
        severity = ThresholdSeverity.critical;
      } else if (rule.warnAbove != null && absV >= rule.warnAbove!) {
        severity = ThresholdSeverity.warning;
      }

      if (severity == null) continue;

      final lastMs = _lastEmittedAtMsByKey[rule.key];
      if (lastMs != null && (nowMs - lastMs) < _cooldownMs) {
        continue;
      }
      _lastEmittedAtMsByKey[rule.key] = nowMs;

      final title = switch (rule.key) {
        'v1_zero' || 'v2_zero' => 'Solar panel fault detected',
        _ => severity == ThresholdSeverity.critical ? 'Critical threshold reached' : 'Threshold reached',
      };

      final message = switch (rule.key) {
        'v1_zero' || 'v2_zero' => 'Solar panel became faulty. Please look into it.',
        _ => '${rule.key}: ${absV.toStringAsFixed(2)} ${rule.unit}',
      };

      emit(
        ThresholdAlertEmitted(
          ThresholdAlert(
            id: '${rule.key}-$nowMs',
            title: title,
            message: message,
            severity: severity,
            occurredAt: now,
          ),
        ),
      );

      emit(const ThresholdAlertIdle());
    }
  }
}
