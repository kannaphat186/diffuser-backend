// lib/screens/onboarding/onboarding_wizard_screen.dart
// ─────────────────────────────────────────────────────────────
// End-to-end device onboarding wizard (v2 — Apr 2026)
//
// Single, coherent state machine covering:
//   scanBle → pickDevice → pickCustomer → pickWifi → password →
//   sendingCredentials → waitingForDevice → claimingDevice → done
//
// Key behaviour:
//   - BLE status characteristic drives the Wi-Fi list and the provisioning
//     outcome; no fake "wait 2 seconds and pretend" step anywhere.
//   - scanWifi() waits for the firmware's actual WIFI_END frame (or times out
//     after 14 s) via the dedicated BleWifiService._wifiScanEventCtrl stream.
//   - After sendWifiConfig(), we wait up to 45 s for the firmware to emit
//     OK / WIFI_FAIL / a composite status line with a non-zero IP. Only then
//     do we call /devices/claim — a false backend register is impossible.
//   - On claim success we use the returned device._id to navigate directly
//     to /device/<id>, the real control screen — not a dead "done" screen.
//   - Manual SSID is a fallback-only switch.
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/app_colors.dart';
import '../../models/customer_model.dart';
import '../../providers/customer_provider.dart';
import '../../providers/device_provider.dart';
import '../../providers/locale_provider.dart';
import '../../services/ble_wifi_service.dart';
import '../../services/device_service.dart';

enum OnboardStep {
  scanBle,
  pickCustomer,
  pickWifi,
  password,
  sendingCredentials,
  waitingForDevice,
  claimingDevice,
  done,
  failed,
}

class OnboardingWizardScreen extends ConsumerStatefulWidget {
  /// Pre-select a customer when the wizard is launched from a specific slot.
  final String? initialCustomerId;
  final int? slotNumber;

  const OnboardingWizardScreen({
    super.key,
    this.initialCustomerId,
    this.slotNumber,
  });

