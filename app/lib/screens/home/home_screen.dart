// lib/screens/home/home_screen.dart — v3.0 Production
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/customer_provider.dart';
import '../../models/customer_model.dart';
import '../../models/device_model.dart';
import '../../services/device_service.dart';
import '../../services/cache_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchC = TextEditingController();
  List<CustomerModel> _customers = [];
  List<DeviceModel> _allDevices = [];
  bool _loading = true;
  Timer? _refreshTimer;
  final _cache = CacheService();

  @override
  void initState() {
    super.initState();
    _loadCachedThenFetch();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _silentLoad());
  }

  Future<void> _loadCachedThenFetch() async {
    try {
      final cachedCustomers = await _cache.getCustomers();
      final cachedDevices = await _cache.getDevices();
      if (cachedCustomers != null && cachedCustomers.isNotEmpty) {
        _customers = cachedCustomers.map((j) => CustomerModel.fromJson(j)).toList();
      }
      if (cachedDevices != null && cachedDevices.isNotEmpty) {
        _allDevices = cachedDevices.map((j) => DeviceModel.fromJson(j)).toList();
      }
      if (_customers.isNotEmpty || _allDevices.isNotEmpty) {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {}
    await _load();
  }

  Future<void> _load() async {
    if (_customers.isEmpty && _allDevices.isEmpty) setState(() => _loading = true);
    try {
      await ref.read(customerProvider.notifier).loadCustomers(skipCache: true);
      final devices = await DeviceService().getDevices();
      _customers = ref.read(customerProvider).customers;
      _allDevices = devices;
      _cache.saveCustomers(_customers.map((c) => <String, dynamic>{
        'id': c.id, 'name': c.name, 'contactName': c.contactName,
        'contactPhone': c.contactPhone, 'contactEmail': c.contactEmail,
        'address': c.address, 'packageQty': c.packageQty, 'notes': c.notes,
        'deviceCount': c.deviceCount, 'onlineCount': c.onlineCount,
        'alertCount': c.alertCount, 'createdAt': c.createdAt,
      }).toList());
      _cache.saveDevices(devices.map((d) => <String, dynamic>{
        'id': d.id, 'serialNumber': d.serialNumber, 'name': d.name,
        'customerId': d.customerId, 'customerName': d.customerName,
        'location': d.location, 'status': d.status, 'isOn': d.isOn,
        'level': d.level, 'pumpOk': d.pumpOk, 'relayOk': d.relayOk,
        'wifiSSID': d.wifiSSID, 'firmwareVersion': d.firmwareVersion,
      }).toList());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _silentLoad() async {
    try {
      await ref.read(customerProvider.notifier).loadCustomers(skipCache: true);
      _customers = ref.read(customerProvider).customers;
      _allDevices = await DeviceService().getDevices();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchC.dispose();
    super.dispose();
  }

  List<CustomerModel> get _filtered {
    final q = _searchC.text.toLowerCase();
    if (q.isEmpty) return _customers;
    return _customers.where((c) =>
      c.name.toLowerCase().contains(q) ||
      c.address.toLowerCase().contains(q)
    ).toList();
  }

  String _greeting(String lang) {
    final h = DateTime.now().hour;
    if (h < 12) return AppStrings.get('goodMorning', lang);
    if (h < 17) return AppStrings.get('goodAfternoon', lang);
    return AppStrings.get('goodEvening', lang);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final lang = ref.watch(localeProvider).languageCode;
    String t(String k) => AppStrings.get(k, lang);
    final user = auth.user;
    final canManage = user?.isAdmin == true || user?.isManager == true;
    final totalDevices = _allDevices.length;
    final totalOnline = _allDevices.where((d) => d.isOnline).length;
    final totalAlerts = _allDevices.where((d) => d.needsAttention).length;

    return Scaffold(
      backgroundColor: AppColors.bodyBg,
      body: Column(children: [
        // ═══ HEADER ═══
        Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(children: [
                // ─── Row: ทักทาย + ปุ่ม Scan / Notification / Profile ───
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // ชื่อ + ทักทาย
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _greeting(lang),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user?.name ?? '',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ปุ่ม: Install (wizard) + Scan + Notification + Profile
                    Row(children: [
                      // ★ NEW: Install button → end-to-end onboarding wizard
                      if (canManage) ...[
                        GestureDetector(
                          onTap: () => context.push('/onboard'),
                          child: Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(color: AppColors.success.withValues(alpha: 0.45)),
                            ),
                            child: const Icon(Icons.add_to_home_screen_rounded,
                                color: AppColors.success, size: 20),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      // (v6.0 cleanup) Redundant Scan magnifier removed —
                      // the green Install button above is the single entry
                      // point for adding a device via the onboarding wizard.
                      // A separate content search bar below still exists for
                      // filtering the customer list.
                      // ปุ่ม Notification
                      GestureDetector(
                        onTap: () => context.push('/notifications'),
                        child: Stack(children: [
                          Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.cardBackground,
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: const Icon(Icons.notifications_outlined, color: AppColors.textPrimary, size: 20),
                          ),
                          if (totalAlerts > 0)
                            Positioned(
                              right: 5, top: 5,
                              child: Container(
                                width: 9, height: 9,
                                decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                              ),
                            ),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      // ปุ่ม Profile / Menu
                      GestureDetector(
                        onTap: () => _showDrawer(context, t, auth, user),
                        child: Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: Center(
                            child: Text(
                              user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'A',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
                const SizedBox(height: 16),
                // ─── Stats Row ───
                Row(children: [
                  _statBox(t('totalDevices'), '$totalDevices', null),
                  const SizedBox(width: 8),
                  _statBox(t('online'), '$totalOnline', AppColors.success),
                  const SizedBox(width: 8),
                  _statBox(
                    t('alerts'), '$totalAlerts',
                    totalAlerts > 0 ? AppColors.error : null,
                    bg: totalAlerts > 0 ? AppColors.errorBg : null,
                    hasBorder: totalAlerts > 0,
                  ),
                ]),
                const SizedBox(height: 12),
                // ─── Search Bar ───
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: TextField(
                    controller: _searchC,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: '${t('search')}...',
                      hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),

        // ═══ BODY ═══
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.primary,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ─── Alert Banner ───
                    if (totalAlerts > 0)
                      GestureDetector(
                        onTap: () => context.push('/alert-devices'),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.errorBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '$totalAlerts ${lang == 'th' ? 'เครื่องต้องการความสนใจ' : 'device(s) need attention'}',
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: AppColors.error.withValues(alpha: 0.7), size: 20),
                          ]),
                        ),
                      ),

                    // ─── ลูกค้า Header ───
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('customers'),
                              style: const TextStyle(
                                color: AppColors.textDark,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: 40, height: 3,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                        if (canManage)
                          GestureDetector(
                            onTap: () => _showAddCustomerDialog(t),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  t('add'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ]),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ─── Customer Cards ───
                    ..._filtered.map((c) => _customerCard(c, t)),

                    // ─── Unassigned Devices ───
                    if (_allDevices.any((d) => !d.isAssigned)) ...[
                      const SizedBox(height: 18),
                      Text(
                        lang == 'th' ? 'ยังไม่ผูกลูกค้า' : 'Unassigned Devices',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._allDevices.where((d) => !d.isAssigned).map((d) => _unassignedCard(d)),
                    ],
                  ],
                ),
              ),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════
  //  Widgets
  // ═══════════════════════════════════════════════

  Widget _statBox(String label, String value, Color? valueColor, {Color? bg, bool hasBorder = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: bg ?? AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: hasBorder
            ? Border.all(color: (valueColor ?? AppColors.primary).withValues(alpha: 0.3))
            : Border.all(color: AppColors.cardBorder),
        ),
        child: Column(children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }

  Widget _customerCard(CustomerModel c, String Function(String) t) {
    final colors = [
      AppColors.primary,
      const Color(0xFFFF9500),
      const Color(0xFFFF3B30),
      const Color(0xFF5856D6),
      const Color(0xFF34C759),
    ];
    final color = colors[c.name.hashCode.abs() % colors.length];
    final hasAlert = c.alertCount > 0;

    return GestureDetector(
      onTap: () => context.push('/customer/${c.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasAlert ? AppColors.error.withValues(alpha: 0.3) : AppColors.borderLight,
          ),
        ),
        child: Row(children: [
          // Initial avatar
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Center(
              child: Text(
                c.initial,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 5),
                Row(children: [
                  _miniTag(
                    '${c.deviceCount} ${t('devices')}',
                    AppColors.primary.withValues(alpha: 0.08),
                    AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  if (hasAlert)
                    _miniTag(
                      '${c.alertCount} ${t('alerts')}',
                      AppColors.error.withValues(alpha: 0.08),
                      AppColors.error,
                    )
                  else
                    _miniTag(
                      t('active'),
                      AppColors.success.withValues(alpha: 0.08),
                      AppColors.success,
                    ),
                ]),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
            size: 22,
          ),
        ]),
      ),
    );
  }

  Widget _miniTag(String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
    child: Text(
      text,
      style: TextStyle(
        color: fg,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
    ),
  );

  Widget _unassignedCard(DeviceModel d) => GestureDetector(
    onTap: () => context.push('/device/${d.id}'),
    child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardWhite.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: d.isOnline ? AppColors.success : Colors.grey,
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
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                d.serialNumber,
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.chevron_right_rounded,
          color: AppColors.textSecondary.withValues(alpha: 0.4),
          size: 18,
        ),
      ]),
    ),
  );

  // ═══════════════════════════════════════════════
  //  Add Customer Dialog
  // ═══════════════════════════════════════════════

  void _showAddCustomerDialog(String Function(String) t) {
    final nameC = TextEditingController();
    final contactC = TextEditingController();
    final phoneC = TextEditingController();
    final emailC = TextEditingController();
    final addrC = TextEditingController();
    final noteC = TextEditingController();
    final pkgC = TextEditingController(text: '1');
    bool saving = false;

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        t('addCustomer'),
        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _dialogField(nameC, t('customerName'), Icons.business),
        const SizedBox(height: 10),
        _dialogField(contactC, t('contact'), Icons.person),
        const SizedBox(height: 10),
        _dialogField(phoneC, t('phone'), Icons.phone, type: TextInputType.phone),
        const SizedBox(height: 10),
        _dialogField(emailC, t('email'), Icons.email, type: TextInputType.emailAddress),
        const SizedBox(height: 10),
        _dialogField(addrC, t('address'), Icons.location_on),
        const SizedBox(height: 10),
        _dialogField(pkgC, t('packageQty'), Icons.router, type: TextInputType.number),
        const SizedBox(height: 10),
        _dialogField(noteC, t('notes'), Icons.note),
      ])),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t('cancel'), style: const TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: saving ? null : () async {
            if (nameC.text.trim().isEmpty) return;
            setD(() => saving = true);
            try {
              await ref.read(customerProvider.notifier).createCustomer(
                name: nameC.text.trim(),
                contactName: contactC.text.trim(),
                contactPhone: phoneC.text.trim(),
                contactEmail: emailC.text.trim(),
                address: addrC.text.trim(),
                packageQty: int.tryParse(pkgC.text) ?? 1,
                notes: noteC.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              await _load();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(t('saveSuccess')),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ));
              }
            } catch (e) {
              setD(() => saving = false);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text(e.toString()),
                  backgroundColor: AppColors.error,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ));
              }
            }
          },
          child: saving
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(t('save'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ],
    )));
  }

  Widget _dialogField(TextEditingController c, String label, IconData icon, {TextInputType? type}) => TextField(
    controller: c,
    keyboardType: type,
    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      prefixIcon: Icon(icon, color: AppColors.primary, size: 18),
      filled: true,
      fillColor: AppColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
    ),
  );

  // ═══════════════════════════════════════════════
  //  Drawer Menu
  // ═══════════════════════════════════════════════

  void _showDrawer(BuildContext ctx, String Function(String) t, AuthState auth, dynamic user) {
    final canManage = user?.isAdmin == true || user?.isManager == true;
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.cardBorder, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            // User info
            Row(children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: Text(
                    user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'A',
                    style: const TextStyle(color: AppColors.primary, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  user?.name ?? '',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  user?.email ?? '',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ])),
            ]),
            const SizedBox(height: 16),
            const Divider(color: AppColors.cardBorder),
            // Menu items
            _menuItem(Icons.settings_outlined, t('settings'), () { Navigator.pop(ctx); context.push('/settings'); }),
            if (canManage)
              _menuItem(Icons.business_outlined, t('customersMenu'), () { Navigator.pop(ctx); context.push('/customers'); }),
            _menuItem(Icons.history_outlined, t('serviceLogMenu'), () { Navigator.pop(ctx); context.push('/service-log'); }),
            if (canManage)
              _menuItem(Icons.people_outline, t('userManagement'), () { Navigator.pop(ctx); context.push('/user-management'); }),
            if (canManage)
              _menuItem(Icons.bar_chart_outlined, t('stats'), () { Navigator.pop(ctx); context.push('/stats'); }),
            // (v6.0) Removed: OTA (placeholder; backend lacks OTA support)
            //                 Group control (local-SharedPreferences only)
            const SizedBox(height: 12),
            // Logout
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await ref.read(authProvider.notifier).logout();
                  if (mounted) context.go('/login');
                },
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: Text(t('logout')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.errorBg,
                  foregroundColor: AppColors.error,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String title, VoidCallback onTap) => ListTile(
    leading: Icon(icon, color: AppColors.primary, size: 22),
    title: Text(
      title,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary.withValues(alpha: 0.4), size: 20),
    dense: true,
    onTap: onTap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}
