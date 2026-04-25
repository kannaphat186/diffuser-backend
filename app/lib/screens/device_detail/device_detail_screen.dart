import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:math';
import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';
import '../../providers/locale_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/device_model.dart';
import '../../models/service_log_model.dart';
import '../../services/device_service.dart';
import '../../services/service_log_service.dart';

class DeviceDetailScreen extends ConsumerStatefulWidget {
  final String deviceId;
  const DeviceDetailScreen({super.key, required this.deviceId});
  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  final _deviceSvc = DeviceService();
  DeviceModel? _device;
  List<ServiceLogModel> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _device = await _deviceSvc.getDevice(widget.deviceId);
      _logs = await ServiceLogService().getLogs(deviceId: widget.deviceId);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // â˜… NEW: Delete device with confirm dialog
  Future<void> _confirmDelete(DeviceModel d, String lang) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          lang == 'th' ? 'ลบเครื่อง' : 'Delete Device',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          lang == 'th'
              ? 'ต้องการลบ "${d.displayName}" ออกจากระบบ?\nการลบไม่สามารถย้อนกลับได้'
              : 'Delete "${d.displayName}" from the system?\nThis cannot be undone.',
          style: TextStyle(
            color: AppColors.textPrimary.withValues(alpha: 0.8),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              lang == 'th' ? 'ยกเลิก' : 'Cancel',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              lang == 'th' ? 'ลบเลย' : 'Delete',
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      try {
        await _deviceSvc.deleteDevice(d.id);
        if (mounted) context.pop();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                lang == 'th' ? 'ลบไม่สำเร็จ: $e' : 'Delete failed: $e',
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    final user = ref.watch(authProvider).user;
    final canManage = user?.isAdmin == true || user?.isManager == true;
    String t(String k) => AppStrings.get(k, lang);
    final d = _device;

    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.bodyBg,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (d == null) {
      return Scaffold(
        backgroundColor: AppColors.bodyBg,
        body: Center(
          child: Text(
            'Device not found',
            style: const TextStyle(color: AppColors.textPrimary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bodyBg,
      body: Column(
        children: [
          // Header
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => context.pop(),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: AppColors.cardBackground,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: AppColors.textPrimary,
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.displayName,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    d.serialNumber,
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (d.customerName.isNotEmpty) ...[
                                    Text(
                                      '  ·  ',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      d.customerName,
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Online/Offline badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: d.isOnline
                                ? AppColors.successBg
                                : AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: d.isOnline
                                  ? AppColors.success.withValues(alpha: 0.3)
                                  : AppColors.cardBorder,
                            ),
                          ),
                          child: Text(
                            d.isOnline ? t('online') : t('offline'),
                            style: TextStyle(
                              color: d.isOnline
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Delete button (Admin/Manager only)
                        if (canManage) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _confirmDelete(d, lang),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppColors.errorBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppColors.error.withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                color: AppColors.error,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Level circle + Power toggle row
                    Row(
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CustomPaint(
                            painter: _LevelPainter(
                              d.level,
                              _levelColor(d.level),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${d.level}%',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: _levelColor(d.level),
                                    ),
                                  ),
                                  Text(
                                    '${d.displayMl} mL',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: _levelColor(
                                        d.level,
                                      ).withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _infoChip(
                                Icons.location_on_outlined,
                                d.location.isNotEmpty
                                    ? d.location
                                    : (lang == 'th'
                                          ? 'ไม่ระบุ'
                                          : 'No location'),
                              ),
                              const SizedBox(height: 5),
                              _infoChip(
                                Icons.wifi,
                                d.wifiSSID.isNotEmpty
                                    ? d.wifiSSID
                                    : (lang == 'th'
                                          ? 'ยังไม่ได้เชื่อมต่อ'
                                          : 'Not connected'),
                              ),
                              const SizedBox(height: 5),
                              _infoChip(
                                Icons.memory_outlined,
                                '${t('firmwareVersion')} ${d.firmwareVersion}',
                              ),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            Switch(
                              value: d.isOn,
                              onChanged: (v) {
                                setState(() {
                                  _device = d.copyWith(isOn: v);
                                });
                                _deviceSvc.toggleDevice(d.id, v).catchError((
                                  _,
                                ) {
                                  if (mounted) _load();
                                });
                              },
                              activeThumbColor: AppColors.success,
                              activeTrackColor: AppColors.successBg,
                              inactiveThumbColor: AppColors.textSecondary,
                              inactiveTrackColor: AppColors.cardBackground,
                            ),
                            Text(
                              d.isOn ? t('running') : t('stopped'),
                              style: TextStyle(
                                fontSize: 9,
                                color: d.isOn
                                    ? AppColors.success
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Body scrollable
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  // Edit name/location tab
                  GestureDetector(
                    onTap: () => _showEditPopup(d, t, lang),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_note_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            lang == 'th'
                                ? 'แก้ไขชื่อเครื่อง / สถานที่'
                                : 'Edit device name / location',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.primary.withValues(alpha: 0.5),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // FAULT BANNER
                  if (!d.pumpOk || !d.relayOk)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.errorBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.warning_rounded,
                                color: AppColors.error,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                lang == 'th'
                                    ? '⚠ พบปัญหาฮาร์ดแวร์'
                                    : 'âš  Hardware Fault Detected',
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (!d.pumpOk)
                            _faultBanner(
                              lang == 'th' ? 'ปั๊มหยุดทำงาน' : 'Pump Stopped',
                              lang == 'th'
                                  ? 'แรงดันปั๊มต่ำ — ไดอะแฟรมอาจสึกหรอ ควรเรียกช่างตรวจสอบ'
                                  : 'Pump pressure low — diaphragm may be worn. Service required.',
                              AppColors.error,
                            ),
                          if (!d.relayOk)
                            _faultBanner(
                              lang == 'th'
                                  ? 'รีเลย์หยุดทำงาน'
                                  : 'Relay Failure',
                              lang == 'th'
                                  ? 'รีเลย์ไม่ตอบสนอง — ควรตรวจสอบด้านไฟฟ้า'
                                  : 'Relay not responding — check electrical circuit.',
                              AppColors.error,
                            ),
                        ],
                      ),
                    ),
                  // Connection row
                  Row(
                    children: [
                      Expanded(
                        child: _connCard(
                          icon: Icons.wifi_rounded,
                          label: 'WiFi',
                          value: d.wifiSSID.isNotEmpty
                              ? d.wifiSSID
                              : (lang == 'th'
                                    ? 'ไม่ได้เชื่อมต่อ'
                                    : 'Not connected'),
                          // v5.2.1: Change-Wi-Fi button removed. Wi-Fi
                          // reprovisioning only happens over BLE through
                          // the onboarding wizard, never from here.
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _connCard(
                          icon: Icons.bluetooth_rounded,
                          label: 'Bluetooth',
                          value: d.btConnected
                              ? t('connected')
                              : t('notConnected'),
                          actionLabel: t('manage'),
                          onAction: () => _showBTDialog(d, t),
                          valueColor: d.btConnected ? AppColors.success : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Schedule section
                  _sectionHeader(
                    t('scheduleMenu'),
                    Icons.schedule_rounded,
                    () => _showScheduleInfo(t),
                  ),
                  if (d.schedule.isEmpty)
                    _emptyTile(
                      lang == 'th'
                          ? 'ยังไม่มีตาราง กด + เพื่อเพิ่ม'
                          : 'No schedules yet. Tap + to add.',
                    )
                  else
                    ...d.schedule.map((s) => _scheduleTile(s, t, lang)),
                  const SizedBox(height: 12),
                  // Alerts
                  if (d.needsAttention) ...[
                    _sectionHeader(
                      lang == 'th' ? 'การแจ้งเตือน' : 'Alerts',
                      Icons.warning_amber_rounded,
                      null,
                      color: AppColors.warning,
                    ),
                    ...[
                      if (d.isLowLevel)
                        _alertTile(
                          lang == 'th'
                              ? 'น้ำหอมเหลือน้อย (${d.level}% · ${d.displayMl} mL)'
                              : 'Low fragrance (${d.level}% · ${d.displayMl} mL)',
                        ),
                      if (!d.pumpOk)
                        _alertTile(
                          lang == 'th'
                              ? 'ปั๊มเสีย — ควรเรียกช่าง'
                              : 'Pump failure — service needed',
                        ),
                      if (!d.relayOk)
                        _alertTile(
                          lang == 'th'
                              ? 'รีเลย์เสีย — ควรตรวจสอบ'
                              : 'Relay failure — check circuit',
                        ),
                      if (!d.isOnline)
                        _alertTile(
                          lang == 'th' ? 'เครื่องออฟไลน์' : 'Device is offline',
                        ),
                    ],
                    const SizedBox(height: 12),
                  ],
                  // Service log section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.history_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            t('serviceLog'),
                            style: const TextStyle(
                              color: AppColors.textDark,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => _showAddServiceLog(d, t, lang),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.add_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                lang == 'th' ? 'บันทึก' : 'Add',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_logs.isEmpty)
                    _emptyTile(
                      lang == 'th'
                          ? 'ยังไม่มีประวัติเซอร์วิส'
                          : 'No service logs yet',
                    )
                  else
                    ..._logs.take(5).map((l) => _logCard(l, lang)),
                  if (_logs.length > 5)
                    TextButton(
                      onPressed: () => _showAllLogs(lang),
                      child: Text(
                        lang == 'th'
                            ? 'ดูทั้งหมด ${_logs.length} รายการ'
                            : 'View all ${_logs.length} logs',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _levelColor(int level) {
    if (level > 50) return AppColors.levelHigh;
    if (level > 20) return AppColors.levelMedium;
    return AppColors.levelLow;
  }

  Widget _infoChip(IconData icon, String text) => Row(
    children: [
      Icon(icon, color: AppColors.textSecondary, size: 13),
      const SizedBox(width: 4),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.textPrimary.withValues(alpha: 0.85),
            fontSize: 11,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );

  Widget _connCard({
    required IconData icon,
    required String label,
    required String value,
    String? actionLabel,
    VoidCallback? onAction,
    Color? valueColor,
  }) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.cardWhite,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.borderLight),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.textDark,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _sectionHeader(
    String title,
    IconData icon,
    VoidCallback? onAction, {
    Color color = AppColors.primary,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            color: AppColors.textDark,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        if (onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.add_rounded,
                color: AppColors.primary,
                size: 18,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _emptyTile(String msg) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.cardWhite,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: AppColors.borderLight,
        style: BorderStyle.solid,
      ),
    ),
    child: Center(
      child: Text(
        msg,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    ),
  );

  Widget _alertTile(String msg) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.errorBg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.warning,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            msg,
            style: const TextStyle(
              color: AppColors.warning,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _scheduleTile(ScheduleItem s, String Function(String) t, String lang) {
    const daysTh = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];
    const daysEn = ['M', 'T', 'W', 'Th', 'F', 'Sa', 'Su'];
    final days = lang == 'th' ? daysTh : daysEn;
    final activeDays = s.activeDays
        .asMap()
        .entries
        .where((e) => e.value)
        .map((e) => days[e.key])
        .join('·');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s.startTime} – ${s.endTime}',
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$activeDays  ·  ${s.workSeconds}${t('seconds')}/${s.pauseSeconds}${t('seconds')}',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _logCard(ServiceLogModel l, String lang) {
    final colors = {
      'refill': AppColors.primary,
      'repair': AppColors.error,
      'inspection': AppColors.success,
      'installation': const Color(0xFFFF9500),
      'uninstall': AppColors.warning,
    };
    final c = colors[l.type] ?? AppColors.textSecondary;
    final typeLabel = lang == 'th' ? l.typeDisplayTh : l.typeDisplayEn;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: c, width: 3),
          top: BorderSide(color: AppColors.borderLight),
          right: BorderSide(color: AppColors.borderLight),
          bottom: BorderSide(color: AppColors.borderLight),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  typeLabel,
                  style: TextStyle(
                    color: c,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                l.createdAt.length >= 10
                    ? l.createdAt.substring(0, 10)
                    : l.createdAt,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
              ),
            ],
          ),
          if (l.description.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              l.description,
              style: const TextStyle(color: AppColors.textDark, fontSize: 12),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            l.technicianName,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
          ),
        ],
      ),
    );
  }

  // ===== DIALOGS =====

  void _showEditPopup(DeviceModel d, String Function(String) t, String lang) {
    final nameC = TextEditingController(text: d.name);
    final locC = TextEditingController(text: d.location);
    final user = ref.read(authProvider).user;
    final isTech = user?.role == 'technician' || user?.role == 'staff';
    final originalLocation = d.location;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final locationChanged = locC.text.trim() != originalLocation;
          return AlertDialog(
            backgroundColor: AppColors.cardBackground,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  lang == 'th' ? 'แก้ไขข้อมูลเครื่อง' : 'Edit Device Info',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textSecondary,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(
                  nameC,
                  lang == 'th' ? 'ชื่อเครื่อง' : 'Device Name',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: locC,
                  onChanged: (_) => setD(() {}),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    labelText: lang == 'th'
                        ? 'สถานที่ติดตั้ง'
                        : 'Install Location',
                    labelStyle: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                if (isTech && locationChanged) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: AppColors.warning,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            lang == 'th'
                                ? 'หาก Tech เปลี่ยนสถานที่ ระบบจะแจ้งเตือน Admin/Manager ทางอีเมลอัตโนมัติ'
                                : 'Location change by Tech will notify Admin/Manager via email',
                            style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  t('cancel'),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  try {
                    await _deviceSvc.updateDevice(
                      d.id,
                      name: nameC.text.trim(),
                      location: locC.text.trim(),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _load();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(t('saveSuccess')),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(e.toString()),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  }
                },
                child: Text(
                  t('save'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // v5.2.1 (Apr 2026): _showWiFiDialog removed. It used to scan the
  // phone's Wi-Fi, then call DeviceService.changeWiFi() which only
  // updated backend metadata — the ESP32 itself was never
  // reconfigured. Real Wi-Fi reprovisioning happens over BLE via
  // the onboarding wizard.

  void _showBTDialog(DeviceModel d, String Function(String) t) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.bluetooth_rounded,
                color: AppColors.primary,
                size: 26,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Bluetooth',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: d.btConnected
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      d.btConnected
                          ? '${d.serialNumber}  ·  ${t('connected')}'
                          : t('notConnected'),
                      style: TextStyle(
                        color: d.btConnected
                            ? AppColors.success
                            : AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Scanning...',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              t('close'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _showScheduleInfo(String Function(String) t) =>
      context.push('/schedule/${widget.deviceId}');

  void _showAddServiceLog(
    DeviceModel d,
    String Function(String) t,
    String lang,
  ) {
    bool refillChecked = false;
    final mlBeforeC = TextEditingController();
    final mlAfterC = TextEditingController();
    final scentC = TextEditingController();
    bool filterCleaned = false;
    bool malfunctionChecked = false;
    bool faultPump = false,
        faultRelay = false,
        faultWifi = false,
        faultLevel = false;
    final notesC = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppColors.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 20,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('addServiceLog'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${d.displayName}  ·  ${d.serialNumber}',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _checkGroup(
                  title: t('refill'),
                  icon: Icons.water_drop_rounded,
                  color: AppColors.primary,
                  children: [
                    _checkRow(
                      checked: refillChecked,
                      label: t('refill'),
                      onTap: () => setD(() => refillChecked = !refillChecked),
                    ),
                    if (refillChecked) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lang == 'th'
                                  ? 'ปริมาณน้ำหอม (mL)'
                                  : 'Fragrance amount (mL)',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lang == 'th' ? 'ก่อนเติม' : 'Before',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 10,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      TextField(
                                        controller: mlBeforeC,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        textAlign: TextAlign.center,
                                        decoration: InputDecoration(
                                          hintText: '0',
                                          hintStyle: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                          suffixText: 'mL',
                                          suffixStyle: const TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 10,
                                          ),
                                          filled: true,
                                          fillColor: AppColors.cardBackground,
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 8,
                                              ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            borderSide: BorderSide.none,
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            borderSide: const BorderSide(
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Icon(
                                    Icons.arrow_forward_rounded,
                                    color: AppColors.textSecondary,
                                    size: 16,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lang == 'th' ? 'หลังเติม' : 'After',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 10,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      TextField(
                                        controller: mlAfterC,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        textAlign: TextAlign.center,
                                        decoration: InputDecoration(
                                          hintText: '1000',
                                          hintStyle: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                          suffixText: 'mL',
                                          suffixStyle: const TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 10,
                                          ),
                                          filled: true,
                                          fillColor: AppColors.cardBackground,
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 8,
                                              ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            borderSide: BorderSide.none,
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            borderSide: const BorderSide(
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              lang == 'th'
                                  ? 'สูงสุด 1,000 mL (1 ลิตร)'
                                  : 'Max 1,000 mL (1 liter)',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 9,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: scentC,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                              ),
                              decoration: InputDecoration(
                                hintText: lang == 'th'
                                    ? 'กลิ่นน้ำหอม เช่น Lavender, Jasmine...'
                                    : 'Scent e.g. Lavender, Jasmine...',
                                hintStyle: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                                filled: true,
                                fillColor: AppColors.cardBackground,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    _checkRow(
                      checked: filterCleaned,
                      label: t('filterCleaned'),
                      onTap: () => setD(() => filterCleaned = !filterCleaned),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _checkGroup(
                  title: lang == 'th' ? 'พบปัญหา' : 'Issues Found',
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.error,
                  children: [
                    _checkRow(
                      checked: malfunctionChecked,
                      label: t('deviceMalfunction'),
                      onTap: () =>
                          setD(() => malfunctionChecked = !malfunctionChecked),
                      color: AppColors.error,
                    ),
                    if (malfunctionChecked) ...[
                      const SizedBox(height: 6),
                      _faultCheck(
                        label: t('faultPump'),
                        desc: t('faultPumpDesc'),
                        checked: faultPump,
                        onTap: () => setD(() => faultPump = !faultPump),
                      ),
                      _faultCheck(
                        label: t('faultRelay'),
                        desc: t('faultRelayDesc'),
                        checked: faultRelay,
                        onTap: () => setD(() => faultRelay = !faultRelay),
                      ),
                      _faultCheck(
                        label: t('faultWifi'),
                        desc: t('faultWifiDesc'),
                        checked: faultWifi,
                        onTap: () => setD(() => faultWifi = !faultWifi),
                      ),
                      _faultCheck(
                        label: t('faultLevel'),
                        desc: t('faultLevelDesc'),
                        checked: faultLevel,
                        onTap: () => setD(() => faultLevel = !faultLevel),
                        color: AppColors.warning,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesC,
                  maxLines: 2,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    labelText: t('notes'),
                    labelStyle: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: AppColors.cardBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                t('cancel'),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final parts = <String>[];
                if (refillChecked) {
                  final before = int.tryParse(mlBeforeC.text) ?? 0;
                  final after = int.tryParse(mlAfterC.text) ?? 0;
                  parts.add(
                    lang == 'th'
                        ? 'เติมน้ำหอม $before → $after mL'
                        : 'Refill $before → $after mL',
                  );
                  if (scentC.text.isNotEmpty) {
                    parts.add(
                      lang == 'th'
                          ? 'กลิ่น ${scentC.text}'
                          : 'Scent: ${scentC.text}',
                    );
                  }
                }
                if (filterCleaned) {
                  parts.add(
                    lang == 'th' ? 'ล้างฟิลเตอร์แล้ว' : 'Filter cleaned',
                  );
                }
                if (faultPump) parts.add(lang == 'th' ? 'ปั๊มเสีย' : 'Pump fault');
                if (faultRelay) parts.add(lang == 'th' ? 'รีเลย์เสีย' : 'Relay fault');
                if (faultWifi) parts.add(lang == 'th' ? 'WiFi อ่อน' : 'Weak WiFi');
                if (faultLevel) parts.add(lang == 'th' ? 'น้ำหอมต่ำ' : 'Low fragrance');
                if (notesC.text.isNotEmpty) parts.add(notesC.text);
                final type = malfunctionChecked
                    ? 'repair'
                    : refillChecked
                    ? 'refill'
                    : 'inspection';
                try {
                  await ServiceLogService().createLog(
                    deviceId: d.id,
                    type: type,
                    description: parts.join(' · '),
                    notes: notesC.text,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(t('saveSuccess')),
                        backgroundColor: AppColors.success,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(e.toString()),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: Text(
                t('save'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAllLogs(String lang) => showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, sc) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              lang == 'th' ? 'ประวัติเซอร์วิสทั้งหมด' : 'All Service Logs',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: sc,
                itemCount: _logs.length,
                itemBuilder: (_, i) => _logCard(_logs[i], lang),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _checkGroup({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) => Container(
    decoration: BoxDecoration(
      color: AppColors.cardWhite,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.borderLight),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.borderLight),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Column(children: children),
        ),
      ],
    ),
  );

  Widget _checkRow({
    required bool checked,
    required String label,
    required VoidCallback onTap,
    Widget? trailing,
    Color color = AppColors.primary,
  }) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: checked ? color : AppColors.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: checked ? color : AppColors.cardBorder),
            ),
            child: checked
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textDark,
                fontSize: 12,
                fontWeight: checked ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    ),
  );

  Widget _faultCheck({
    required String label,
    required String desc,
    required bool checked,
    required VoidCallback onTap,
    Color color = AppColors.error,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: checked ? color.withValues(alpha: 0.08) : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: checked ? color.withValues(alpha: 0.3) : AppColors.cardBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: checked ? color : AppColors.surface,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: checked ? color : AppColors.cardBorder),
            ),
            child: checked
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 12)
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _dialogField(
    TextEditingController c,
    String label, {
    bool obscure = false,
  }) => TextField(
    controller: c,
    obscureText: obscure,
    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    ),
  );
}

Widget _faultBanner(String title, String desc, Color color) => Container(
  margin: const EdgeInsets.only(top: 6),
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: color.withValues(alpha: 0.25)),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 3,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    ],
  ),
);

class _LevelPainter extends CustomPainter {
  final int level;
  final Color color;
  _LevelPainter(this.level, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.cardBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * (level / 100),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => true;
}
