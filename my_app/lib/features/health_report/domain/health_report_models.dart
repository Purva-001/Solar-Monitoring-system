import 'package:equatable/equatable.dart';

class Reading extends Equatable {
  const Reading({required this.value, required this.timestamp});

  final double value;
  final int timestamp;

  @override
  List<Object?> get props => [value, timestamp];
}

class TopPrediction extends Equatable {
  const TopPrediction({required this.label, required this.score});

  final String label;
  final double score;

  @override
  List<Object?> get props => [label, score];
}

class DefectAnalysis extends Equatable {
  const DefectAnalysis({required this.defect, required this.confidence, required this.topPredictions});

  final String defect;
  final double confidence;
  final List<TopPrediction> topPredictions;

  @override
  List<Object?> get props => [defect, confidence, topPredictions];
}

class PowerTrigger extends Equatable {
  const PowerTrigger({
    required this.p1Value,
    required this.p2Value,
    required this.p3Value,
    required this.threshold,
    required this.status,
    required this.message,
  });

  final double p1Value;
  final double p2Value;
  final double p3Value;
  final double threshold;
  final String status;
  final String message;

  @override
  List<Object?> get props => [p1Value, p2Value, p3Value, threshold, status, message];
}

class SensorData extends Equatable {
  const SensorData({required this.v1, required this.v2, required this.v3, required this.p1, required this.p2, required this.p3, required this.i});

  final Reading v1;
  final Reading v2;
  final Reading v3;
  final Reading p1;
  final Reading p2;
  final Reading p3;
  final Reading i;

  @override
  List<Object?> get props => [v1, v2, v3, p1, p2, p3, i];
}

class HealthReport extends Equatable {
  const HealthReport({
    required this.status,
    required this.analysisTriggered,
    required this.panelId,
    required this.timestampIso,
    required this.powerTrigger,
    required this.defectAnalysis,
    required this.knowledgeContext,
    required this.healthReportMarkdown,
    required this.aiSummaryMarkdown,
    required this.aiRecommendationsMarkdown,
    required this.aiRootCauseMarkdown,
    required this.sensorData,
    required this.geminiError,
  });

  final String status;
  final bool analysisTriggered;
  final String panelId;
  final String timestampIso;
  final PowerTrigger powerTrigger;
  final DefectAnalysis defectAnalysis;
  final String knowledgeContext;
  final String healthReportMarkdown;
  final String? aiSummaryMarkdown;
  final String? aiRecommendationsMarkdown;
  final String? aiRootCauseMarkdown;
  final SensorData sensorData;
  final String? geminiError;

  @override
  List<Object?> get props => [
        status,
        analysisTriggered,
        panelId,
        timestampIso,
        powerTrigger,
        defectAnalysis,
        knowledgeContext,
        healthReportMarkdown,
        aiSummaryMarkdown,
        aiRecommendationsMarkdown,
        aiRootCauseMarkdown,
        sensorData,
        geminiError,
      ];
}

extension HealthReportServoHelpers on HealthReport {
  /// Quick heuristic: AI suggests cleaning if health report or defect text mentions cleaning.
  bool get aiSuggestsCleaning {
    final d = defectAnalysis.defect.toLowerCase();
    final md = healthReportMarkdown.toLowerCase();
    return d.contains('dust') || d.contains('soiling') || md.contains('clean') || md.contains('cleaning');
  }
}
