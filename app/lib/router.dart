// lib/router.dart — v5.2.1 (Apr 2026)
// ─────────────────────────────────────────────────────────────
// Removed routes (code + files deleted in the same pass):
//   /dashboard       — never navigated to; superseded by /home
//   /wifi-setup      — legacy manual-SSID flow; superseded by /onboard
//   /ota-update      — stub screen that literally said OTA wasn't implemented
//   /scan            — redundant BLE scan reached only by the header
//                      magnifying glass; /onboard does real onboarding
//   /group-control   — local-only SharedPreferences; never synced to backend
//   /add-device/...  — v5.2.1: manual add-device path removed to stop
//                      ghost device records. All device creation goes
//                      through the BLE onboarding wizard.
//
// Schedule route now requires :deviceId so the screen always edits the
// intended device, not whatever device happens to be "selected" in
// shared state.
// ─────────────────────────────────────────────────────────────
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/auth_provider.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/customer_devices/customer_devices_screen.dart';
import 'screens/customers/customers_screen.dart';
import 'screens/device_detail/device_detail_screen.dart';
import 'screens/schedule/schedule_screen.dart';
import 'screens/service_log/service_log_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/stats/stats_screen.dart';
import 'screens/user_management/user_management_screen.dart';
import 'screens/alert_devices/alert_devices_screen.dart';
import 'screens/onboarding/onboarding_wizard_screen.dart';

bool _canAccessRoute(AuthState authState, String path) {
  final user = authState.user;
  if (user == null) return false;

  if (path == '/user-management') {
    // Admin OR manager can now manage users (manager cannot elevate
    // roles or edit admin accounts — enforced server-side).
    return user.isAdmin || user.isManager;
  }
  if (path == '/customers' ||
      path == '/stats' ||
      path.startsWith('/onboard')) {
    return user.isAdmin || user.isManager;
  }
  return true;
}

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final isAuth = authState.isAuthenticated;
      final isLoading = authState.isLoading;
      final path = state.uri.path;
      final isLoginPage = path == '/login';
      final isSplashPage = path == '/splash';
      if (isLoading || isSplashPage) return null;
      if (!isAuth && !isLoginPage) return '/login';
      if (isAuth && isLoginPage) return '/home';
      // Legacy / removed deep links from previous builds → /home.
      if (isAuth && (path == '/wifi-setup' ||
                     path == '/scan' ||
                     path == '/dashboard' ||
                     path == '/ota-update' ||
                     path == '/group-control' ||
                     path == '/schedule' ||
                     path.startsWith('/add-device'))) {
        return '/home';
      }
      if (isAuth && !_canAccessRoute(authState, path)) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/home', builder: (c, s) => const HomeScreen()),
      GoRoute(
        path: '/customer/:id',
        builder: (c, s) =>
            CustomerDevicesScreen(customerId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/customers', builder: (c, s) => const CustomersScreen()),
      GoRoute(
        path: '/device/:id',
        builder: (c, s) =>
            DeviceDetailScreen(deviceId: s.pathParameters['id']!),
      ),
      // Schedule now requires a device ID in the URL — no more implicit
      // "selected device" binding.
      GoRoute(
        path: '/schedule/:deviceId',
        builder: (c, s) => ScheduleScreen(deviceId: s.pathParameters['deviceId']!),
      ),
      GoRoute(
        path: '/service-log',
        builder: (c, s) => const ServiceLogScreen(),
      ),
      GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
      GoRoute(
        path: '/notifications',
        builder: (c, s) => const NotificationsScreen(),
      ),
      GoRoute(path: '/stats', builder: (c, s) => const StatsScreen()),
      GoRoute(
        path: '/user-management',
        builder: (c, s) => const UserManagementScreen(),
      ),
      GoRoute(
        path: '/alert-devices',
        builder: (c, s) => const AlertDevicesScreen(),
      ),
      // End-to-end onboarding wizard — the ONLY device creation path.
      GoRoute(
        path: '/onboard',
        builder: (c, s) => const OnboardingWizardScreen(),
      ),
      GoRoute(
        path: '/onboard/:customerId',
        builder: (c, s) => OnboardingWizardScreen(
          initialCustomerId: s.pathParameters['customerId'],
          slotNumber: int.tryParse(s.uri.queryParameters['slot'] ?? ''),
        ),
      ),
    ],
  );
});
