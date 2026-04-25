// lib/services/customer_service.dart
//
// Fix: Add Customer previously showed a generic "เกิดข้อผิดพลาด" message
//      even when the backend returned a specific error (e.g. 400/403/500).
//      The fix:
//        1) _err() now inspects DioException.type, response.statusCode, and
//           response.data (which can be Map, String, or null) and builds a
//           human-readable message.
//        2) createCustomer/updateCustomer now explicitly log which HTTP code
//           the server returned, so the user/staff can see 403 vs 500 vs
//           network failure at a glance.
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/network/api_client.dart';
import '../core/constants/api_constants.dart';
import '../models/customer_model.dart';

class CustomerService {
  final _api = ApiClient();

  Future<List<CustomerModel>> getCustomers() async {
    try {
      final response = await _api.get(ApiConstants.customers);
      final data = response.data;
      final List rawList;
      if (data is List) {
        rawList = data;
      } else if (data is Map && data['data'] is List) {
        rawList = data['data'] as List;
      } else {
        rawList = const [];
      }
      return rawList
          .map((j) => CustomerModel.fromJson(Map<String, dynamic>.from(j)))
          .toList();
    } on DioException catch (e) {
      throw _err(e, 'โหลดรายชื่อลูกค้าไม่สำเร็จ');
    }
  }

  Future<CustomerModel> createCustomer({
    required String name,
    String? contactName,
    String? contactPhone,
    String? contactEmail,
    String? address,
    int? packageQty,
    String? notes,
  }) async {
    try {
      // Build payload matching backend expected shape.
      // Backend normalizes packageQty: null/''/undefined → 1. We default to 1
      // explicitly so UI never sends 0-slot customers by accident.
      final payload = <String, dynamic>{
        'name': name.trim(),
        'contactName': (contactName ?? '').trim(),
        'contactPhone': (contactPhone ?? '').trim(),
        'contactEmail': (contactEmail ?? '').trim().toLowerCase(),
        'address': (address ?? '').trim(),
        'packageQty': (packageQty == null || packageQty < 1) ? 1 : packageQty,
        'notes': (notes ?? '').trim(),
      };
      if (kDebugMode) debugPrint('[CustomerService] POST /customers → $payload');
      final response = await _api.post(ApiConstants.customers, data: payload);
      return CustomerModel.fromJson(Map<String, dynamic>.from(response.data));
    } on DioException catch (e) {
      throw _err(e, 'เพิ่มลูกค้าไม่สำเร็จ');
    }
  }

  Future<CustomerModel> updateCustomer(
    String id, {
    String? name,
    String? contactName,
    String? contactPhone,
    String? contactEmail,
    String? address,
    int? packageQty,
    String? notes,
    bool? isActive,
  }) async {
    try {
      final data = <String, dynamic>{
        if (name != null) 'name': name.trim(),
        if (contactName != null) 'contactName': contactName.trim(),
        if (contactPhone != null) 'contactPhone': contactPhone.trim(),
        if (contactEmail != null)
          'contactEmail': contactEmail.trim().toLowerCase(),
        if (address != null) 'address': address.trim(),
        if (packageQty != null) 'packageQty': packageQty,
        if (notes != null) 'notes': notes.trim(),
        if (isActive != null) 'isActive': isActive,
      };
      final response =
          await _api.put('${ApiConstants.customers}/$id', data: data);
      return CustomerModel.fromJson(Map<String, dynamic>.from(response.data));
    } on DioException catch (e) {
      throw _err(e, 'แก้ไขลูกค้าไม่สำเร็จ');
    }
  }

  Future<void> deleteCustomer(String id) async {
    try {
      await _api.delete('${ApiConstants.customers}/$id');
    } on DioException catch (e) {
      throw _err(e, 'ลบลูกค้าไม่สำเร็จ');
    }
  }

  /// Extract the most useful error string possible.
  ///
  /// Priority:
  ///   1. Real message from backend response body (`data.message` or raw String)
  ///   2. HTTP status description with contextual fallback (403 → permission)
  ///   3. Network type fallback (timeout / no connection)
  ///   4. User-provided [fallback]
  String _err(DioException e, String fallback) {
    if (kDebugMode) {
      debugPrint(
        '[CustomerService] DioException type=${e.type} status=${e.response?.statusCode} data=${e.response?.data}',
      );
    }

    // Backend returned a response (4xx/5xx). Try to use its message.
    final resp = e.response;
    if (resp != null) {
      final data = resp.data;
      String? backendMsg;
      if (data is Map && data['message'] != null) {
        backendMsg = data['message'].toString();
      } else if (data is String && data.trim().isNotEmpty) {
        // Trim HTML/JSON noise to keep snackbar short.
        backendMsg = data.length > 140 ? '${data.substring(0, 140)}…' : data;
      }
      if (backendMsg != null && backendMsg.isNotEmpty) {
        return backendMsg;
      }
      // No message from backend — use status code hint.
      switch (resp.statusCode) {
        case 400:
          return 'ข้อมูลไม่ถูกต้อง (400) — ตรวจสอบฟอร์มอีกครั้ง';
        case 401:
          return 'เซสชันหมดอายุ (401) — กรุณาเข้าสู่ระบบใหม่';
        case 403:
          return 'ไม่มีสิทธิ์ดำเนินการ (403) — เฉพาะ Admin/Manager';
        case 404:
          return 'ไม่พบข้อมูล (404)';
        case 409:
          return 'ข้อมูลซ้ำในระบบ (409)';
        case 500:
        case 502:
        case 503:
          return 'เซิร์ฟเวอร์ผิดพลาด (${resp.statusCode}) — กรุณาลองใหม่';
      }
    }

    // Transport-level failures.
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'หมดเวลาเชื่อมต่อเซิร์ฟเวอร์ — ตรวจสอบอินเทอร์เน็ต';
      case DioExceptionType.connectionError:
        return 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ — ตรวจสอบ Wi-Fi/Mobile Data';
      case DioExceptionType.cancel:
        return 'ยกเลิกการร้องขอ';
      case DioExceptionType.badCertificate:
        return 'ใบรับรอง HTTPS ไม่ถูกต้อง';
      default:
        break;
    }
    return fallback;
  }
}
