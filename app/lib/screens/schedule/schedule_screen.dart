// lib/screens/schedule/schedule_screen.dart — v5.2.1 (Apr 2026)
// ─────────────────────────────────────────────────────────────
// Changes vs previous version:
//   • The screen now REQUIRES an explicit deviceId through the route
//     (/schedule/:deviceId). Previously it relied on
//     deviceProvider.selectedDevice, which is ambient state — a user
//     coming back from navigation with a stale selection would have
//     silently edited the wrong device's schedule. Now the URL itself
//     identifies the target.
//   • The fake "Schedule enabled / disabled" toggle is removed. It
//     only flipped local widget opacity; the firmware was never told
//     anything and schedules kept running. Having an "off" state that
//     did nothing was misleading.
//   • Weekday index is explicit: 0=Mon, 1=Tue, 2=Wed, 3=Thu, 4=Fri,
//     5=Sat, 6=Sun. This matches Device.schedule.days[] in MongoDB and
//     the SCHEDULE_DAYS[] array in firmware_v2_5_0.ino. See the
//     `_kWeekdayKeys` constant below — any future edits must keep this
//     ordering in sync with backend and firmware, or schedules will
//     fire on the wrong day.
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/device_provider.dart';
import '../../providers/locale_provider.dart';
import '../../services/device_service.dart';
import '../../models/device_model.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';

// Canonical weekday order — must match backend `schedule.days[]` and
// firmware SCHEDULE_DAYS[]. Do NOT reorder without updating both.
const List<String> _kWeekdayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

class _ScheduleEntry {
  TimeOfDay startTime;
  TimeOfDay endTime;
  int workSeconds;
  int pauseSeconds;
  List<bool> activeDays;

  _ScheduleEntry({
    required this.startTime,
    required this.endTime,
    required this.workSeconds,
    required this.pauseSeconds,
    required this.activeDays,
  });
}

