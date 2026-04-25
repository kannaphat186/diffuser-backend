// app/lib/core/config/app_config.dart — v5.2.5 (Apr 2026)
// ─────────────────────────────────────────────────────────────
// FIX #1 (v5.2.5): public-internet backend support.
//
// Build-time strategy:
//
//   APP_ENV=prod (default)           → uses API_BASE_URL if supplied,
//                                      otherwise the public production
//                                      URL (_prodDefaultUrl). Never
//                                      silently falls back to a LAN IP.
//
//   APP_ENV=dev                      → uses API_BASE_URL if supplied,
//                                      otherwise _devDefaultUrl
//                                      (localhost-style). Safe for
//                                      `flutter run` on a real device
//                                      with the backend on the same
//                                      Wi-Fi — just pass
//                                      --dart-define=API_BASE_URL=
//                                      http://<your-lan-ip>:3000
//
// Typical release build:
//   flutter build apk --release \
//     --dart-define=APP_ENV=prod \
//     --dart-define=API_BASE_URL=https://diffuser-backend-1.onrender.com
//
// Typical dev build on a phone:
//   flutter run \
//     --dart-define=APP_ENV=dev \
//     --dart-define=API_BASE_URL=http://192.168.1.106:3000
//
// If you forget API_BASE_URL the app still works:
//   • prod build → talks to the public Render URL below
//   • dev build  → talks to localhost (desktop/emulator only)
// ─────────────────────────────────────────────────────────────
class AppConfig {
  AppConfig._();

  // FIX #1: environment is declared explicitly. No magic.
  static const String environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'prod',
  );

  // FIX #1: public production backend — this is the source of truth
  // for `flutter build apk --release` when no --dart-define is given.
  // When you move to a custom domain, change this ONE line.
  static const String _prodDefaultUrl =
      'https://diffuser-backend-1.onrender.com';

  // FIX #1: localhost is the only safe dev default. A LAN IP like
  // 192.168.1.106 is NOT portable between networks, so we no longer
  // bake one in. Override per-run with --dart-define=API_BASE_URL=...
  static const String _devDefaultUrl = 'http://localhost:3000';

  // FIX #1: if the caller passes --dart-define=API_BASE_URL=... it wins.
  // Otherwise we pick a default based on APP_ENV.
  static const String _overrideUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static bool get isProduction => environment.toLowerCase() == 'prod';
  static bool get isDevelopment => !isProduction;

  /// Resolved API base URL for this build. Never a LAN IP by default.
  static String get apiBaseUrl {
    if (_overrideUrl.isNotEmpty) return _overrideUrl;
    return isProduction ? _prodDefaultUrl : _devDefaultUrl;
  }
}