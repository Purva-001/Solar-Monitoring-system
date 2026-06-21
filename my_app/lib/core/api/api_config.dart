class ApiConfig {
  /// This PC on LAN (phone on same Wi‑Fi). Override: `--dart-define=FASTAPI_BASE_URL=http://127.0.0.1:8000`
  /// or Android emulator `http://10.0.2.2:8000`.
  static const String fastApiBaseUrl = String.fromEnvironment(
    'FASTAPI_BASE_URL',
    defaultValue: 'http:///192.168.0.103:8000',
  );

  static const String esp32CameraUrl = String.fromEnvironment(
    'ESP32_CAMERA_URL',
    defaultValue: 'http:///192.168.0.103:8000/images/latest.jpg',
  );

  /// Prefer loading **live I1–I4 / V1–V4** through FastAPI (`/api/panel/readings`, `/panel/{id}`) which
  /// proxies `AWS_API_ENDPOINT` on the server — keeps keys off the mobile app.
  static const String liveReadingsUrl = String.fromEnvironment(
    'LIVE_READINGS_URL',
    defaultValue: 'https://ay8w848sv5.execute-api.us-east-1.amazonaws.com/default/solar-data',
  );

  /// Runtime override (e.g. from a small settings sheet). Empty → use [fastApiBaseUrl].
  static String runtimeBaseOverride = '';

  static String get effectiveBaseUrl {
    final r = runtimeBaseOverride.trim();
    if (r.isNotEmpty) return r.contains('://') ? r : 'http://$r';
    return fastApiBaseUrl.trim();
  }

  static String getCameraFeedUrl(int tickMs) {
    return '$esp32CameraUrl?t=$tickMs';
  }

  static String getHealthMetricsUrl() {
    return '$effectiveBaseUrl/api/health/metrics';
  }

  static String getHealthPanelsUrl() {
    return '$effectiveBaseUrl/api/health/panels';
  }

  static String getHealthRecommendationsUrl() {
    return '$effectiveBaseUrl/api/health/recommendations';
  }

  static const String esp32ControlUrl = String.fromEnvironment(
    'ESP32_CONTROL_URL',
    defaultValue: 'http://10.14.20.80',
  );

  static const String esp32ServoOnPath = String.fromEnvironment(
    'ESP32_SERVO_ON_PATH',
    defaultValue: '/servo?pos=180',
  );

  static const String esp32ServoOffPath = String.fromEnvironment(
    'ESP32_SERVO_OFF_PATH',
    defaultValue: '/servo?pos=0',
  );

  static const int esp32ServoAutoOffSeconds = int.fromEnvironment(
    'ESP32_SERVO_AUTO_OFF_SECONDS',
    defaultValue: 5,
  );

  static String getServoUrl(bool on) {
    return '$esp32ControlUrl${on ? esp32ServoOnPath : esp32ServoOffPath}';
  }

  static const int httpRequestTimeoutSeconds = 10;
}
