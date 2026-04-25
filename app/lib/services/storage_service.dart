import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  // Keep secure storage encrypted on Android, but recover cleanly if the
  // keystore entry becomes invalid after reinstall / restore.
  //
  // v5.2.2 (Apr 2026): flutter_secure_storage 10.x deprecated the explicit
  // `encryptedSharedPreferences: true` — it's now the default on Android,
  // and passing it emits an info-level analyzer warning. Using the
  // zero-arg constructor gives the same behaviour without the warning.
  final _secureStorage = const FlutterSecureStorage();
  SharedPreferences? _prefs;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
    }
  }

  Future<void> _resetSecureStorage() async {
    try {
      await _secureStorage.deleteAll();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Secure storage reset failed: $error');
      }
    }
  }

  bool _isRecoverableSecureStorageError(Object error) {
    if (error is PlatformException) return true;
    final message = error.toString().toLowerCase();
    return message.contains('decrypt') ||
        message.contains('keystore') ||
        message.contains('encryptedsharedpreferences') ||
        message.contains('bad padding');
  }

  Future<void> saveToken(String token) async {
    try {
      await _secureStorage.write(key: 'auth_token', value: token);
    } catch (error) {
      if (!_isRecoverableSecureStorageError(error)) rethrow;
      await _resetSecureStorage();
      await _secureStorage.write(key: 'auth_token', value: token);
    }
  }

  Future<String?> getToken() async {
    try {
      return await _secureStorage.read(key: 'auth_token');
    } catch (error) {
      if (_isRecoverableSecureStorageError(error)) {
        await _resetSecureStorage();
        return null;
      }
      rethrow;
    }
  }

  Future<void> saveUser(Map<String, dynamic> user) async {
    await _ensureInitialized();
    await _prefs?.setString('user_data', jsonEncode(user));
  }

  Future<Map<String, dynamic>?> getUser() async {
    await _ensureInitialized();
    final userData = _prefs?.getString('user_data');
    if (userData != null) return jsonDecode(userData);
    return null;
  }

  Future<void> clearAll() async {
    await _resetSecureStorage();
    await _ensureInitialized();
    await _prefs?.clear();
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> saveLanguage(String langCode) async {
    await _ensureInitialized();
    await _prefs?.setString('language_code', langCode);
  }

  Future<String?> getLanguage() async {
    await _ensureInitialized();
    return _prefs?.getString('language_code');
  }
}