class ScheduleScreen extends ConsumerStatefulWidget {
  final String deviceId;
  const ScheduleScreen({super.key, required this.deviceId});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  final _service = DeviceService();
  List<_ScheduleEntry> _schedules = [];
  DeviceModel? _device;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDevice();
  }

  Future<void> _loadDevice() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final device = await _service.getDevice(widget.deviceId);
      _device = device;
      _schedules = device.schedule.map(_toEntry).toList();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  _ScheduleEntry _toEntry(ScheduleItem s) {
    final startParts = s.startTime.split(':');
    final endParts = s.endTime.split(':');
    // Guarantee the activeDays list is exactly length 7 (mon..sun).
    final days = List<bool>.generate(
      7,
      (i) => i < s.activeDays.length && s.activeDays[i] == true,
    );
    return _ScheduleEntry(
      startTime: TimeOfDay(
        hour: int.tryParse(startParts[0]) ?? 8,
        minute: int.tryParse(startParts.length > 1 ? startParts[1] : '0') ?? 0,
      ),
      endTime: TimeOfDay(
        hour: int.tryParse(endParts[0]) ?? 18,
        minute: int.tryParse(endParts.length > 1 ? endParts[1] : '0') ?? 0,
      ),
      workSeconds: s.workSeconds,
      pauseSeconds: s.pauseSeconds,
      activeDays: days,
    );
  }

  String _fmt24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    String t(String key) => AppStrings.get(key, lang);
    final days = _kWeekdayKeys.map(t).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(t('scheduleMenu'), style: const TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 60, color: AppColors.error),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadDevice,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                        child: Text(t('retry')),
                      ),
                    ],
                  ),
                )
              : _device == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.devices_other, size: 80, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(t('noDevice'), style: const TextStyle(color: Colors.white, fontSize: 18)),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _deviceInfo(_device!, t),
                          const SizedBox(height: 24),
                          Text(t('savedSchedules'),
                              style: const TextStyle(
                                  color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          if (_schedules.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: AppColors.cardBackground,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                              ),
                              child: Center(
                                child: Column(children: [
                                  const Icon(Icons.calendar_today, size: 60, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  Text(t('noSchedule'), style: const TextStyle(color: Colors.grey, fontSize: 16)),
                                  const SizedBox(height: 8),
                                  Text(t('pressAddToCreate'),
                                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                ]),
                              ),
                            )
                          else
                            ..._schedules.asMap().entries.map((e) => _scheduleCard(e.key, e.value, t, days)),
                          const SizedBox(height: 16),
                          Row(children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _schedules.isNotEmpty ? _saveSchedules : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  minimumSize: const Size(0, 50),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text(t('saveSchedule'),
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              height: 50,
                              decoration: BoxDecoration(
                                color: AppColors.cardBackground,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                              ),
                              child: IconButton(
                                onPressed: _addSchedule,
                                icon: const Icon(Icons.add_rounded, color: AppColors.primary, size: 24),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
    );
  }

  Widget _deviceInfo(DeviceModel device, String Function(String) t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.router, color: AppColors.primary, size: 30),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(device.displayName,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: device.isOnline ? AppColors.success : Colors.grey),
              ),
              const SizedBox(width: 6),
              Text(
                device.isOnline ? t('online') : t('offline'),
                style: TextStyle(color: device.isOnline ? AppColors.success : Colors.grey, fontSize: 12),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _scheduleCard(int index, _ScheduleEntry s, String Function(String) t, List<String> days) {
    return Card(
      color: AppColors.cardBackground,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${t('scheduleNo')} ${index + 1}',
                  style: const TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.delete, color: AppColors.error, size: 20),
                onPressed: () => setState(() => _schedules.removeAt(index)),
              ),
            ]),
            const Divider(color: Colors.grey),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _timeSelector(
                    t('startTime'), s.startTime, (time) => setState(() => s.startTime = time)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _timeSelector(
                    t('endTime'), s.endTime, (time) => setState(() => s.endTime = time)),
              ),
            ]),
            const SizedBox(height: 16),
            _sliderWithInput(t('work'), s.workSeconds, 5, 600, t('seconds'),
                (v) => setState(() => s.workSeconds = v)),
            const SizedBox(height: 12),
            _sliderWithInput(t('pause'), s.pauseSeconds, 5, 600, t('seconds'),
                (v) => setState(() => s.pauseSeconds = v)),
            const SizedBox(height: 16),
            Text(t('activeDays'), style: const TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(
                7,
                (di) => GestureDetector(
                  onTap: () => setState(() => s.activeDays[di] = !s.activeDays[di]),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: s.activeDays[di] ? AppColors.primary : Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: s.activeDays[di] ? AppColors.primary : Colors.grey),
                    ),
                    child: Center(
                      child: Text(
                        days[di],
                        style: TextStyle(
                          color: s.activeDays[di] ? Colors.white : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeSelector(String label, TimeOfDay time, Function(TimeOfDay) onChanged) {
    return GestureDetector(
      onTap: () => _showTimePicker(time, onChanged),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(_fmt24(time),
              style: const TextStyle(
                  color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Future<void> _showTimePicker(TimeOfDay initialTime, Function(TimeOfDay) onChanged) async {
    int h = initialTime.hour, m = initialTime.minute;
    final lang = ref.read(localeProvider).languageCode;
    String t(String key) => AppStrings.get(key, lang);

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          backgroundColor: AppColors.cardBackground,
          title: Text(t('selectTime'), style: const TextStyle(color: Colors.white)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _wheel(h, 24, (i) => setD(() => h = i)),
              const SizedBox(width: 16),
              const Text(':', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              _wheel(m, 60, (i) => setD(() => m = i)),
            ]),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(t('cancel'), style: const TextStyle(color: Colors.grey))),
            TextButton(
                onPressed: () => Navigator.pop(c, {'hour': h, 'minute': m}),
                child: Text(t('confirm'), style: const TextStyle(color: AppColors.primary))),
          ],
        ),
      ),
    );
    if (result != null) onChanged(TimeOfDay(hour: result['hour']!, minute: result['minute']!));
  }

  Widget _wheel(int selected, int count, Function(int) onChanged) {
    return Container(
      width: 80,
      height: 150,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: ListWheelScrollView.useDelegate(
        itemExtent: 50,
        perspective: 0.005,
        diameterRatio: 1.2,
        physics: const FixedExtentScrollPhysics(),
        controller: FixedExtentScrollController(initialItem: selected),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (c, i) {
            final sel = i == selected;
            return Center(
              child: Text(
                i.toString().padLeft(2, '0'),
                style: TextStyle(
                  color: sel ? AppColors.primary : Colors.grey,
                  fontSize: sel ? 24 : 18,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sliderWithInput(String label, int value, double min, double max, String unit,
      Function(int) onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14))),
        SizedBox(
          width: 70,
          height: 36,
          child: TextField(
            controller: TextEditingController(text: '$value'),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.bold),
            onSubmitted: (text) {
              final v = (int.tryParse(text) ?? value).clamp(min.toInt(), max.toInt());
              onChanged(v);
            },
            decoration: InputDecoration(
              suffixText: unit,
              suffixStyle: const TextStyle(color: Colors.grey, fontSize: 10),
              filled: true,
              fillColor: AppColors.background,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: AppColors.primary,
          inactiveTrackColor: Colors.grey.shade800,
          thumbColor: AppColors.primary,
          overlayColor: AppColors.primary.withValues(alpha: 0.2),
        ),
        child: Slider(
          value: value.toDouble().clamp(min, max),
          min: min,
          max: max,
          divisions: ((max - min) / 5).toInt(),
          onChanged: (v) => onChanged(v.toInt()),
        ),
      ),
    ]);
  }

  void _addSchedule() => setState(
        () => _schedules.add(_ScheduleEntry(
          startTime: const TimeOfDay(hour: 8, minute: 0),
          endTime: const TimeOfDay(hour: 18, minute: 0),
          workSeconds: 30,
          pauseSeconds: 60,
          // Default: weekdays (Mon-Fri) on; Sat/Sun off.
          activeDays: [true, true, true, true, true, false, false],
        )),
      );

  Future<void> _saveSchedules() async {
    final lang = ref.read(localeProvider).languageCode;
    String t(String key) => AppStrings.get(key, lang);
    try {
      final updated = await _service.updateSchedule(
        widget.deviceId,
        _schedules
            .map((s) => {
                  'startTime': _fmt24(s.startTime),
                  'endTime': _fmt24(s.endTime),
                  'workSeconds': s.workSeconds,
                  'pauseSeconds': s.pauseSeconds,
                  // Backend field name is `days`, ordered mon..sun (see
                  // _kWeekdayKeys at top of file).
                  'days': s.activeDays,
                })
            .toList(),
      );
      // Keep the cached device list in sync so the detail screen reflects
      // the new schedule without a full refresh.
      ref.read(deviceProvider.notifier).upsertDevice(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('saveSuccess')), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t('error')}: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }
}
