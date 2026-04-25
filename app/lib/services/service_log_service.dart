import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../core/constants/api_constants.dart';
import '../models/service_log_model.dart';

class ServiceLogService {
  final _api = ApiClient();

  Future<List<ServiceLogModel>> getLogs({String? deviceId, String? customerId}) async {
    try {
      final params = <String, dynamic>{};
      if (deviceId != null) params['deviceId'] = deviceId;
      if (customerId != null) params['customerId'] = customerId;
      final response = await _api.get(ApiConstants.serviceLogs, queryParameters: params);
      return (response.data as List).map((j) => ServiceLogModel.fromJson(j)).toList();
    } on DioException catch (e) { throw _err(e); }
  }

  Future<ServiceLogModel> createLog({required String deviceId, String? taskId, required String type, String? description, String? notes, List<String>? photos}) async {
    try {
      final response = await _api.post(ApiConstants.serviceLogs, data: {
        'deviceId': deviceId, 'taskId': taskId, 'type': type,
        'description': description ?? '', 'notes': notes ?? '', 'photos': photos ?? [],
      });
      return ServiceLogModel.fromJson(response.data);
    } on DioException catch (e) { throw _err(e); }
  }

  Future<Map<String, dynamic>> exportReport({String? customerId, String? startDate, String? endDate}) async {
    try {
      final params = <String, dynamic>{};
      if (customerId != null) params['customerId'] = customerId;
      if (startDate != null) params['startDate'] = startDate;
      if (endDate != null) params['endDate'] = endDate;
      final response = await _api.get(ApiConstants.serviceLogsExport, queryParameters: params);
      return response.data;
    } on DioException catch (e) { throw _err(e); }
  }

  String _err(DioException e) => e.response?.data?['message'] ?? 'เกิดข้อผิดพลาด';
}
