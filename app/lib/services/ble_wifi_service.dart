// lib/services/ble_wifi_service.dart
// ─────────────────────────────────────────────────────────────
// BLE Wi-Fi provisioning service for ScentSense diffusers.
//
// v5.2 — 2026-04
//   FIX (major): scanWifi() used to listen on _statusController looking for
//     "WIFI_END" / "WIFI_SCAN_FAIL", but _subscribeStatus translated those
//     raw frames into user-facing strings ("Wi-Fi scan complete (N)") before
//     emitting — so the completion signal never matched and the scan always
//     fell through to the 12 s fallback timer. We now use a dedicated
//     _wifiScanEventCtrl Stream<_WifiScanEvent> that is fired directly from
//     the raw-notify parser. The UI completes as soon as the device says it
//     is done.
//   FIX: waitForProvisionOutcome() — block up to [timeout] until the device
//     confirms it joined the new Wi-Fi (via "OK" frame or a composite status
//     with a non-zero IPv4). Replaces the fake 2-second delay in onboarding.
//   FIX: writes are attempted writeWithResponse first (required by NimBLE
//     when the characteristic has WRITE property) with fallback to
//     writeWithoutResponse. Previous order failed silently on Android 13+.
//   Preserved: UUIDs, status payload format ("SSID|IP|ID|ON/OFF|LVL%|FW").
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

class BleDevice {
  final String id;
  final String name;
  final int rssi;
  String? deviceId;   // MongoDB _id (parsed from status)
  String? wifiSsid;
  String? wifiIp;
  String? status;     // ON/OFF
  String? level;
  String? firmware;

  BleDevice({required this.id, required this.name, required this.rssi});

  bool get isScentSense => name.startsWith('ScentSense');
  bool get hasWifiIp =>
      wifiIp != null && wifiIp!.isNotEmpty && wifiIp != '0.0.0.0';
}

/// Access Point reported by the ESP32 Wi-Fi scan.
/// Wire format: `<ssid>:<rssi>:<S|O>`  (rssi + secured may be absent in
/// legacy firmware, parser is tolerant).
class BleWifiAp {
  final String ssid;
  final int? rssi;
  final bool secured;

  const BleWifiAp({required this.ssid, this.rssi, this.secured = true});

  factory BleWifiAp.parse(String raw) {
    final parts = raw.split(':');
    if (parts.length == 1) return BleWifiAp(ssid: parts[0].trim());
    final ssid = parts[0].trim();
    final rssi = int.tryParse(parts[1].trim());
    final secured = parts.length >= 3 ? parts[2].trim().toUpperCase() != 'O' : true;
    return BleWifiAp(ssid: ssid, rssi: rssi, secured: secured);
  }
}

/// Outcome of a Wi-Fi scan cycle, signalled by _subscribeStatus.
enum _WifiScanOutcome { done, failed }

class _WifiScanEvent {
  final _WifiScanOutcome outcome;
  const _WifiScanEvent(this.outcome);
}

/// Post-provisioning firmware signal (parsed from the status characteristic).
enum ProvisionOutcome { pending, ok, failed }

class BleWifiService {
  static final BleWifiService _instance = BleWifiService._internal();
  factory BleWifiService() => _instance;
  BleWifiService._internal();

  final _ble = FlutterReactiveBle();

  // UUIDs — must match firmware (BLE_SERVICE_UUID / BLE_WIFI_CHAR / BLE_STATUS_CHAR)
  static final _serviceUuid   = Uuid.parse('4fafc201-1fb5-459e-8fcc-c5c9c331914b');
  static final _wifiCharUuid  = Uuid.parse('beb5483e-36e1-4688-b7f5-ea07361b26a8');
  static final _statusCharUuid = Uuid.parse('beb5483e-36e1-4688-b7f5-ea07361b26a9');

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _statusSub;
  Timer? _scanTimer;

  // Public streams
  final _devicesController = StreamController<List<BleDevice>>.broadcast();
  Stream<List<BleDevice>> get devicesStream => _devicesController.stream;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  final _wifiListController = StreamController<List<BleWifiAp>>.broadcast();
  Stream<List<BleWifiAp>> get wifiListStream => _wifiListController.stream;

  // Internal-only stream used by scanWifi() to await completion reliably.
  final _wifiScanEventCtrl = StreamController<_WifiScanEvent>.broadcast();

