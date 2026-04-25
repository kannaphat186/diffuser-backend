import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

enum NotificationType {
  lowLevel,
  criticalLevel,
  deviceOffline,
  pumpFailure,
  relayFailure,
  info,
}

class NotificationItem {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  bool isRead;
  final String deviceId;
  final String deviceName;

  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    required this.deviceId,
    required this.deviceName,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      type: _parseType(json['type']?.toString()),
      timestamp: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      isRead: json['isRead'] == true,
      deviceId: json['deviceId']?.toString() ?? '',
      deviceName: json['deviceName']?.toString() ?? '',
    );
  }

  static NotificationType _parseType(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'lowlevel':
      case 'low_level':
        return NotificationType.lowLevel;
      case 'criticallevel':
      case 'critical_level':
        return NotificationType.criticalLevel;
      case 'deviceoffline':
      case 'device_offline':
      case 'offline':
        return NotificationType.deviceOffline;
      case 'pumpfailure':
      case 'pump_failure':
        return NotificationType.pumpFailure;
      case 'relayfailure':
      case 'relay_failure':
        return NotificationType.relayFailure;
      default:
        return NotificationType.info;
    }
  }

  String get backendType {
    switch (type) {
      case NotificationType.lowLevel:
        return 'low_level';
      case NotificationType.criticalLevel:
        return 'critical_level';
      case NotificationType.deviceOffline:
        return 'device_offline';
      case NotificationType.pumpFailure:
        return 'pump_failure';
      case NotificationType.relayFailure:
        return 'relay_failure';
      case NotificationType.info:
        return 'info';
    }
  }

  IconData get typeIcon {
    switch (type) {
      case NotificationType.lowLevel:
        return Icons.warning_amber_rounded;
      case NotificationType.criticalLevel:
        return Icons.error_rounded;
      case NotificationType.deviceOffline:
        return Icons.cloud_off_rounded;
      case NotificationType.pumpFailure:
        return Icons.water_damage_rounded;
      case NotificationType.relayFailure:
        return Icons.electric_bolt_rounded;
      case NotificationType.info:
        return Icons.notifications_active_outlined;
    }
  }

  Color get typeColor {
    switch (type) {
      case NotificationType.lowLevel:
        return AppColors.warning;
      case NotificationType.criticalLevel:
        return AppColors.error;
      case NotificationType.deviceOffline:
        return Colors.grey;
      case NotificationType.pumpFailure:
      case NotificationType.relayFailure:
        return AppColors.error;
      case NotificationType.info:
        return AppColors.primary;
    }
  }

  String get typeName {
    switch (type) {
      case NotificationType.lowLevel:
        return 'Low Level';
      case NotificationType.criticalLevel:
        return 'Critical';
      case NotificationType.deviceOffline:
        return 'Offline';
      case NotificationType.pumpFailure:
        return 'Pump Fault';
      case NotificationType.relayFailure:
        return 'Relay Fault';
      case NotificationType.info:
        return 'Info';
    }
  }
}
