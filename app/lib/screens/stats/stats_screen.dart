// lib/screens/stats/stats_screen.dart — v2.0
//
// Fixes:
//   - Previously any API error silently replaced _stats with zeroed placeholders.
//     Staff saw "0 / 0 / 0" everywhere and couldn't tell if the backend was
//     down, their session expired, or the database was actually empty.
//   - Now we keep three clean states: loading, error (with retry), success.
//   - All data is read defensively with safe casts (int/num/bool) so a minor
//     backend shape change will not crash the widget tree.
//
// Uses only dependencies already in pubspec.yaml: flutter, flutter_riverpod,
// go_router, dio (indirect via ApiClient). No new packages.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../providers/locale_provider.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient().get(ApiConstants.stats);
      final data = response.data;
      if (data is! Map) {
        throw Exception('unexpected stats response shape');
      }
      if (!mounted) return;
      setState(() {
        _stats = Map<String, dynamic>.from(data);
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _dioMessage(e);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _dioMessage(DioException e) {
    final resp = e.response;
    if (resp != null) {
      final data = resp.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
      switch (resp.statusCode) {
        case 401:
          return 'เซสชันหมดอายุ (401) — กรุณาเข้าสู่ระบบใหม่';
        case 403:
          return 'ไม่มีสิทธิ์ดูสถิติ (403) — เฉพาะ Admin/Manager';
        case 404:
          return 'ไม่พบข้อมูลสถิติ (404)';
        case 500:
        case 502:
        case 503:
          return 'เซิร์ฟเวอร์ผิดพลาด (${resp.statusCode})';
      }
      return 'HTTP ${resp.statusCode}';
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'หมดเวลาเชื่อมต่อเซิร์ฟเวอร์';
      case DioExceptionType.connectionError:
        return 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ — ตรวจสอบ Wi-Fi/Mobile Data';
      default:
        return 'โหลดสถิติไม่สำเร็จ';
    }
  }

  int _i(String key) {
    final v = _stats?[key];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  Map<String, dynamic> _asMap(String key) {
    final v = _stats?[key];
    if (v is Map) return Map<String, dynamic>.from(v);
    return const {};
  }

  List<dynamic> _asList(String key) {
    final v = _stats?[key];
    if (v is List) return v;
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    String t(String key) => AppStrings.get(key, lang);
    final isTh = lang == 'th';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(t('stats'),
            style: const TextStyle(color: Colors.white, fontSize: 18)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loading ? null : _loadStats,
          ),
        ],
      ),
      body: _buildBody(isTh),
    );
  }

  Widget _buildBody(bool isTh) {
    if (_loading && _stats == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null && _stats == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                isTh ? 'โหลดสถิติไม่สำเร็จ' : 'Failed to load statistics',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadStats,
                icon: const Icon(Icons.refresh),
                label: Text(isTh ? 'ลองใหม่' : 'Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final hasNoData = _i('totalDevices') == 0 &&
        _i('totalCustomers') == 0 &&
        _asList('fragrancePerDevice').isEmpty;

    return RefreshIndicator(
      onRefresh: _loadStats,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) _refreshErrorBanner(_error!, isTh),
            if (hasNoData)
              _emptyState(isTh)
            else ...[
              Row(children: [
                _statCard(isTh ? 'เครื่องทั้งหมด' : 'Total',
                    '${_i('totalDevices')}', AppColors.primary),
                const SizedBox(width: 8),
                _statCard(isTh ? 'ออนไลน์' : 'Online',
                    '${_i('onlineDevices')}', AppColors.success),
                const SizedBox(width: 8),
                _statCard(isTh ? 'แจ้งเตือน' : 'Alerts',
                    '${_i('alertDevices')}', AppColors.error),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _statCard(isTh ? 'ลูกค้า' : 'Customers',
                    '${_i('totalCustomers')}', AppColors.info),
                const SizedBox(width: 8),
                _statCard(isTh ? 'น้ำหอมเฉลี่ย' : 'Avg Level',
                    '${_i('avgLevel')}%', AppColors.warning),
                const SizedBox(width: 8),
                _statCard(isTh ? 'เซอร์วิส 30วัน' : 'Logs 30d',
                    '${_i('recentServiceLogs')}', AppColors.primary),
              ]),
              const SizedBox(height: 20),
              _sectionTitle(isTh
                  ? 'เซอร์วิสตามประเภท (30 วัน)'
                  : 'Service by Type (30 days)'),
              const SizedBox(height: 10),
              ..._buildTypeBars(isTh),
              const SizedBox(height: 20),
              _sectionTitle(
                  isTh ? 'น้ำหอมแต่ละเครื่อง' : 'Fragrance per Device'),
              const SizedBox(height: 10),
              ..._buildFragranceRows(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _refreshErrorBanner(String msg, bool isTh) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isTh
                  ? 'อัปเดตข้อมูลล่าสุดไม่สำเร็จ: $msg'
                  : 'Could not refresh: $msg',
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(bool isTh) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Column(
          children: [
            Icon(Icons.bar_chart_rounded,
                size: 80, color: Colors.grey.shade600),
            const SizedBox(height: 12),
            Text(
              isTh ? 'ยังไม่มีข้อมูลสถิติ' : 'No statistics yet',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              isTh
                  ? 'เพิ่มลูกค้าและติดตั้งเครื่องเพื่อเริ่มต้นดูสถิติ'
                  : 'Add customers and install devices to start seeing statistics',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      );

  List<Widget> _buildTypeBars(bool isTh) {
    final logsByType = _asMap('logsByType');
    if (logsByType.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            isTh
                ? 'ยังไม่มีเซอร์วิสในช่วง 30 วัน'
                : 'No service logs in last 30 days',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ),
      ];
    }
    final maxCount = logsByType.values.fold<int>(
      0,
      (acc, v) => v is num && v.toInt() > acc ? v.toInt() : acc,
    );
    final scale = maxCount == 0 ? 1 : maxCount;
    return logsByType.entries
        .map((e) => _typeBar(e.key, e.value, isTh, scale))
        .toList();
  }

  List<Widget> _buildFragranceRows() {
    final devices = _asList('fragrancePerDevice');
    if (devices.isEmpty) return const [SizedBox.shrink()];
    return devices.map<Widget>((raw) {
      final d =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final lv = d['level'];
      final level = lv is num ? lv.toInt() : 0;
      final mlRaw = d['levelMl'];
      final ml = mlRaw is num ? mlRaw.toInt() : level * 10;
      final color = level > 50
          ? AppColors.success
          : level > 20
              ? AppColors.warning
              : AppColors.error;
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (d['name'] ?? '').toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (level.clamp(0, 100)) / 100,
                    backgroundColor: AppColors.cardBorder,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$level%',
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  )),
              Text('$ml mL',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.7),
                    fontSize: 10,
                  )),
            ],
          ),
        ]),
      );
    }).toList();
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _typeBar(String type, dynamic count, bool isTh, int scale) {
    final labels = {
      'refill': isTh ? 'เติมน้ำหอม' : 'Refill',
      'repair': isTh ? 'ซ่อม' : 'Repair',
      'inspection': isTh ? 'ตรวจเช็ค' : 'Inspection',
      'installation': isTh ? 'ติดตั้ง' : 'Installation',
      'uninstall': isTh ? 'ถอดเครื่อง' : 'Uninstall',
      'other': isTh ? 'อื่นๆ' : 'Other',
    };
    final colors = {
      'refill': AppColors.primary,
      'repair': AppColors.error,
      'inspection': AppColors.warning,
      'installation': AppColors.success,
      'uninstall': Colors.grey,
      'other': AppColors.info,
    };
    final n = count is num ? count.toInt() : 0;
    final progress = scale <= 0 ? 0.0 : (n / scale).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(
          width: 90,
          child: Text(
            labels[type] ?? type,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.cardBorder,
              valueColor: AlwaysStoppedAnimation<Color>(
                  colors[type] ?? AppColors.primary),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 32,
          child: Text(
            '$n',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: colors[type] ?? AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ]),
    );
  }
}
