import '../config/app_config.dart';

// ========================================
// api_constants.dart — v5.2.5
//
// Timeouts are deliberately generous:
//   - connectTimeout  30s  — Render free-tier cold start can take 20-30s
//                            before the TCP SYN gets answered.
//   - receiveTimeout  45s  — once connected, first response from a cold
//                            backend can still take 10-15s (DB warm-up).
// Before this fix timeouts were 8s each, causing login to fail with a
// "cannot connect to server" error on the very first call after the
// backend had been idle.
// ========================================
class ApiConstants {
  // FIX: AppConfig.apiBaseUrl is resolved at runtime, so this cannot be const.
  static String get baseUrl => AppConfig.apiBaseUrl;

  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 45);

  // Auth
  static const String login = '/api/auth/login';
  static const String register = '/api/auth/register';
  static const String logout = '/api/auth/logout';
  static const String me = '/api/auth/me';

  // Users
  static const String users = '/api/users';
  static const String usersOnline = '/api/users/online';

  // Devices
  static const String devices = '/api/devices';

  // Customers
  static const String customers = '/api/customers';

  // Service Logs
  static const String serviceLogs = '/api/service-logs';
  static const String serviceLogsExport = '/api/service-logs/export';

  // Notifications
  static const String notifications = '/api/notifications';

  // Search
  static const String search = '/api/search';

  // Stats
  static const String stats = '/api/stats';
}