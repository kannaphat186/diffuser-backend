import 'package:dio/dio.dart';
import 'dart:async';
import '../core/network/api_client.dart';
import '../core/constants/api_constants.dart';
import '../models/auth_response_model.dart';
import 'storage_service.dart';

class AuthService {
  final _api = ApiClient();
  final _storage = StorageService();

  Future<AuthResponseModel> login({required String email, required String password}) async {
    // Retry policy:
    //   - Up to 4 attempts (first + 3 retries)
    //   - Only retry on transport failures (cold start / network glitch)
    //   - Never retry on 400/401 (wrong credentials) — that would waste time
    //     and potentially lock the user out on the backend side
    //   - 6s gap between attempts
    Object? lastError;
    for (int attempt = 1; attempt <= 4; attempt++) {
      try {
        final response = await _api.post(ApiConstants.login, data: {'email': email, 'password': password});
        final authResponse = AuthResponseModel.fromJson(response.data);
        _api.setToken(authResponse.token);
        await Future.wait([
          _storage.saveToken(authResponse.token),
          _storage.saveUser(authResponse.user.toJson()),
        ]);
        return authResponse;
      } on DioException catch (e) {
        lastError = e;
        // A real backend response (4xx/5xx) — don't retry.
        if (e.response != null) {
          throw _handleError(e);
        }
        // Only transport errors fall through here.
        final isTransient = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.connectionError;
        if (isTransient && attempt < 4) {
          await Future.delayed(const Duration(seconds: 6));
          continue;
        }
        throw _handleError(e);
      }
    }
    if (lastError is DioException) throw _handleError(lastError);
    throw 'ไม่สามารถเชื่อมต่อได้ กรุณาลองใหม่';
  }

  // v5.2.1 (Apr 2026): self-service password change removed.
  // Passwords are managed by admin / manager through UserService.

  Future<void> logout() async {
    // ทำการสั่ง logout แบบ fire-and-forget ไม่ต้องรอ API ตอบ
    unawaited(_api.post(ApiConstants.logout, data: {})
        .timeout(const Duration(seconds: 3))
        .catchError((_) => Response(requestOptions: RequestOptions(path: ''))));
    // ล็อคเอาท์ทันทีโดยไม่รอ API
    _api.clearToken();
    await _storage.clearAll();
  }

  Future<bool> isLoggedIn() async => await _storage.isLoggedIn();

  Future<void> restoreToken() async {
    final token = await _storage.getToken();
    if (token != null && token.isNotEmpty) _api.setToken(token);
  }

  String _handleError(DioException error) {
    final resp = error.response;
    if (resp != null) {
      final data = resp.data;
      String? backendMsg;
      if (data is Map && data['message'] != null) {
        backendMsg = data['message'].toString();
      } else if (data is String && data.trim().isNotEmpty) {
        backendMsg = data.length > 160 ? '${data.substring(0, 160)}…' : data;
      }
      if (backendMsg != null && backendMsg.isNotEmpty) return backendMsg;

      switch (resp.statusCode) {
        case 400:
        case 401:
          return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
        case 403:
          return 'ไม่มีสิทธิ์เข้าใช้งาน';
        case 404:
          return 'ไม่พบผู้ใช้นี้ในระบบ';
        case 429:
          return 'พยายามเข้าสู่ระบบบ่อยเกินไป กรุณารอสักครู่';
        case 500:
        case 502:
        case 503:
          return 'เซิร์ฟเวอร์ผิดพลาด (${resp.statusCode})\nกรุณาลองใหม่';
      }
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return 'หมดเวลาเชื่อมต่อเซิร์ฟเวอร์\nเซิร์ฟเวอร์อาจกำลัง wake-up ลองอีกครั้ง';
      case DioExceptionType.receiveTimeout:
        return 'เซิร์ฟเวอร์ตอบสนองช้าเกินไป\nกรุณาลองใหม่';
      case DioExceptionType.connectionError:
        return 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้\nตรวจสอบ Wi-Fi / Mobile Data';
      case DioExceptionType.badCertificate:
        return 'ใบรับรอง HTTPS ไม่ถูกต้อง';
      default:
        break;
    }
    return 'เข้าสู่ระบบไม่สำเร็จ';
  }
}