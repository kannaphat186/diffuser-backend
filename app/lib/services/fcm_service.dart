// lib/services/fcm_service.dart — v6.0.0
// ─────────────────────────────────────────────────────────────
// Firebase Cloud Messaging integration for Scent & Sense.
//
// Lifecycle:
//   • App start → FcmService.init() creates the notification channel
//     and installs the message handlers. Not yet authenticated, so we
//     don't fetch a token.
//   • After successful login → FcmService().registerWithBackend()
//     requests permission, obtains the FCM token, and POSTs it to
//     /api/auth/fcm-token so the backend can target this device.
//   • On logout → FcmService().unregisterFromBackend() deletes the
//     token server-side so stale handsets stop receiving alerts.
//   • Token rotates automatically (onTokenRefresh) — we push the new
//     value to the backend without blocking the UI.
//
// Foreground messages trigger a manual refresh of the notification
// list so the drawer updates instantly; background/terminated messages
// are handled by the OS via the Android notification channel.
// ─────────────────────────────────────────────────────────────
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/network/api_client.dart';
import '../firebase_options.dart';
import 'notification_service.dart';

// Background message handler must be a top-level / static function.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized in the background isolate.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kDebugMode) {
    debugPrint('[FCM] background message: ${message.messageId} '
        'title=${message.notification?.title}');
  }
  // The system tray notification is rendered by the OS from the FCM
  // `notification` payload. No extra work needed here.
}

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final _api = ApiClient();
  final _notifications = NotificationService();

  bool _initialized = false;
  String? _currentToken;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<String>? _tokenSub;

  /// One-time initialization. Safe to call before login — does NOT
  /// request permission or register a token yet.
  Future<void> init() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[FCM] Firebase.initializeApp failed: $e\n$st');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    _foregroundSub = FirebaseMessaging.onMessage.listen((msg) {
      if (kDebugMode) {
        debugPrint('[FCM] foreground: ${msg.notification?.title} '
            '— ${msg.notification?.body}');
      }
      // Device alerts are the only messages we currently send — reflect
      // them in the in-app drawer without waiting for the 30s poll.
      _notifications.refreshFromBackend();
    });

    _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      _currentToken = token;
      await _postTokenIfAuthenticated();
    });

    _initialized = true;
  }

  /// Called after a successful login. Prompts for permission (Android
  /// 13+ / iOS), obtains the token, and posts it to the backend.
  Future<void> registerWithBackend() async {
    if (!_initialized) await init();
    if (!_initialized) return;

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        if (kDebugMode) debugPrint('[FCM] permission denied — skipping token registration');
        return;
      }

      final token = await FirebaseMessaging.instance.getToken();
      _currentToken = token;
      await _postTokenIfAuthenticated();
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] registerWithBackend failed: $e');
    }
  }

  Future<void> _postTokenIfAuthenticated() async {
    final token = _currentToken;
    if (token == null || token.isEmpty) return;
    if (!_api.hasToken) return;   // not authenticated yet
    try {
      await _api.post(
        '/api/auth/fcm-token',
        data: {'token': token, 'platform': 'android'},
      );
      if (kDebugMode) debugPrint('[FCM] registered token with backend');
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] token registration failed: $e');
    }
  }

  /// Called on logout. Deletes the current token server-side so stale
  /// sessions stop receiving pushes. Best-effort — a failure does not
  /// block logout.
  Future<void> unregisterFromBackend() async {
    final token = _currentToken;
    if (token == null || token.isEmpty) return;
    try {
      await _api.delete(
        '/api/auth/fcm-token',
        data: {'token': token},
      );
    } catch (_) {
      // Ignore — logout shouldn't fail on a cleanup call.
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _currentToken = null;
  }

  void dispose() {
    _foregroundSub?.cancel();
    _tokenSub?.cancel();
    _foregroundSub = null;
    _tokenSub = null;
  }
}
