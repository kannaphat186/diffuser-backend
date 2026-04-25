import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// CacheService — เก็บข้อมูลลูกค้าและเครื่องลง SharedPreferences
/// เพื่อให้แอปแสดงข้อมูลได้ทันทีแม้ไม่มี internet
/// Pattern: โหลด cache ก่อน → แสดง → fetch API ใน background → อัปเดต
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ========== Customers ==========

  Future<void> saveCustomers(List<Map<String, dynamic>> data) async {
    final prefs = await _p;
    await prefs.setString('cache_customers', jsonEncode(data));
    await prefs.setString('cache_customers_ts', DateTime.now().toIso8601String());
  }

  Future<List<Map<String, dynamic>>?> getCustomers() async {
    final prefs = await _p;
    final raw = prefs.getString('cache_customers');
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return list.cast<Map<String, dynamic>>();
  }

  // ========== Devices ==========

  Future<void> saveDevices(List<Map<String, dynamic>> data) async {
    final prefs = await _p;
    await prefs.setString('cache_devices', jsonEncode(data));
    await prefs.setString('cache_devices_ts', DateTime.now().toIso8601String());
  }

  Future<List<Map<String, dynamic>>?> getDevices() async {
    final prefs = await _p;
    final raw = prefs.getString('cache_devices');
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return list.cast<Map<String, dynamic>>();
  }

  // ========== Service Logs ==========

  Future<void> saveServiceLogs(List<Map<String, dynamic>> data) async {
    final prefs = await _p;
    await prefs.setString('cache_service_logs', jsonEncode(data));
  }

  Future<List<Map<String, dynamic>>?> getServiceLogs() async {
    final prefs = await _p;
    final raw = prefs.getString('cache_service_logs');
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return list.cast<Map<String, dynamic>>();
  }

  // ========== Users ==========

  Future<void> saveUsers(List<Map<String, dynamic>> data) async {
    final prefs = await _p;
    await prefs.setString('cache_users', jsonEncode(data));
  }

  Future<List<Map<String, dynamic>>?> getUsers() async {
    final prefs = await _p;
    final raw = prefs.getString('cache_users');
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return list.cast<Map<String, dynamic>>();
  }

  // ========== Cache Age Check ==========

  /// ตรวจว่า cache เก่ากว่า [minutes] นาทีหรือยัง
  Future<bool> isCacheStale(String key, {int minutes = 5}) async {
    final prefs = await _p;
    final tsStr = prefs.getString('${key}_ts');
    if (tsStr == null) return true;
    final ts = DateTime.tryParse(tsStr);
    if (ts == null) return true;
    return DateTime.now().difference(ts).inMinutes >= minutes;
  }

  // ========== Clear ==========

  Future<void> clearAll() async {
    final prefs = await _p;
    final keys = prefs.getKeys().where((k) => k.startsWith('cache_'));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
