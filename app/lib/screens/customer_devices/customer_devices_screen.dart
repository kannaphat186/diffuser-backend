import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';
import '../../providers/locale_provider.dart';
import '../../models/customer_model.dart';
import '../../models/device_model.dart';
import '../../services/customer_service.dart';
import '../../services/device_service.dart';

class CustomerDevicesScreen extends ConsumerStatefulWidget {
  final String customerId;
  const CustomerDevicesScreen({super.key, required this.customerId});
  @override
  ConsumerState<CustomerDevicesScreen> createState() =>
      _CustomerDevicesScreenState();
}

class _CustomerDevicesScreenState extends ConsumerState<CustomerDevicesScreen> {
  CustomerModel? _customer;
  List<DeviceModel> _devices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final customers = await CustomerService().getCustomers();
      _customer = customers.firstWhere((c) => c.id == widget.customerId);
      _devices = await DeviceService().getDevices(
        customerId: widget.customerId,
      );
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // v5.2.1 (Apr 2026): the bottom-sheet "pick between BLE wizard and
  // manual entry" chooser is gone. The manual path created ghost
  // devices (records with no real hardware behind them), so it has
  // been removed from the UI and the backend also returns 410 on
  // POST /api/devices. The BLE onboarding wizard is the only path.
  Future<void> _promptAddDevice(CustomerModel c, int slotNumber, String lang) async {
    if (!mounted) return;
    await context.push('/onboard/${widget.customerId}?slot=$slotNumber');
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    String t(String k) => AppStrings.get(k, lang);
    final c = _customer;
    final online = _devices.where((d) => d.isOnline).length;
    final offline = _devices.where((d) => !d.isOnline).length;
    final alerts = _devices.where((d) => d.needsAttention).length;

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
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(
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
                                c?.name ?? '...',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (c != null)
                                Text(
                                  '${t('package')} ${c.packageQty} ${t('devices')}',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _statBox(
                          '$online',
                          t('online'),
                          AppColors.success,
                          AppColors.successBg,
                        ),
                        const SizedBox(width: 8),
                        _statBox(
                          '$offline',
                          t('offline'),
                          AppColors.textSecondary,
                          AppColors.cardBackground,
                        ),
                        const SizedBox(width: 8),
                        _statBox(
                          '$alerts',
                          t('alerts'),
                          alerts > 0
                              ? AppColors.error
                              : AppColors.textSecondary,
                          alerts > 0
                              ? AppColors.errorBg
                              : AppColors.cardBackground,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.primary,
                    child: ListView(
                      padding: const EdgeInsets.all(14),
                      children: [
                        ..._devices.asMap().entries.map(
                          (e) => _deviceCard(e.value, e.key + 1, t, lang),
                        ),
                        // â˜… CHANGED: Empty slots are now tappable
                        if ((c?.packageQty ?? 0) > _devices.length) ...[
                          const SizedBox(height: 4),
                          Text(
                            lang == 'th' ? 'ช่องว่าง' : 'Empty Slots',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...List.generate(c!.packageQty - _devices.length, (
                            i,
                          ) {
                            final slotNumber = _devices.length + i + 1;
                            return GestureDetector(
                              onTap: () => _promptAddDevice(c, slotNumber, lang),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.cardWhite.withValues(
                                    alpha: 0.5,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.2,
                                    ),
                                    style: BorderStyle.solid,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    // â˜… NEW: + icon circle
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.08,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.add_rounded,
                                        color: AppColors.primary,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${lang == 'th' ? 'ช่องว่าง' : 'Slot'} $slotNumber',
                                            style: const TextStyle(
                                              color: AppColors.textDark,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            lang == 'th'
                                                ? 'กดเพื่อเพิ่มเครื่อง'
                                                : 'Tap to add device',
                                            style: TextStyle(
                                              color: AppColors.primary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: AppColors.primary.withValues(
                                        alpha: 0.5,
                                      ),
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String value, String label, Color valueColor, Color bg) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );

  Widget _deviceCard(
    DeviceModel d,
    int index,
    String Function(String) t,
    String lang,
  ) {
    final levelColor = d.level > 50
        ? AppColors.levelHigh
        : d.level > 20
        ? AppColors.levelMedium
        : AppColors.levelLow;
    // â˜… NEW: Calculate mL from % (tank capacity = 1000 mL)
    final mlValue = d.displayMl;
    return GestureDetector(
      onTap: () => context.push('/device/${d.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: d.needsAttention
                ? AppColors.error.withValues(alpha: 0.25)
                : AppColors.borderLight,
          ),
        ),
        child: Row(
          children: [
            // Index + status dot
            Column(
              children: [
                Text(
                  '$index',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: d.isOnline ? AppColors.success : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.displayName,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        d.serialNumber,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (d.location.isNotEmpty) ...[
                        Text(
                          '  ·  ',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          d.location,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // â˜… CHANGED: Level indicator shows both % and mL
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${d.level}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: levelColor,
                  ),
                ),
                Text(
                  '$mlValue mL',
                  style: TextStyle(
                    fontSize: 10,
                    color: levelColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  t('fragranceLevel'),
                  style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
