import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/api_constants.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio _dio;
  String? _token;

  // ★ NEW: callback เมื่อ token หมดอายุ (401) — ให้ auth_provider set
  static VoidCallback? onUnauthorized;

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        validateStatus: (status) => true,
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null && _token!.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          if (kDebugMode) {
            print('➡️ ${options.method} ${options.uri}');
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          if (kDebugMode) {
            print('✅ ${response.statusCode} ${response.requestOptions.uri}');
            print('📦 Response: ${response.data}');
          }

          // ★ NEW: ตรวจจับ 401 เมื่อมี token อยู่ = token หมดอายุ
          // ไม่เรียกตอน login (ตอนนั้น _token ยังเป็น null)
          if (response.statusCode == 401 &&
              _token != null &&
              _token!.isNotEmpty) {
            if (kDebugMode) {
              print('🔒 Token expired — triggering auto-logout');
            }
            // เรียก callback แบบ async เพื่อไม่ block response chain
            Future.microtask(() {
              onUnauthorized?.call();
            });
          }

          // ถ้า status code ไม่ใช่ 2xx ให้ throw DioException เอง
          if (response.statusCode != null && response.statusCode! >= 400) {
            final message = _extractMessage(response.data);
            return handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                response: response,
                type: DioExceptionType.badResponse,
                message: message,
              ),
            );
          }
          return handler.next(response);
        },
        onError: (error, handler) {
          if (kDebugMode) {
            print('❌ ${error.response?.statusCode} ${error.requestOptions.uri}');
            print('❌ Error: ${error.message}');
          }
          return handler.next(error);
        },
      ),
    );
  }

  String _extractMessage(dynamic data) {
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    if (data is String && data.isNotEmpty) return data;
    return 'เกิดข้อผิดพลาด';
  }

  Dio get dio => _dio;

  void setToken(String token) {
    _token = token;
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  void clearToken() {
    _token = null;
    _dio.options.headers.remove('Authorization');
  }

  bool get hasToken => _token != null && _token!.isNotEmpty;

  String? get token => _token;

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) {
    return _dio.get(path, queryParameters: queryParameters);
  }

  Future<Response> post(String path, {dynamic data}) {
    return _dio.post(path, data: data);
  }

  Future<Response> put(String path, {dynamic data}) {
    return _dio.put(path, data: data);
  }

  Future<Response> delete(String path, {dynamic data}) {
    return _dio.delete(path, data: data);
  }
}
