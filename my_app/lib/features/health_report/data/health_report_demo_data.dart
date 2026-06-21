import '../domain/health_report_models.dart';

HealthReport demoHealthReport() {
  const ts = 1771500904;
  return HealthReport(
    status: 'analyzed',
    analysisTriggered: true,
    panelId: 'PL01-B02-INV03-STR05-P01',
    timestampIso: '2026-03-05T01:01:00.123456',
    powerTrigger: const PowerTrigger(
      p1Value: 4.34,
      p2Value: 6.84,
      p3Value: 6.84,
      threshold: 5.0,
      status: 'TRIGGERED',
      message: 'Power (P1/P2/P3) is below 5.0W',
    ),
    defectAnalysis: const DefectAnalysis(
      defect: 'Dusty',
      confidence: 0.94,
      topPredictions: [
        TopPrediction(label: 'Dusty', score: 0.94),
        TopPrediction(label: 'Bird-drop', score: 0.04),
        TopPrediction(label: 'Clean', score: 0.02),
      ],
    ),
    knowledgeContext:
        '[CONTEXT 1 | source=quality_standard.pdf | score=0.8123]\n...\n\n---\n\n[CONTEXT 2 | source=example_knowledge.txt | score=0.7741]\n...',
    healthReportMarkdown:
        '## Summary\n| Field | Value |\n|-------|-------|\n| **Panel ID** | PL01-B02-INV03-STR05-P01 |\n| **Defect Detected** | Dusty |\n| **Model Confidence** | 94.0% |\n| **Urgency Level** | 🟡 MEDIUM - Schedule cleaning within 1-2 weeks |\n| **Action Required** | Inspect & maintain |\n\n## Root Cause Analysis\n- Possible causes: ...\n\n## Recommendations\n- ...\n',
    sensorData: SensorData(
      v1: const Reading(value: 16.5, timestamp: ts),
      v2: const Reading(value: 18.5, timestamp: ts),
      v3: const Reading(value: 18.5, timestamp: ts),
      p1: const Reading(value: 4.34, timestamp: ts),
      p2: const Reading(value: 6.84, timestamp: ts),
      p3: const Reading(value: 6.84, timestamp: ts),
      i: const Reading(value: 312.9, timestamp: ts),
    ),
    geminiError: null,
  );
}
