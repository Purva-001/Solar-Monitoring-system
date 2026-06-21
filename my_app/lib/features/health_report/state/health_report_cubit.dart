import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../data/health_report_repository.dart';
import 'health_report_state.dart';

class HealthReportCubit extends Cubit<HealthReportState> {
  HealthReportCubit({HealthReportRepository? repository})
      : _repo = repository ?? HealthReportRepository(),
        super(const HealthReportLoading());

  final HealthReportRepository _repo;

  /// Send a request to the ESP32 to move the servo.
  ///
  /// Reads `SP32_CONTROL_URL` and `ESP32_SERVO_MOVE_PATH` from environment.
  /// If `ESP32_SERVO_MOVE_PATH` is not set, falls back to `ESP32_LED_ON_PATH`.
  Future<void> moveServo({int angle = 90}) async {
    try {
      final base = dotenv.env['SP32_CONTROL_URL'] ?? 'http://10.14.20.80';
      var path = dotenv.env['ESP32_SERVO_MOVE_PATH'] ?? dotenv.env['ESP32_LED_ON_PATH'] ?? '/led?on=1';

      // If the configured path contains a {angle} placeholder, substitute it.
      if (path.contains('{angle}')) {
        path = path.replaceAll('{angle}', angle.toString());
      } else {
        // Append angle as query parameter if not present
        if (path.contains('?')) {
          path = '$path&angle=$angle';
        } else {
          path = '$path?angle=$angle';
        }
      }

      final uri = Uri.parse('$base$path');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode < 200 || res.statusCode >= 400) {
        throw Exception('ESP32 request failed: ${res.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> load({String panelId = 'PL01-B02-INV03-STR05-P01', bool force = false}) async {
    try {
      if (isClosed) return;
      emit(const HealthReportLoading());
      final report = await _repo.fetchHealthReport(panelId: panelId, force: force);
      if (isClosed) return;
      Map<String, dynamic>? weather;
      Map<String, dynamic>? readings;

      try {
        weather = await _repo.fetchWeatherWardha();
      } catch (_) {
        weather = null;
      }
      if (isClosed) return;

      try {
        readings = await _repo.fetchReadings(panelId: panelId);
      } catch (_) {
        readings = null;
      }
      if (isClosed) return;

      emit(HealthReportLoaded(report: report, weather: weather, readings: readings));
    } catch (e) {
      if (isClosed) return;
      emit(HealthReportError(e.toString()));
    }
  }
}
