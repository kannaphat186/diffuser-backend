import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../core/constants/api_constants.dart';

typedef DeviceUpdateCallback = void Function(Map<String, dynamic> data);
typedef DeviceRemovedCallback = void Function(String deviceId);

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  io.Socket? _socket;
  bool _isConnected = false;

  final List<DeviceUpdateCallback> _deviceUpdateListeners = [];
  final List<DeviceRemovedCallback> _deviceRemovedListeners = [];

  bool get isConnected => _isConnected;

  // v5.2.1 (Apr 2026): the socket handshake now requires a JWT. The
  // backend derives userId and role from the verified token, so the
  // payload passed to `join` is no longer trusted — we still emit it for
  // backwards compatibility with older server versions but it is
  // informational only.
  void connect({required String token, String? userId, String? role}) {
    if (_socket != null) {
      if (_isConnected) return;
      _socket!.connect();
      return;
    }

    _socket = io.io(
      ApiConstants.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .disableAutoConnect()
          .enableForceNew()
          .enableReconnection()
          .setReconnectionAttempts(20)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!.onConnect((_) {
      _isConnected = true;
      if (kDebugMode) print('🔌 Socket.IO connected');
      _socket!.emit('join', {'userId': userId, 'role': role});
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      if (kDebugMode) print('🔌 Socket.IO disconnected');
    });

    _socket!.onConnectError((err) {
      if (kDebugMode) print('🔌 Socket.IO error: $err');
    });

    _socket!.on('device:updated', (data) {
      try {
        final parsed = data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from((data as Map?) ?? {});
        if (parsed.isEmpty) return;
        for (final cb in List<DeviceUpdateCallback>.from(_deviceUpdateListeners)) {
          cb(parsed);
        }
      } catch (e) {
        if (kDebugMode) print('Socket parse error: $e');
      }
    });

    _socket!.on('device:removed', (data) {
      final parsed = data is Map<String, dynamic>
          ? data
          : Map<String, dynamic>.from((data as Map?) ?? {});
      final id = parsed['id']?.toString();
      if (id == null || id.isEmpty) return;
      for (final cb in List<DeviceRemovedCallback>.from(_deviceRemovedListeners)) {
        cb(id);
      }
    });

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
  }

  void toggleDevice(String deviceId, bool isOn) {
    _socket?.emit('device:toggle', {'deviceId': deviceId, 'isOn': isOn});
  }

  void addDeviceUpdateListener(DeviceUpdateCallback cb) {
    if (!_deviceUpdateListeners.contains(cb)) _deviceUpdateListeners.add(cb);
  }

  void removeDeviceUpdateListener(DeviceUpdateCallback cb) {
    _deviceUpdateListeners.remove(cb);
  }

  void addDeviceRemovedListener(DeviceRemovedCallback cb) {
    if (!_deviceRemovedListeners.contains(cb)) _deviceRemovedListeners.add(cb);
  }

  void removeDeviceRemovedListener(DeviceRemovedCallback cb) {
    _deviceRemovedListeners.remove(cb);
  }
}
