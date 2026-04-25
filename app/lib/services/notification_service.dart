// lib/services/notification_service.dart — v5.0 production
// CRITICAL FIX: Removed checkDevice() which was the root cause of the
// notification loop. All notifications now come from the backend via
// syncDeviceNotifications(). The app only reads/displays them.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/api_constants.dart';
import '../core/network/api_client.dart';
import '../models/notification_model.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _api = ApiClient();
  final List<NotificationItem> _notifications = [];
  final List<void Function()> _listeners = [];

  // deviceId → earliest time when offline notifications may be shown again.
  // Populated when the user sends a power-on command so stale offline
  // alerts don't reappear while the device boots.
  final Map<String, DateTime> _offlineSuppressedUntil = {};

  Timer? _refreshTimer;
  bool _isRefreshing = false;

  List<NotificationItem> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
  }

  /// Start periodic background refresh (every 30 seconds).
  /// Call after successful login.
  void startPeriodicRefresh() {
    stopPeriodicRefresh();
    refreshFromBackend();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      refreshFromBackend();
    });
  }

  /// Stop periodic refresh. Call on logout.
  void stopPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// Suppress offline notifications for a device (e.g. after power-on command).
  void suppressOfflineFor(String deviceId, {Duration grace = const Duration(minutes: 2)}) {
    _offlineSuppressedUntil[deviceId] = DateTime.now().add(grace);
    _notifications.removeWhere(
      (n) => n.deviceId == deviceId && n.type == NotificationType.deviceOffline,
    );
    _notifyListeners();
  }

  bool _isOfflineSuppressed(String deviceId) {
    final until = _offlineSuppressedUntil[deviceId];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _offlineSuppressedUntil.remove(deviceId);
      return false;
    }
    return true;
  }

  /// Fetch notifications from the backend. This is the ONLY source of truth.
  /// The backend's syncDeviceNotifications() handles creation/clearing of
  /// device alerts, so we never create notifications client-side.
  Future<void> refreshFromBackend() async {
    if (_isRefreshing) return;
    if (!_api.hasToken) return;

    _isRefreshing = true;
    try {
      final response = await _api.get(ApiConstants.notifications);
      final data = response.data;
      if (data is! List) return;

      final fetched = data
          .map((item) => NotificationItem.fromJson(Map<String, dynamic>.from(item)))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // Filter out offline notifications for devices that were recently
      // commanded on — backend may lag behind the device rebooting.
      final filtered = fetched.where((n) {
        if (n.type == NotificationType.deviceOffline && _isOfflineSuppressed(n.deviceId)) {
          return false;
        }
        return true;
      }).toList();

      _notifications
        ..clear()
        ..addAll(filtered);
      _notifyListeners();
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[NotificationService] refresh failed: ${e.message}');
      }
    } finally {
      _isRefreshing = false;
    }
  }

  /// Called when device status changes via realtime socket.
  /// If device comes back online, remove stale offline alerts immediately
  /// without waiting for the next backend refresh.
  void onDeviceStatusChanged(String deviceId, String newStatus) {
    if (newStatus == 'online') {
      final before = _notifications.length;
      _notifications.removeWhere(
        (n) => n.deviceId == deviceId && n.type == NotificationType.deviceOffline,
      );
      if (_notifications.length != before) _notifyListeners();
    }
  }

  void clearState() {
    _notifications.clear();
    _offlineSuppressedUntil.clear();
    stopPeriodicRefresh();
    _notifyListeners();
  }

  Future<void> markAsRead(String notificationId) async {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index < 0) return;
    _notifications[index].isRead = true;
    _notifyListeners();
    try {
      await _api.put('${ApiConstants.notifications}/$notificationId/read');
    } on DioException {
      // Keep local UI state even if backend sync fails.
    }
  }

  Future<void> markAllAsRead() async {
    for (final notification in _notifications) {
      notification.isRead = true;
    }
    _notifyListeners();
    try {
      await _api.put('${ApiConstants.notifications}/read-all');
    } on DioException {
      // Keep local state.
    }
  }

  Future<void> clearAll() async {
    _notifications.clear();
    _notifyListeners();
    try {
      await _api.delete(ApiConstants.notifications);
    } on DioException {
      // Ignore.
    }
  }

  Future<void> clearNotification(String id) async {
    _notifications.removeWhere((n) => n.id == id);
    _notifyListeners();
    try {
      await _api.delete('${ApiConstants.notifications}/$id');
    } on DioException {
      // Ignore.
    }
  }
}