  @override
  ConsumerState<OnboardingWizardScreen> createState() =>
      _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState
    extends ConsumerState<OnboardingWizardScreen> {
  final _ble = BleWifiService();
  final _deviceSvc = DeviceService();

  // Wizard state
  OnboardStep _step = OnboardStep.scanBle;
  String? _error;
  String _busyMessage = '';

  // BLE
  bool _bleScanning = false;
  List<BleDevice> _bleDevices = const [];
  BleDevice? _selectedDevice;
  StreamSubscription<List<BleDevice>>? _bleDevSub;
  StreamSubscription<String>? _bleStatusSub;

  // Customer
  CustomerModel? _selectedCustomer;
  final _customerSearchC = TextEditingController();

  // Wi-Fi
  bool _wifiScanning = false;
  List<BleWifiAp> _wifiAps = const [];
  BleWifiAp? _selectedWifi;
  final _manualSsidC = TextEditingController();
  bool _useManualSsid = false;

  // Password / registration meta
  final _passC = TextEditingController();
  bool _showPass = false;
  final _deviceNameC = TextEditingController();
  final _locationC = TextEditingController();

  // Result of /claim (used to navigate to the newly-added device)
  String? _claimedDeviceId;

  @override
  void initState() {
    super.initState();
    _bleDevSub = _ble.devicesStream.listen((devices) {
      if (mounted) setState(() => _bleDevices = devices);
    });
    _bleStatusSub = _ble.statusStream.listen((_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _startBleScan());

    if (widget.initialCustomerId != null) {
      final customers = ref.read(customerProvider).customers;
      for (final c in customers) {
        if (c.id == widget.initialCustomerId) {
          _selectedCustomer = c;
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _bleDevSub?.cancel();
    _bleStatusSub?.cancel();
    _ble.stopScan();
    _customerSearchC.dispose();
    _manualSsidC.dispose();
    _passC.dispose();
    _deviceNameC.dispose();
    _locationC.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // State machine helpers
  // ─────────────────────────────────────────────────────────────
  void _goTo(OnboardStep step, {String? busy}) {
    if (!mounted) return;
    setState(() {
      _step = step;
      _error = null;
      _busyMessage = busy ?? '';
    });
  }

  Future<void> _startBleScan() async {
    setState(() {
      _bleScanning = true;
      _bleDevices = const [];
      _selectedDevice = null;
      _step = OnboardStep.scanBle;
      _error = null;
    });
    await _ble.startScan(timeout: const Duration(seconds: 12));
    if (mounted) setState(() => _bleScanning = false);
  }

  Future<void> _connectTo(BleDevice device) async {
    setState(() {
      _selectedDevice = device;
      _busyMessage = 'Connecting to ${device.name}...';
      _error = null;
    });
    final ok = await _ble.connect(device.id);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _error = 'BLE connection failed. Make sure the device is on and '
            'nearby, then try again.';
        _selectedDevice = null;
        _busyMessage = '';
      });
      return;
    }
    if (_deviceNameC.text.isEmpty) {
      _deviceNameC.text = device.name.replaceFirst('ScentSense-', '');
    }
    setState(() => _busyMessage = '');
    _goTo(OnboardStep.pickCustomer);
  }

  Future<void> _scanWifi() async {
    setState(() {
      _wifiScanning = true;
      _wifiAps = const [];
      _selectedWifi = null;
      _error = null;
    });
    final aps = await _ble.scanWifi(timeout: const Duration(seconds: 14));
    if (!mounted) return;
    final sorted = [...aps]..sort((a, b) {
        final ar = a.rssi ?? -999;
        final br = b.rssi ?? -999;
        return br.compareTo(ar);
      });
    setState(() {
      _wifiScanning = false;
      _wifiAps = sorted;
      if (sorted.isEmpty) {
        _error = 'The device did not find any Wi-Fi networks. Make sure the '
            'diffuser is within range of a 2.4 GHz network, or enter an SSID '
            'manually below.';
      }
    });
  }

  Future<void> _provisionAndRegister() async {
    final customer = _selectedCustomer;
    final device = _selectedDevice;
    if (customer == null || device == null) return;

    final ssid = _useManualSsid
        ? _manualSsidC.text.trim()
        : (_selectedWifi?.ssid.trim() ?? '');
    final password = _passC.text;
    if (ssid.isEmpty) {
      setState(() => _error =
          'Please pick a Wi-Fi network or enter an SSID manually.');
      return;
    }

    // ── Step: send credentials over BLE ────────────────────────
    _goTo(OnboardStep.sendingCredentials,
        busy: 'Sending Wi-Fi credentials over Bluetooth...');
    final sent = await _ble.sendWifiConfig(ssid, password);
    if (!mounted) return;
    if (!sent) {
      setState(() {
        _step = OnboardStep.password;
        _error = 'Failed to send Wi-Fi credentials to the device over '
            'Bluetooth. Please reconnect and retry.';
        _busyMessage = '';
      });
      return;
    }

    // ── Step: wait for firmware OK / WIFI_FAIL (no fake delay) ──
    _goTo(OnboardStep.waitingForDevice,
        busy: 'Waiting for the device to join "$ssid"...');
    final joined = await _ble.waitForProvisionOutcome(
      timeout: const Duration(seconds: 45),
    );
    if (!mounted) return;
    if (!joined) {
      setState(() {
        _step = OnboardStep.failed;
        _error =
            'Device failed to join "$ssid". Double-check the password and '
            'make sure the network is 2.4 GHz. You can retry from the '
            'password step.';
        _busyMessage = '';
      });
      return;
    }

    // ── Step: claim on backend ─────────────────────────────────
    _goTo(OnboardStep.claimingDevice,
        busy: 'Registering device to ${customer.name}...');

    final reportedDeviceId = _selectedDevice?.deviceId;
    final serial = device.name.replaceFirst('ScentSense-', '').trim();

    Map<String, dynamic> claim;
    try {
      claim = await _deviceSvc.claimDevice(
        serialNumber: serial.isEmpty ? device.id : serial,
        customerId: customer.id,
        name: _deviceNameC.text.trim().isEmpty
            ? device.name
            : _deviceNameC.text.trim(),
        location: _locationC.text.trim(),
        deviceId: reportedDeviceId,
        hardwareId: reportedDeviceId ?? device.id,
        wifiSSID: ssid,
        firmwareVersion: _selectedDevice?.firmware,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = OnboardStep.failed;
        _error = 'Backend claim failed: $e';
        _busyMessage = '';
      });
      return;
    }
    if (!mounted) return;

    // Extract the new device id from the claim response so we can route to it
    String? newId;
    final deviceField = claim['device'];
    if (deviceField is Map) {
      final raw = deviceField['_id'] ?? deviceField['id'];
      if (raw != null) newId = raw.toString();
    }
    newId ??= reportedDeviceId;
    _claimedDeviceId = newId;

    // Refresh local caches so the new device appears immediately
    try {
      await ref.read(deviceProvider.notifier).refresh();
      await ref.read(customerProvider.notifier).refresh();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _step = OnboardStep.done;
      _busyMessage = '';
    });
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    final isTh = lang == 'th';

    return Scaffold(
      backgroundColor: AppColors.bodyBg,
      body: Column(
        children: [
          _buildHeader(isTh),
          _buildStepIndicator(isTh),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildStepBody(isTh),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isTh) {
    return Container(
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
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _confirmExit(isTh),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: AppColors.textPrimary, size: 16),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isTh ? 'ติดตั้งเครื่อง Diffuser' : 'Install a Diffuser',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
              ),
              if (_selectedDevice != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bluetooth_connected,
                          color: AppColors.primary, size: 13),
                      const SizedBox(width: 4),
                      Text(
                        _selectedDevice!.name,
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(bool isTh) {
    final steps = [
      isTh ? 'ค้นหา' : 'Scan',
      isTh ? 'ลูกค้า' : 'Customer',
      isTh ? 'Wi-Fi' : 'Wi-Fi',
      isTh ? 'รหัสผ่าน' : 'Password',
      isTh ? 'ติดตั้ง' : 'Install',
      isTh ? 'เสร็จ' : 'Done',
    ];
    final current = _mappedIndicatorIndex();
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Row(
        children: List.generate(steps.length, (i) {
          final isActive = i <= current;
          final isCurrent = i == current;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.primary
                          : AppColors.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    steps[i],
                    style: TextStyle(
                      color: isCurrent
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight:
                          isCurrent ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  int _mappedIndicatorIndex() {
    switch (_step) {
      case OnboardStep.scanBle:
        return 0;
      case OnboardStep.pickCustomer:
        return 1;
      case OnboardStep.pickWifi:
        return 2;
      case OnboardStep.password:
        return 3;
      case OnboardStep.sendingCredentials:
      case OnboardStep.waitingForDevice:
      case OnboardStep.claimingDevice:
        return 4;
      case OnboardStep.done:
        return 5;
      case OnboardStep.failed:
        return 3;
    }
  }

  Widget _buildStepBody(bool isTh) {
    switch (_step) {
      case OnboardStep.scanBle:
        return _buildBleSection(isTh);
      case OnboardStep.pickCustomer:
        return _buildCustomerSection(isTh);
      case OnboardStep.pickWifi:
        return _buildWifiSection(isTh);
      case OnboardStep.password:
        return _buildPasswordSection(isTh);
      case OnboardStep.sendingCredentials:
      case OnboardStep.waitingForDevice:
      case OnboardStep.claimingDevice:
        return _buildProgressSection(isTh);
      case OnboardStep.done:
        return _buildDoneSection(isTh);
      case OnboardStep.failed:
        return _buildFailedSection(isTh);
    }
  }

  // ───────── BLE scan / pick device ─────────
  Widget _buildBleSection(bool isTh) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoBanner(
          icon: Icons.bluetooth_searching,
          color: AppColors.primary,
          title: isTh ? 'ค้นหาเครื่อง Diffuser ที่อยู่ใกล้' : 'Find nearby Diffusers',
          subtitle: isTh
              ? 'เปิดเครื่อง Diffuser และเปิด Bluetooth บนมือถือ'
              : 'Power on the diffuser and enable Bluetooth on this phone',
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _bleScanning ? null : _startBleScan,
          icon: _bleScanning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.refresh),
          label: Text(_bleScanning
              ? (isTh ? 'กำลังค้นหา...' : 'Scanning...')
              : (isTh ? 'สแกนอีกครั้ง' : 'Scan again')),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null) _errorBox(_error!),
        if (_busyMessage.isNotEmpty) _busyBox(_busyMessage),
        const SizedBox(height: 8),
        if (_bleDevices.isEmpty && !_bleScanning)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              children: [
                Icon(Icons.bluetooth_disabled,
                    size: 48,
                    color: AppColors.textSecondary.withValues(alpha: 0.4)),
                const SizedBox(height: 10),
                Text(
                  isTh ? 'ไม่พบเครื่อง Diffuser' : 'No Diffusers found',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  isTh
                      ? 'ตรวจสอบว่าเครื่องเปิดอยู่ แล้วลองสแกนอีกครั้ง'
                      : 'Check the device is on, then scan again',
                  style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.8),
                      fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ..._bleDevices.map((d) => _bleDeviceCard(d, isTh)),
      ],
    );
  }

  Widget _bleDeviceCard(BleDevice d, bool isTh) {
    final isTarget = _selectedDevice?.id == d.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTarget ? AppColors.primary : AppColors.borderLight,
          width: isTarget ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: d.isScentSense
                ? AppColors.primary.withValues(alpha: 0.1)
                : AppColors.borderLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.router_rounded,
              color: d.isScentSense
                  ? AppColors.primary
                  : AppColors.textSecondary),
        ),
        title: Text(d.name,
            style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        subtitle: Text('RSSI: ${d.rssi} dBm',
            style:
                TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        trailing:
            const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        onTap: () => _connectTo(d),
      ),
    );
  }

  // ───────── Customer ─────────
  Widget _buildCustomerSection(bool isTh) {
    final customers = ref.watch(customerProvider).customers;
    final q = _customerSearchC.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? customers
        : customers
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.contactName.toLowerCase().contains(q) ||
                c.address.toLowerCase().contains(q))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoBanner(
          icon: Icons.business_outlined,
          color: AppColors.success,
          title: isTh
              ? 'เลือกลูกค้าที่จะติดตั้งเครื่องนี้'
              : 'Select a customer for this device',
          subtitle: isTh
              ? 'เครื่องจะถูกผูกกับลูกค้านี้หลังตั้งค่า Wi-Fi สำเร็จ'
              : 'The device will be linked to this customer once Wi-Fi succeeds',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _customerSearchC,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: isTh ? 'ค้นหาลูกค้า...' : 'Search customer...',
            prefixIcon: const Icon(Icons.search, size: 18),
            filled: true,
            fillColor: AppColors.cardWhite,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.borderLight),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (customers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.people_outline,
                    size: 44, color: AppColors.textSecondary),
                const SizedBox(height: 10),
                Text(
                  isTh
                      ? 'ยังไม่มีลูกค้าในระบบ\nกรุณาเพิ่มลูกค้าก่อนติดตั้งเครื่อง'
                      : 'No customers yet.\nPlease add a customer before installing.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.push('/customers'),
                  icon: const Icon(Icons.add),
                  label: Text(isTh ? 'เพิ่มลูกค้า' : 'Add customer'),
                ),
              ],
            ),
          ),
        ...filtered.map((c) => _customerCard(c, isTh)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _selectedCustomer == null
                ? null
                : () {
                    _goTo(OnboardStep.pickWifi);
                    _scanWifi();
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
              disabledBackgroundColor: AppColors.cardBorder,
            ),
            child: Text(isTh ? 'ถัดไป' : 'Next',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _customerCard(CustomerModel c, bool isTh) {
    final selected = _selectedCustomer?.id == c.id;
    return GestureDetector(
      onTap: () => setState(() => _selectedCustomer = c),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  c.initial,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name,
                      style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${c.deviceCount}/${c.packageQty} ${isTh ? 'เครื่อง' : 'devices'}'
                    '${c.address.isNotEmpty ? '  ·  ${c.address}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  color: AppColors.primary, size: 22)
            else if (c.deviceCount >= c.packageQty && c.packageQty > 0)
              const Icon(Icons.lock_outline,
                  color: AppColors.warning, size: 18),
          ],
        ),
      ),
    );
  }

