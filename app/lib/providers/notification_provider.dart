// lib/providers/notification_provider.dart — v5.0 production
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';

class NotificationState {
  final List<NotificationItem> notifications;
  final int unreadCount;

  NotificationState({
    this.notifications = const [],
    this.unreadCount = 0,
  });

  NotificationState copyWith({
    List<NotificationItem>? notifications,
    int? unreadCount,
  }) {
    return NotificationState(
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

class NotificationNotifier extends StateNotifier<NotificationState> {
  final NotificationService _notificationService;

  NotificationNotifier(this._notificationService) : super(NotificationState()) {
    _notificationService.addListener(_onNotificationChanged);
  }

  void _syncState() {
    state = state.copyWith(
      notifications: _notificationService.notifications,
      unreadCount: _notificationService.unreadCount,
    );
  }

  void _onNotificationChanged() {
    _syncState();
  }

  Future<void> refresh() async {
    await _notificationService.refreshFromBackend();
    _syncState();
  }

  Future<void> markAsRead(String notificationId) async {
    await _notificationService.markAsRead(notificationId);
    _syncState();
  }

  Future<void> markAllAsRead() async {
    await _notificationService.markAllAsRead();
    _syncState();
  }

  Future<void> clearAll() async {
    await _notificationService.clearAll();
    _syncState();
  }

  Future<void> clearNotification(String id) async {
    await _notificationService.clearNotification(id);
    _syncState();
  }

  void clearState() {
    _notificationService.clearState();
    _syncState();
  }

  @override
  void dispose() {
    _notificationService.removeListener(_onNotificationChanged);
    super.dispose();
  }
}

final notificationServiceProvider = Provider((ref) => NotificationService());

final notificationProvider = StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
  return NotificationNotifier(ref.watch(notificationServiceProvider));
});
