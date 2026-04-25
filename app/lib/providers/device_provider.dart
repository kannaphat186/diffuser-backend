// lib/providers/device_provider.dart — v5.0 production
// CRITICAL FIX: Removed all NotificationService().checkDevice() calls.
// Notifications are now managed entirely by the backend.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/device_model.dart';
import '../services/device_service.dart';
import '../services/notification_service.dart';

class DeviceState {
  final bool isLoading;
  final List<DeviceModel> devices;
  final DeviceModel? selectedDevice;
  final String? error;
  final DateTime? lastFetched;

  const DeviceState({
    this.isLoading = false,
    this.devices = const [],
    this.selectedDevice,
    this.error,
    this.lastFetched,
  });

  DeviceState copyWith({
    bool? isLoading,
    List<DeviceModel>? devices,
    DeviceModel? selectedDevice,
    String? error,
    DateTime? lastFetched,
    bool clearSelectedDevice = false,
  }) {
    return DeviceState(
      isLoading: isLoading ?? this.isLoading,
      devices: devices ?? this.devices,
      selectedDevice: clearSelectedDevice ? null : (selectedDevice ?? this.selectedDevice),
      error: error,
      lastFetched: lastFetched ?? this.lastFetched,
    );
  }

  bool get isCacheValid {
    if (lastFetched == null || devices.isEmpty) return false;
    return DateTime.now().difference(lastFetched!) < const Duration(seconds: 15);
  }
}

class DeviceNotifier extends StateNotifier<DeviceState> {
  final DeviceService _deviceService;

  DeviceNotifier(this._deviceService) : super(const DeviceState()) {
    loadDevices();
  }

  Future<void> loadDevices({bool skipCache = false, String? customerId}) async {
    if (!skipCache && customerId == null && state.isCacheValid) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final devices = await _deviceService.getDevices(customerId: customerId);
      state = state.copyWith(
        isLoading: false,
        devices: devices,
        selectedDevice: _preserveSelection(devices),
        lastFetched: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  DeviceModel? _preserveSelection(List<DeviceModel> devices) {
    if (devices.isEmpty) return null;
    final selectedId = state.selectedDevice?.id;
    if (selectedId == null) return devices.first;
    return devices.firstWhere(
      (d) => d.id == selectedId,
      orElse: () => devices.first,
    );
  }

  Future<void> refresh() => loadDevices(skipCache: true);

  void selectDevice(DeviceModel device) {
    state = state.copyWith(selectedDevice: device);
  }

  void upsertDevice(DeviceModel updated) {
    final existingIndex = state.devices.indexWhere((d) => d.id == updated.id);
    final next = [...state.devices];
    if (existingIndex >= 0) {
      next[existingIndex] = updated;
    } else {
      next.insert(0, updated);
    }
    state = state.copyWith(
      devices: next,
      selectedDevice: state.selectedDevice?.id == updated.id ? updated : state.selectedDevice,
      lastFetched: DateTime.now(),
    );
  }

  void applyRealtimePatch(Map<String, dynamic> patch) {
    final id = patch['id']?.toString();
    if (id == null || id.isEmpty) return;
    final existingIndex = state.devices.indexWhere((d) => d.id == id);
    if (existingIndex < 0) {
      loadDevices(skipCache: true);
      return;
    }

    final oldDevice = state.devices[existingIndex];
    final updated = oldDevice.mergeJson(patch);
    upsertDevice(updated);

    // If device status changed to online, immediately clear stale
    // offline notifications on the client side.
    final newStatus = patch['status']?.toString();
    if (newStatus != null && newStatus != oldDevice.status) {
      NotificationService().onDeviceStatusChanged(id, newStatus);
    }
  }

  void removeDeviceFromCache(String deviceId) {
    final updatedDevices = state.devices.where((d) => d.id != deviceId).toList();
    state = state.copyWith(
      devices: updatedDevices,
      selectedDevice: state.selectedDevice?.id == deviceId ? null : state.selectedDevice,
      lastFetched: DateTime.now(),
    );
  }

  Future<void> toggleDevice(String deviceId, bool isOn) async {
    DeviceModel? existing;
    for (final device in state.devices) {
      if (device.id == deviceId) {
        existing = device;
        break;
      }
    }
    if (existing != null) {
      upsertDevice(existing.copyWith(isOn: isOn));
    }

    // Suppress offline notifications for this device while it boots
    if (isOn) {
      NotificationService().suppressOfflineFor(deviceId);
    }

    try {
      await _deviceService.toggleDevice(deviceId, isOn);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      await loadDevices(skipCache: true);
    }
  }

  Future<void> updateSchedule(String deviceId, List<dynamic> schedule) async {
    try {
      final scheduleList = schedule.map<Map<String, dynamic>>((s) {
        if (s is Map<String, dynamic>) return s;
        if (s is ScheduleItem) return s.toJson();
        return <String, dynamic>{};
      }).toList();
      final updatedDevice = await _deviceService.updateSchedule(deviceId, scheduleList);
      upsertDevice(updatedDevice);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> reloadDevice(String deviceId) async {
    try {
      final updatedDevice = await _deviceService.getDevice(deviceId);
      upsertDevice(updatedDevice);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  void clearState() {
    state = const DeviceState();
  }
}

final deviceServiceProvider = Provider((ref) => DeviceService());

final deviceProvider = StateNotifierProvider<DeviceNotifier, DeviceState>((ref) {
  return DeviceNotifier(ref.watch(deviceServiceProvider));
});
