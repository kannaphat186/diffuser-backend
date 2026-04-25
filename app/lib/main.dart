// lib/main.dart — v6.0.0 (Apr 2026)
// ─────────────────────────────────────────────────────────────
// Changes vs v5.2.x:
//   • Firebase / FCM restored end-to-end. Init at app start;
//     token register on login; token unregister on logout.
//   • Everything else preserved: Socket.IO reconnection, provider
//     refresh, system chrome, and Riverpod ProviderScope.
// ─────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'providers/auth_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/device_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/notification_provider.dart';
import 'constants/app_theme.dart';
import 'core/network/api_client.dart';
import 'services/notification_service.dart';
import 'services/socket_service.dart';
import 'services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  // Fire-and-forget FCM bootstrap. It awaits its own Firebase init
  // internally; we don't block the UI on it because a missing Play
  // Services / network should still let the app open.
  unawaited(FcmService().init());

  runApp(const ProviderScope(child: ScentSenseApp()));
}

class ScentSenseApp extends ConsumerStatefulWidget {
  const ScentSenseApp({super.key});

  @override
  ConsumerState<ScentSenseApp> createState() => _ScentSenseAppState();
}

class _ScentSenseAppState extends ConsumerState<ScentSenseApp> {
  final _socketService = SocketService();
  final _notificationService = NotificationService();
  final _fcmService = FcmService();
  ProviderSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();

    _socketService.addDeviceUpdateListener((data) {
      ref.read(deviceProvider.notifier).applyRealtimePatch(data);
    });
    _socketService.addDeviceRemovedListener((deviceId) {
      ref.read(deviceProvider.notifier).removeDeviceFromCache(deviceId);
    });

    _authSub = ref.listenManual<AuthState>(authProvider, (previous, next) {
      final prevAuth = previous?.isAuthenticated ?? false;
      final nextAuth = next.isAuthenticated;

      if (!prevAuth && nextAuth && next.user != null) {
        final token = ApiClient().token;
        if (token != null && token.isNotEmpty) {
          _socketService.connect(
            token: token,
            userId: next.user!.id,
            role: next.user!.role,
          );
        }
        _notificationService.startPeriodicRefresh();

        // Ask for push permission + register token after login.
        // Non-blocking; the notification list still works without it.
        _fcmService.registerWithBackend();

        Future.microtask(() async {
          await ref.read(customerProvider.notifier).refresh();
          await ref.read(deviceProvider.notifier).refresh();
          await ref.read(notificationProvider.notifier).refresh();
        });
      } else if (prevAuth && !nextAuth) {
        // Remove this device from the backend push list before we drop
        // the auth token — otherwise the API call has no JWT to present.
        _fcmService.unregisterFromBackend();

        _socketService.disconnect();
        _notificationService.clearState();
        ref.read(customerProvider.notifier).clearState();
        ref.read(deviceProvider.notifier).clearState();
        ref.read(notificationProvider.notifier).clearState();
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _authSub?.close();
    _socketService.disconnect();
    _notificationService.stopPeriodicRefresh();
    _fcmService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'Scent & Sense',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      locale: locale,
      supportedLocales: const [Locale('th'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