  // Firmware provisioning outcome stream ("OK" / "WIFI_FAIL" frames).
  final _provisionCtrl = StreamController<ProvisionOutcome>.broadcast();
  Stream<ProvisionOutcome> get provisionStream => _provisionCtrl.stream;

  final List<BleWifiAp> _wifiList = [];
  List<BleWifiAp> get wifiList => List.unmodifiable(_wifiList);

  final List<BleDevice> _foundDevices = [];
  String? _connectedDeviceId;
  bool _isScanning = false;

  bool get isScanning => _isScanning;
  bool get isConnected => _connectedDeviceId != null;
  List<BleDevice> get foundDevices => List.unmodifiable(_foundDevices);

  BleDevice? get connectedDevice {
    if (_connectedDeviceId == null) return null;
    for (final d in _foundDevices) {
      if (d.id == _connectedDeviceId) return d;
    }
    return null;
  }

  Future<bool> requestPermissions() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    final allGranted =
        results.values.every((s) => s.isGranted || s.isLimited);
    if (kDebugMode) {
      debugPrint('[BLE] Permissions: '
          '${results.entries.map((e) => '${e.key}: ${e.value}').join(', ')}');
    }
    return allGranted;
  }

  // ─────────────────────────────────────────────────────────────
  // BLE device scan
  // ─────────────────────────────────────────────────────────────
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isScanning) return;

    final ok = await requestPermissions();
    if (!ok) {
      _statusController.add('Please allow Bluetooth and Location');
      return;
    }

    _scanTimer?.cancel();
    _scanSub?.cancel();

    _isScanning = true;
    _foundDevices.clear();
    _devicesController.add(List.unmodifiable(_foundDevices));
    _statusController.add('Scanning...');

    if (kDebugMode) debugPrint('[BLE] Starting scan filter: $_serviceUuid');

    _scanSub = _ble
        .scanForDevices(
          withServices: [_serviceUuid],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
      (d) {
        if (kDebugMode) {
          debugPrint('[BLE] Found: ${d.name} (${d.id}) rssi=${d.rssi}');
        }
        final idx = _foundDevices.indexWhere((x) => x.id == d.id);
        final device = BleDevice(
          id: d.id,
          name: d.name.isNotEmpty ? d.name : 'ScentSense',
          rssi: d.rssi,
        );
        if (idx >= 0) {
          _foundDevices[idx] = device;
        } else {
          _foundDevices.add(device);
        }
        _devicesController.add(List.unmodifiable(_foundDevices));
      },
      onError: (e) {
        if (kDebugMode) debugPrint('[BLE] Scan error: $e');
        _statusController.add('BLE scan failed');
        stopScan();
      },
    );

    _scanTimer = Timer(timeout, stopScan);
  }

  void stopScan() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanSub?.cancel();
    _scanSub = null;
    final wasScanning = _isScanning;
    _isScanning = false;
    if (wasScanning) {
      final msg = _foundDevices.isEmpty
          ? 'No diffuser found. Make sure the device is powered on.'
          : 'Found ${_foundDevices.length} device(s)';
      if (kDebugMode) debugPrint('[BLE] Scan stopped: $msg');
      _statusController.add(msg);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Connect / subscribe
  // ─────────────────────────────────────────────────────────────
  Future<bool> connect(String deviceId) async {
    _statusController.add('Connecting...');
    if (kDebugMode) debugPrint('[BLE] Connecting to: $deviceId');

    await _connSub?.cancel();
    await _statusSub?.cancel();

    final completer = Completer<bool>();

    _connSub = _ble
        .connectToDevice(
          id: deviceId,
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
      (state) async {
        if (kDebugMode) debugPrint('[BLE] State: ${state.connectionState}');
        if (state.connectionState == DeviceConnectionState.connected) {
          _connectedDeviceId = deviceId;
          _statusController.add('Connected');
          _subscribeStatus(deviceId);

          // Let NimBLE stack settle before the first write
          await Future<void>.delayed(const Duration(milliseconds: 800));
          try {
            await _writeWifiChar(deviceId, 'SCAN');  // ask for status now
          } catch (e) {
            if (kDebugMode) debugPrint('[BLE] SCAN write error: $e');
          }
          if (!completer.isCompleted) completer.complete(true);
        } else if (state.connectionState == DeviceConnectionState.disconnected) {
          _connectedDeviceId = null;
          _statusController.add('Disconnected');
          if (!completer.isCompleted) completer.complete(false);
        }
      },
      onError: (e) {
        if (kDebugMode) debugPrint('[BLE] Connection error: $e');
        _statusController.add('BLE connection failed');
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        if (kDebugMode) debugPrint('[BLE] Connection timed out');
        _statusController.add('BLE connection timed out');
        disconnect();
        return false;
      },
    );
  }

  void _subscribeStatus(String deviceId) {
    final char = QualifiedCharacteristic(
      serviceId: _serviceUuid,
      characteristicId: _statusCharUuid,
      deviceId: deviceId,
    );
    _statusSub?.cancel();
    _statusSub = _ble.subscribeToCharacteristic(char).listen(
      (data) => _handleStatusFrame(utf8.decode(data), deviceId),
      onError: (e) {
        if (kDebugMode) debugPrint('[BLE] Status sub error: $e');
      },
    );
  }

  /// Parse a single notify frame from the status characteristic.
  void _handleStatusFrame(String status, String deviceId) {
    if (kDebugMode) debugPrint('[BLE] Notify: $status');

    if (status.startsWith('WIFI_START')) {
      _wifiList.clear();
      _wifiListController.add(List.unmodifiable(_wifiList));
      return;
    }
    if (status.startsWith('WIFI_END')) {
      _wifiListController.add(List.unmodifiable(_wifiList));
      _statusController.add('Wi-Fi scan complete (${_wifiList.length})');
      _wifiScanEventCtrl.add(const _WifiScanEvent(_WifiScanOutcome.done));
      return;
    }
    if (status.startsWith('WIFI_SCAN_FAIL')) {
      _wifiList.clear();
      _wifiListController.add(List.unmodifiable(_wifiList));
      _statusController.add('Wi-Fi scan failed on device');
      _wifiScanEventCtrl.add(const _WifiScanEvent(_WifiScanOutcome.failed));
      return;
    }
    if (status.startsWith('WIFI:')) {
      final ap = BleWifiAp.parse(status.substring(5));
      if (ap.ssid.isNotEmpty && !_wifiList.any((x) => x.ssid == ap.ssid)) {
        _wifiList.add(ap);
        _wifiListController.add(List.unmodifiable(_wifiList));
      }
      return;
    }

    // Provisioning lifecycle frames
    if (status == 'CONNECTING') {
      _statusController.add('Device is joining new Wi-Fi...');
      _provisionCtrl.add(ProvisionOutcome.pending);
      return;
    }
    if (status == 'OK') {
      _statusController.add('Device connected to new Wi-Fi');
      _provisionCtrl.add(ProvisionOutcome.ok);
      return;
    }
    if (status == 'WIFI_FAIL') {
      _statusController.add('Device failed to join Wi-Fi');
      _provisionCtrl.add(ProvisionOutcome.failed);
      return;
    }

    // Composite status: "SSID|IP|DEVICE_ID|ON/OFF|LEVEL%|FW"
    final parts = status.split('|');
    if (parts.length >= 6) {
      final idx = _foundDevices.indexWhere((d) => d.id == deviceId);
      if (idx >= 0) {
        _foundDevices[idx].wifiSsid  = parts[0];
        _foundDevices[idx].wifiIp    = parts[1];
        _foundDevices[idx].deviceId  = parts[2];
        _foundDevices[idx].status    = parts[3];
        _foundDevices[idx].level     = parts[4];
        _foundDevices[idx].firmware  = parts[5];
        _devicesController.add(List.unmodifiable(_foundDevices));
      }
      // A composite frame with a non-zero IP is itself evidence that the
      // device is on Wi-Fi again (e.g. the firmware re-emits status after
      // a successful provisioning without emitting a new "OK" frame).
      if (parts[1].isNotEmpty && parts[1] != '0.0.0.0') {
        _provisionCtrl.add(ProvisionOutcome.ok);
      }
    }
    _statusController.add(status);
  }

  // ─────────────────────────────────────────────────────────────
  // Wi-Fi scan (firmware-assisted)
  // ─────────────────────────────────────────────────────────────
  Future<List<BleWifiAp>> scanWifi({
    Duration timeout = const Duration(seconds: 14),
  }) async {
    if (_connectedDeviceId == null) {
      if (kDebugMode) debugPrint('[BLE] scanWifi: not connected');
      return const [];
    }

    _wifiList.clear();
    _wifiListController.add(const []);
    _statusController.add('Scanning Wi-Fi on device...');

    final completer = Completer<List<BleWifiAp>>();
    late final StreamSubscription<_WifiScanEvent> sub;
    Timer? fallback;

    sub = _wifiScanEventCtrl.stream.listen((e) {
      if (!completer.isCompleted) {
        completer.complete(List.unmodifiable(_wifiList));
      }
    });

    try {
      await _writeWifiChar(_connectedDeviceId!, 'SCAN_WIFI');
    } catch (e) {
      if (kDebugMode) debugPrint('[BLE] scanWifi write error: $e');
      await sub.cancel();
      return const [];
    }

    // Fallback: if the firmware is an older build that never emits WIFI_END
    // we still return whatever APs were collected before the timeout.
    fallback = Timer(timeout, () {
      if (!completer.isCompleted) {
        if (kDebugMode) {
          debugPrint('[BLE] scanWifi timeout — returning ${_wifiList.length} APs');
        }
        completer.complete(List.unmodifiable(_wifiList));
      }
    });

    try {
      return await completer.future;
    } finally {
      fallback.cancel();
      await sub.cancel();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Provisioning helpers
  // ─────────────────────────────────────────────────────────────
  Future<bool> sendWifiConfig(String ssid, String password) async {
    if (_connectedDeviceId == null) {
      if (kDebugMode) debugPrint('[BLE] sendWifiConfig: not connected');
      return false;
    }
    _statusController.add('Sending Wi-Fi credentials...');
    try {
      final payload = '$ssid|$password';
      if (kDebugMode) {
        debugPrint('[BLE] Sending Wi-Fi: '
            '${ssid.length} + ${password.length} chars');
      }
      await _writeWifiChar(_connectedDeviceId!, payload);
      _statusController.add('Credentials sent. Waiting for device...');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[BLE] sendWifiConfig error: $e');
      _statusController.add('Failed to send Wi-Fi credentials');
      return false;
    }
  }

  /// Wait until the firmware reports it has joined Wi-Fi. Resolves:
  ///   - true  if we see an "OK" frame or a composite status with a non-zero IP
  ///   - false if we see "WIFI_FAIL" or the timeout elapses
  Future<bool> waitForProvisionOutcome({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final d = connectedDevice;
    if (d != null && d.hasWifiIp) return true;

    final completer = Completer<bool>();
    late final StreamSubscription<ProvisionOutcome> sub;
    sub = _provisionCtrl.stream.listen((outcome) {
      if (outcome == ProvisionOutcome.ok) {
        if (!completer.isCompleted) completer.complete(true);
      } else if (outcome == ProvisionOutcome.failed) {
        if (!completer.isCompleted) completer.complete(false);
      }
    });
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  Future<bool> sendToggle() async {
    if (_connectedDeviceId == null) return false;
    try {
      await _writeWifiChar(_connectedDeviceId!, 'TOGGLE');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[BLE] TOGGLE error: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Low-level write: tolerant of both NimBLE write styles.
  // ─────────────────────────────────────────────────────────────
  Future<void> _writeWifiChar(String deviceId, String value) async {
    final char = QualifiedCharacteristic(
      serviceId: _serviceUuid,
      characteristicId: _wifiCharUuid,
      deviceId: deviceId,
    );
    final encoded = utf8.encode(value);
    if (kDebugMode) debugPrint('[BLE] Writing ${encoded.length} bytes');

    try {
      await _ble.writeCharacteristicWithResponse(char, value: encoded);
      if (kDebugMode) debugPrint('[BLE] Write (with-response) OK');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BLE] Write (with-response) failed: $e — retrying WRITE_NR');
      }
      await _ble.writeCharacteristicWithoutResponse(char, value: encoded);
      if (kDebugMode) debugPrint('[BLE] Write (no-response) OK');
    }
  }

  void disconnect() {
    if (kDebugMode) debugPrint('[BLE] Disconnecting');
    _statusSub?.cancel();
    _connSub?.cancel();
    _connectedDeviceId = null;
    _statusController.add('Disconnected');
  }

  void dispose() {
    _scanTimer?.cancel();
    _scanSub?.cancel();
    _connSub?.cancel();
    _statusSub?.cancel();
    _devicesController.close();
    _statusController.close();
    _wifiListController.close();
    _wifiScanEventCtrl.close();
    _provisionCtrl.close();
  }
}