  // ───────── Wi-Fi list ─────────
  Widget _buildWifiSection(bool isTh) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoBanner(
          icon: Icons.wifi,
          color: AppColors.primary,
          title: isTh ? 'เลือก Wi-Fi สำหรับเครื่อง' : 'Choose Wi-Fi for the device',
          subtitle: isTh
              ? 'รายการนี้มาจากเครื่อง Diffuser เอง — ใช้ได้เฉพาะย่าน 2.4 GHz'
              : 'This list comes from the diffuser itself — only 2.4 GHz networks work',
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _wifiScanning ? null : _scanWifi,
          icon: _wifiScanning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.refresh),
          label: Text(_wifiScanning
              ? (isTh ? 'กำลังสแกน...' : 'Scanning...')
              : (isTh ? 'สแกน Wi-Fi อีกครั้ง' : 'Scan Wi-Fi again')),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null) _errorBox(_error!),
        if (_wifiAps.isEmpty && !_wifiScanning)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(
              children: [
                Icon(Icons.wifi_off,
                    size: 44,
                    color: AppColors.textSecondary.withValues(alpha: 0.4)),
                const SizedBox(height: 8),
                Text(
                  isTh ? 'ยังไม่พบ Wi-Fi' : 'No Wi-Fi found yet',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ..._wifiAps.map((ap) => _wifiCard(ap, isTh)),
        const SizedBox(height: 10),
        _manualSsidToggle(isTh),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed:
                _canProceedFromWifi() ? () => _goTo(OnboardStep.password) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
              disabledBackgroundColor: AppColors.cardBorder,
            ),
            child: Text(isTh ? 'ถัดไป' : 'Next',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  bool _canProceedFromWifi() {
    if (_useManualSsid) return _manualSsidC.text.trim().isNotEmpty;
    return _selectedWifi != null;
  }

  Widget _wifiCard(BleWifiAp ap, bool isTh) {
    final selected = !_useManualSsid && _selectedWifi?.ssid == ap.ssid;
    final rssi = ap.rssi ?? -100;
    IconData bars;
    if (rssi > -55) {
      bars = Icons.network_wifi;
    } else if (rssi > -70) {
      bars = Icons.network_wifi_3_bar;
    } else if (rssi > -80) {
      bars = Icons.network_wifi_2_bar;
    } else {
      bars = Icons.network_wifi_1_bar;
    }
    return GestureDetector(
      onTap: () => setState(() {
        _selectedWifi = ap;
        _useManualSsid = false;
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(bars,
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ap.ssid,
                      style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(ap.secured ? Icons.lock : Icons.lock_open,
                          size: 11, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text('${ap.rssi ?? '?'} dBm',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _manualSsidToggle(bool isTh) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isTh
                      ? 'ใช้ SSID แบบพิมพ์เอง (เครือข่ายซ่อน)'
                      : 'Enter SSID manually (hidden network)',
                  style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: _useManualSsid,
                onChanged: (v) => setState(() {
                  _useManualSsid = v;
                  if (v) _selectedWifi = null;
                }),
                activeThumbColor: AppColors.primary,
              ),
            ],
          ),
          if (_useManualSsid) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _manualSsidC,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: isTh ? 'ชื่อ Wi-Fi (SSID)' : 'Wi-Fi name (SSID)',
                prefixIcon: const Icon(Icons.wifi, size: 18),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderLight),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ───────── Password ─────────
  Widget _buildPasswordSection(bool isTh) {
    final ssid = _useManualSsid
        ? _manualSsidC.text.trim()
        : (_selectedWifi?.ssid ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _infoBanner(
          icon: Icons.lock_outline,
          color: AppColors.primary,
          title: isTh ? 'กรอกรหัสผ่าน Wi-Fi' : 'Enter Wi-Fi password',
          subtitle: 'SSID: $ssid',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passC,
          obscureText: !_showPass,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: isTh ? 'รหัสผ่าน' : 'Password',
            prefixIcon: const Icon(Icons.key, size: 18),
            suffixIcon: IconButton(
              icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility,
                  size: 18),
              onPressed: () => setState(() => _showPass = !_showPass),
            ),
            filled: true,
            fillColor: AppColors.cardWhite,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.borderLight),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            children: [
              Text(
                isTh
                    ? 'ตั้งชื่อและตำแหน่งเครื่อง (ไม่บังคับ)'
                    : 'Device name and location (optional)',
                style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _deviceNameC,
                decoration: InputDecoration(
                  labelText: isTh ? 'ชื่อเครื่อง' : 'Device name',
                  prefixIcon: const Icon(Icons.label_outline, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _locationC,
                decoration: InputDecoration(
                  labelText: isTh ? 'ตำแหน่ง (เช่น ห้องโถง)' : 'Location (e.g. Lobby)',
                  prefixIcon: const Icon(Icons.place_outlined, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null) _errorBox(_error!),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _passC.text.isEmpty ? null : _provisionAndRegister,
            icon: const Icon(Icons.rocket_launch_outlined),
            label: Text(isTh ? 'ติดตั้งและลงทะเบียน' : 'Install and register'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
              disabledBackgroundColor: AppColors.cardBorder,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => _goTo(OnboardStep.pickWifi),
          child: Text(isTh ? 'กลับไปเลือก Wi-Fi' : 'Back to Wi-Fi',
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  // ───────── Progress (sending / waiting / claiming) ─────────
  Widget _buildProgressSection(bool isTh) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            _busyMessage.isEmpty
                ? (isTh ? 'กำลังดำเนินการ...' : 'Working...')
                : _busyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textDark, fontSize: 14),
          ),
          const SizedBox(height: 12),
          _stepChipRow(isTh),
          const SizedBox(height: 12),
          Text(
            isTh
                ? 'ขั้นตอนนี้อาจใช้เวลาประมาณ 30–60 วินาที'
                : 'This may take 30–60 seconds',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _stepChipRow(bool isTh) {
    final steps = [
      (OnboardStep.sendingCredentials,
          isTh ? 'ส่งรหัส' : 'Sending creds'),
      (OnboardStep.waitingForDevice, isTh ? 'เชื่อมต่อ Wi-Fi' : 'Joining Wi-Fi'),
      (OnboardStep.claimingDevice,
          isTh ? 'ลงทะเบียน' : 'Registering'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: steps.map((pair) {
        final active = _step == pair.$1;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppColors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active ? AppColors.primary : AppColors.cardBorder,
              ),
            ),
            child: Text(
              pair.$2,
              style: TextStyle(
                color: active ? AppColors.primary : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ───────── Done ─────────
  Widget _buildDoneSection(bool isTh) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle,
                color: AppColors.success, size: 54),
          ),
          const SizedBox(height: 16),
          Text(
            isTh ? 'ติดตั้งสำเร็จ!' : 'Installation complete!',
            style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 20,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            isTh
                ? 'เครื่องเชื่อมต่อ Wi-Fi ใหม่แล้ว และถูกผูกกับลูกค้า ${_selectedCustomer?.name ?? ''}'
                : 'The device joined the new Wi-Fi and was linked to ${_selectedCustomer?.name ?? ''}.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.tune_rounded),
              onPressed: () {
                _ble.disconnect();
                final id = _claimedDeviceId;
                if (id != null && id.isNotEmpty) {
                  context.go('/device/$id');
                } else if (_selectedCustomer != null) {
                  context.go('/customer/${_selectedCustomer!.id}');
                } else {
                  context.go('/home');
                }
              },
              label: Text(isTh ? 'เปิดหน้าควบคุมเครื่อง' : 'Open device control'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              _ble.disconnect();
              setState(() {
                _step = OnboardStep.scanBle;
                _selectedDevice = null;
                _selectedWifi = null;
                _selectedCustomer = widget.initialCustomerId != null
                    ? _selectedCustomer
                    : null;
                _passC.clear();
                _manualSsidC.clear();
                _deviceNameC.clear();
                _locationC.clear();
                _useManualSsid = false;
                _error = null;
                _claimedDeviceId = null;
              });
              _startBleScan();
            },
            child: Text(isTh ? 'ติดตั้งเครื่องอื่น' : 'Install another',
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ───────── Failed ─────────
  Widget _buildFailedSection(bool isTh) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline,
                color: AppColors.error, size: 54),
          ),
          const SizedBox(height: 16),
          Text(
            isTh ? 'ติดตั้งไม่สำเร็จ' : 'Installation failed',
            style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 20,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _goTo(OnboardStep.password),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text(isTh ? 'ลองใหม่' : 'Retry',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              _ble.disconnect();
              if (mounted) context.pop();
            },
            child: Text(isTh ? 'ออก' : 'Exit',
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  // ───────── helpers ─────────
  Widget _infoBanner({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String msg) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.errorBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg,
                  style:
                      const TextStyle(color: AppColors.error, fontSize: 12)),
            ),
          ],
        ),
      );

  Widget _busyBox(String msg) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg,
                  style:
                      const TextStyle(color: AppColors.primary, fontSize: 12)),
            ),
          ],
        ),
      );

  void _confirmExit(bool isTh) async {
    if (_step == OnboardStep.scanBle ||
        _step == OnboardStep.done ||
        _step == OnboardStep.failed) {
      _ble.disconnect();
      if (mounted) context.pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isTh ? 'ออกจากการติดตั้ง?' : 'Leave setup?'),
        content: Text(isTh
            ? 'การตั้งค่ายังไม่เสร็จ ข้อมูลจะไม่ถูกบันทึก'
            : 'Setup is not finished. Nothing will be saved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isTh ? 'อยู่ต่อ' : 'Stay')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isTh ? 'ออก' : 'Leave',
                  style: const TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (leave == true && mounted) {
      _ble.disconnect();
      if (mounted) context.pop();
    }
  }
}
