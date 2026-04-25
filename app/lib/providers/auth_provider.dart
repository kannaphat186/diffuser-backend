import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../core/network/api_client.dart';

class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final UserModel? user;
  final String? error;

  AuthState({this.isLoading = false, this.isAuthenticated = false, this.user, this.error});

  AuthState copyWith({bool? isLoading, bool? isAuthenticated, UserModel? user, String? error, bool clearError = false}) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;
  final StorageService _storageService;
  bool _isHandlingUnauthorized = false;

  AuthNotifier(this._authService, this._storageService) : super(AuthState()) {
    ApiClient.onUnauthorized = _handleUnauthorized;
    checkAuthStatus();
  }

  void _handleUnauthorized() {
    if (_isHandlingUnauthorized) return;
    // ★ FIX: ถ้ายังไม่ได้ login อยู่ (เช่น อยู่หน้า login พิมพ์รหัสผิด) → ไม่ต้อง auto-logout
    if (!state.isAuthenticated) return;

    _isHandlingUnauthorized = true;
    if (kDebugMode) print('🔒 Auto-logout: token expired');

    ApiClient().clearToken();
    unawaited(_storageService.clearAll());
    state = AuthState();

    Future.delayed(const Duration(seconds: 2), () {
      _isHandlingUnauthorized = false;
    });
  }

  Future<void> checkAuthStatus() async {
    state = state.copyWith(isLoading: true);
    try {
      final isLoggedIn = await _storageService.isLoggedIn();
      if (isLoggedIn) {
        await _authService.restoreToken().timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
        final userData = await _storageService.getUser();
        if (userData != null) {
          state = state.copyWith(isLoading: false, isAuthenticated: true, user: UserModel.fromJson(userData));
          return;
        }
      }
    } catch (_) {}
    state = state.copyWith(isLoading: false, isAuthenticated: false);
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    // ★ FIX: ล้าง token เก่าก่อน login ใหม่ เพื่อป้องกัน 401 interceptor ทำงานผิด
    ApiClient().clearToken();
    try {
      final response = await _authService.login(email: email, password: password);
      state = state.copyWith(isLoading: false, isAuthenticated: true, user: response.user, error: null);
    } catch (e) {
      // ★ FIX v5.2 (Apr 2026): Previously, any empty/null error fell through
      // to the Thai string "อีเมลหรือรหัสผ่านไม่ถูกต้อง" — so a transport-level
      // bug that threw a bare exception would be misreported as "wrong
      // credentials", locking the user out of help loops. We now surface a
      // neutral generic error instead, and only the AuthService's explicit
      // 400/401 paths may produce the credentials-specific message.
      final msg = e.toString().replaceAll('Exception: ', '').trim();
      final errMsg = (msg.isEmpty || msg == 'null')
          ? 'ไม่สามารถเข้าสู่ระบบได้ในขณะนี้ กรุณาลองใหม่'
          : msg;
      state = state.copyWith(isLoading: false, isAuthenticated: false, error: errMsg);
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    state = AuthState();
  }

  // ★ NEW: อัปเดตข้อมูล user ใน state + storage (ใช้หลังแก้ชื่อ)
  Future<void> updateUserLocally(UserModel updatedUser) async {
    if (state.isAuthenticated) {
      state = state.copyWith(user: updatedUser);
      await _storageService.saveUser(updatedUser.toJson());
    }
  }

  @override
  void dispose() {
    ApiClient.onUnauthorized = null;
    super.dispose();
  }
}

final authServiceProvider = Provider((ref) => AuthService());
final storageServiceProvider = Provider((ref) => StorageService());
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authServiceProvider), ref.watch(storageServiceProvider));
});
