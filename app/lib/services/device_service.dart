import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../core/constants/api_constants.dart';
import '../models/device_model.dart';

class DeviceService {
  final _api = ApiClient();

  Future<List<DeviceModel>> getDevices({
    String? customerId,
    String? search,
    int? page,
    int? limit,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (customerId != null && customerId.isNotEmpty) {
        params['customerId'] = customerId;
      }
      if (search != null && search.trim().isNotEmpty) {
        params['search'] = search.trim();
      }
      if (page != null) params['page'] = page;
      if (limit != null) params['limit'] = limit;
      final response = await _api.get(
        ApiConstants.devices,
        queryParameters: params,
      );
      // Backend returns plain array without pagination, or {data: [...], pagination: {...}} with it
      final List rawList;
      if (response.data is List) {
        rawList = response.data as List;
      } else if (response.data is Map && response.data['data'] is List) {
        rawList = response.data['data'] as List;
      } else {
        rawList = [];
      }
      return rawList
          .map((j) => DeviceModel.fromJson(Map<String, dynamic>.from(j)))
          .toList();
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<DeviceModel> getDevice(String id) async {
    try {
      final response = await _api.get('${ApiConstants.devices}/$id');
      return DeviceModel.fromJson(Map<String, dynamic>.from(response.data));
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  // v5.2.1 (Apr 2026): manual createDevice() removed. Backend now returns
  // 410 Gone on POST /api/devices — devices must be claimed through the
  // BLE onboarding flow (claimDevice below) so there is real hardware
  // identity behind every record.

  Future<Map<String, dynamic>> claimDevice({
    required String serialNumber,
    required String customerId,
    String name = '',
    String location = '',
    String? deviceId,
    String? hardwareId,
    String? wifiSSID,
    String? mac,
    String? firmwareVersion,
  }) async {
    try {
      final response = await _api.post(
        '${ApiConstants.devices}/claim',
        data: {
          'serialNumber': serialNumber,
          'customerId': customerId,
          'name': name,
          'location': location,
          if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
          if (hardwareId != null && hardwareId.isNotEmpty) 'hardwareId': hardwareId,
          if (wifiSSID != null && wifiSSID.isNotEmpty) 'wifiSSID': wifiSSID,
          if (mac != null && mac.isNotEmpty) 'mac': mac,
          if (firmwareVersion != null && firmwareVersion.isNotEmpty) 'firmwareVersion': firmwareVersion,
        },
      );
      return Map<String, dynamic>.from(response.data);
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<void> toggleDevice(String id, bool isOn) async {
    try {
      await _api.put(
        '${ApiConstants.devices}/$id/status',
        data: {'isOn': isOn},
      );
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<DeviceModel> updateDevice(
    String id, {
    String? name,
    String? location,
    String? wifiSSID,
    String? wifiIP,
    int? levelMl,
    int? battery,
    double? batteryVoltage,
    String? scentName,
    String? notes,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (location != null) data['location'] = location;
      if (wifiSSID != null) data['wifiSSID'] = wifiSSID;
      if (wifiIP != null) data['wifiIP'] = wifiIP;
      if (levelMl != null) data['levelMl'] = levelMl;
      if (battery != null) data['battery'] = battery;
      if (batteryVoltage != null) data['batteryVoltage'] = batteryVoltage;
      if (scentName != null) data['scentName'] = scentName;
      if (notes != null) data['notes'] = notes;
      final response = await _api.put(
        '${ApiConstants.devices}/$id',
        data: data,
      );
      return DeviceModel.fromJson(Map<String, dynamic>.from(response.data));
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  // v5.2.1 (Apr 2026): changeWiFi() removed. The backend endpoint it hit
  // only updated metadata without reconfiguring the ESP32, so the UI that
  // relied on it was a fake. Real Wi-Fi reprovisioning happens over BLE
  // through the onboarding wizard.

  Future<DeviceModel> updateSchedule(
    String id,
    List<Map<String, dynamic>> schedule,
  ) async {
    try {
      final response = await _api.put(
        '${ApiConstants.devices}/$id/schedule',
        data: {'schedule': schedule},
      );
      return DeviceModel.fromJson(Map<String, dynamic>.from(response.data));
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<DeviceModel> assignCustomer(
    String id,
    String customerId, {
    String? location,
  }) async {
    try {
      final response = await _api.put(
        '${ApiConstants.devices}/$id/assign-customer',
        data: {
          'customerId': customerId,
          if (location != null) 'location': location,
        },
      );
      return DeviceModel.fromJson(Map<String, dynamic>.from(response.data));
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<void> deleteDevice(String id) async {
    try {
      await _api.delete('${ApiConstants.devices}/$id');
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  String _err(DioException e) {
    final resp = e.response;
    if (resp != null) {
      final data = resp.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
      if (data is String && data.trim().isNotEmpty) {
        return data.length > 140 ? '${data.substring(0, 140)}…' : data;
      }
      switch (resp.statusCode) {
        case 400:
          return 'ข้อมูลไม่ถูกต้อง (400)';
        case 401:
          return 'เซสชันหมดอายุ (401) — กรุณาเข้าสู่ระบบใหม่';
        case 403:
          return 'ไม่มีสิทธิ์ดำเนินการ (403)';
        case 404:
          return 'ไม่พบเครื่องในระบบ (404)';
        case 409:
          return 'เครื่องนี้ถูกผูกกับลูกค้ารายอื่นแล้ว (409)';
        case 500:
        case 502:
        case 503:
          return 'เซิร์ฟเวอร์ผิดพลาด (${resp.statusCode})';
      }
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'หมดเวลาเชื่อมต่อเซิร์ฟเวอร์';
      case DioExceptionType.connectionError:
        return 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้';
      default:
        break;
    }
    return 'เกิดข้อผิดพลาด';
  }
}
