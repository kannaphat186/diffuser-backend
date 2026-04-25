import 'package:dio/dio.dart';
import '../core/network/api_client.dart';
import '../core/constants/api_constants.dart';
import '../models/user_model.dart';

class UserService {
  final _api = ApiClient();

  Future<List<UserModel>> getUsers() async {
    try {
      final response = await _api.get(ApiConstants.users);
      final List<dynamic> data = response.data;
      return data.map((json) => UserModel.fromJson(json)).toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<UserModel> createUser({required String name, required String email, required String password, String role = 'technician'}) async {
    try {
      final response = await _api.post(ApiConstants.users, data: {'name': name, 'email': email, 'password': password, 'role': role});
      return UserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<UserModel> updateUser(String id, {String? name, String? email, String? password, String? role}) async {
    try {
      final response = await _api.put('${ApiConstants.users}/$id', data: {
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (password != null) 'password': password,
        if (role != null) 'role': role,
      });
      return UserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> deleteUser(String id) async {
    try {
      await _api.delete('${ApiConstants.users}/$id');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  String _handleError(DioException error) {
    if (error.response != null) {
      final data = error.response?.data;
      if (data is Map) return data['message'] ?? 'เกิดข้อผิดพลาด';
      return 'เกิดข้อผิดพลาด';
    }
    return 'ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์';
  }
}
