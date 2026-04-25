import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';
import '../../providers/locale_provider.dart';
import '../../models/device_model.dart';
import '../../services/device_service.dart';

class AlertDevicesScreen extends ConsumerStatefulWidget {
  const AlertDevicesScreen({super.key});
  @override
  ConsumerState<AlertDevicesScreen> createState() => _AlertDevicesScreenState();
}

class _AlertDevicesScreenState extends ConsumerState<AlertDevicesScreen> {
  List<DeviceModel> _alertDevices = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final devices = await DeviceService().getDevices();
      _alertDevices = devices.where((d) => d.needsAttention).toList();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    String t(String k) => AppStrings.get(k, lang);
    final lowLevel = _alertDevices.where((d) => d.isLowLevel).length;
    final offline = _alertDevices.where((d) => !d.isOnline).length;
    final faultCount = _alertDevices.where((d) => !d.pumpOk || !d.relayOk).length;

    return Scaffold(
      backgroundColor: AppColors.bodyBg,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(color: AppColors.surface,
            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24))),
          child: SafeArea(bottom: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(children: [
              Row(children: [
                GestureDetector(onTap: () => context.pop(),
                  child: Container(width: 34, height: 34,
                    decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.cardBorder)),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 16))),
                const SizedBox(width: 10),
                Text(lang == 'th' ? '\u0e40\u0e04\u0e23\u0e37\u0e48\u0e2d\u0e07\u0e17\u0e35\u0e48\u0e15\u0e49\u0e2d\u0e07\u0e01\u0e32\u0e23\u0e04\u0e27\u0e32\u0e21\u0e2a\u0e19\u0e43\u0e08' : 'Devices Need Attention',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _summaryBox('$lowLevel', lang == 'th' ? '\u0e19\u0e49\u0e33\u0e2b\u0e2d\u0e21\u0e43\u0e01\u0e25\u0e49\u0e2b\u0e21\u0e14' : 'Low fragrance', AppColors.error, AppColors.errorBg),
                const SizedBox(width: 8),
                _summaryBox('$offline', t('offline'), AppColors.textSecondary, AppColors.cardBackground),
                const SizedBox(width: 8),
                _summaryBox('$faultCount', lang == 'th' ? '\u0e2e\u0e32\u0e23\u0e4c\u0e14\u0e41\u0e27\u0e23\u0e4c\u0e40\u0e2a\u0e35\u0e22' : 'Hardware fault', AppColors.warning, AppColors.warningBg),
              ]),
            ]),
          )),
        ),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _alertDevices.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.success.withValues(alpha: 0.1)),
                  child: const Icon(Icons.check_circle_outline_rounded, size: 50, color: AppColors.success)),
                const SizedBox(height: 16),
                Text(lang == 'th' ? '\u0e17\u0e38\u0e01\u0e40\u0e04\u0e23\u0e37\u0e48\u0e2d\u0e07\u0e1b\u0e01\u0e15\u0e34' : 'All devices are fine',
                  style: const TextStyle(color: AppColors.textDark, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(lang == 'th' ? '\u0e44\u0e21\u0e48\u0e21\u0e35\u0e40\u0e04\u0e23\u0e37\u0e48\u0e2d\u0e07\u0e17\u0e35\u0e48\u0e15\u0e49\u0e2d\u0e07\u0e01\u0e32\u0e23\u0e04\u0e27\u0e32\u0e21\u0e2a\u0e19\u0e43\u0e08' : 'No devices need attention',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ]))
            : RefreshIndicator(onRefresh: _load, color: AppColors.primary,
                child: ListView(padding: const EdgeInsets.all(14),
                  children: _alertDevices.map((d) => _alertCard(d, lang)).toList()))),
      ]),
    );
  }

  Widget _summaryBox(String value, String label, Color vc, Color bg) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: vc)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 9, color: AppColors.textSecondary), textAlign: TextAlign.center),
    ]),
  ));

  Widget _alertCard(DeviceModel d, String lang) {
    final issues = <String>[];
    if (d.isLowLevel) issues.add(lang == 'th' ? '\u0e19\u0e49\u0e33\u0e2b\u0e2d\u0e21\u0e40\u0e2b\u0e25\u0e37\u0e2d ${d.level}% (${d.displayMl} mL)' : 'Fragrance ${d.level}% (${d.displayMl} mL)');
    if (!d.pumpOk) issues.add(lang == 'th' ? '\u0e1b\u0e31\u0e4a\u0e21\u0e40\u0e2a\u0e35\u0e22' : 'Pump fault');
    if (!d.relayOk) issues.add(lang == 'th' ? '\u0e23\u0e35\u0e40\u0e25\u0e22\u0e4c\u0e40\u0e2a\u0e35\u0e22' : 'Relay fault');
    if (!d.isOnline) issues.add(lang == 'th' ? '\u0e2d\u0e2d\u0e1f\u0e44\u0e25\u0e19\u0e4c' : 'Offline');

    return GestureDetector(
      onTap: () => context.push('/device/${d.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.cardWhite, borderRadius: BorderRadius.circular(0),
          border: Border(left: const BorderSide(color: AppColors.error, width: 3),
            top: BorderSide(color: AppColors.borderLight), right: BorderSide(color: AppColors.borderLight), bottom: BorderSide(color: AppColors.borderLight))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.displayName, style: const TextStyle(color: AppColors.textDark, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${d.serialNumber} \u00b7 ${d.customerName}', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ])),
            Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary.withValues(alpha: 0.5), size: 22),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: issues.map((issue) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: Text(issue, style: const TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.w600)),
          )).toList()),
          const SizedBox(height: 6),
          Text(lang == 'th' ? '\u0e01\u0e14\u0e40\u0e1e\u0e37\u0e48\u0e2d\u0e14\u0e39\u0e23\u0e32\u0e22\u0e25\u0e30\u0e40\u0e2d\u0e35\u0e22\u0e14\u0e40\u0e04\u0e23\u0e37\u0e48\u0e2d\u0e07 \u2192' : 'Tap to view device details \u2192',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        ]),
      ),
    );
  }
}


