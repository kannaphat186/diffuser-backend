import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';
import '../../providers/locale_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/service_log_model.dart';
import '../../services/service_log_service.dart';
import '../../services/pdf_export_service.dart';
import 'package:intl/intl.dart';

class ServiceLogScreen extends ConsumerStatefulWidget {
  const ServiceLogScreen({super.key});
  @override
  ConsumerState<ServiceLogScreen> createState() => _ServiceLogScreenState();
}

class _ServiceLogScreenState extends ConsumerState<ServiceLogScreen> {
  final _svc = ServiceLogService();
  List<ServiceLogModel> _logs = [];
  bool _loading = true;
  String _filterType = 'all'; // ★ NEW: filter by type

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { _logs = await _svc.getLogs(); } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ★ NEW: Filtered logs
  List<ServiceLogModel> get _filteredLogs {
    if (_filterType == 'all') return _logs;
    return _logs.where((l) => l.type == _filterType).toList();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    final user = ref.watch(authProvider).user;
    String t(String key) => AppStrings.get(key, lang);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.pop()),
        title: Text(t('serviceLogTitle'), style: const TextStyle(color: Colors.white, fontSize: 18)), centerTitle: true,
        actions: [
          if (user?.canManageDevices ?? false)
            IconButton(icon: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.primary), onPressed: () => _exportPDF(t)),
        ],
      ),
      // ★ REMOVED: FloatingActionButton
      body: Column(children: [
        // ★ NEW: Filter tabs
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _filterChip(lang == 'th' ? 'ทั้งหมด' : 'All', 'all'),
              const SizedBox(width: 6),
              _filterChip(t('refill'), 'refill'),
              const SizedBox(width: 6),
              _filterChip(t('repair'), 'repair'),
              const SizedBox(width: 6),
              _filterChip(t('inspection'), 'inspection'),
              const SizedBox(width: 6),
              _filterChip(t('installation'), 'installation'),
            ]),
          ),
        ),
        // ★ NEW: Hint text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            lang == 'th'
                ? 'หากต้องการเพิ่มบันทึกเซอร์วิส กรุณาไปที่หน้าเครื่องนั้นๆ'
                : 'To add a service log, go to the device detail page',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ),
        // Body
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _filteredLogs.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withValues(alpha: 0.1)),
                        child: Icon(Icons.history, size: 50, color: AppColors.primary.withValues(alpha: 0.5))),
                      const SizedBox(height: 20),
                      Text(t('noServiceLogs'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
                    ]))
                  : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                      padding: const EdgeInsets.all(16), itemCount: _filteredLogs.length,
                      itemBuilder: (c, i) => _logCard(_filteredLogs[i], t, lang),
                    )),
        ),
      ]),
    );
  }

  // ★ NEW: Filter chip widget
  Widget _filterChip(String label, String type) {
    final selected = _filterType == type;
    return GestureDetector(
      onTap: () => setState(() => _filterType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primary : AppColors.cardBorder),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? Colors.white : AppColors.textSecondary,
          fontSize: 12, fontWeight: FontWeight.w600,
        )),
      ),
    );
  }

  Widget _logCard(ServiceLogModel log, String Function(String) t, String lang) {
    final typeLabel = lang == 'th' ? log.typeDisplayTh : log.typeDisplayEn;
    final typeColor = _typeColor(log.type);
    return Card(
      color: AppColors.cardBackground, margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: typeColor.withValues(alpha: 0.2))),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(typeLabel, style: TextStyle(color: typeColor, fontSize: 12, fontWeight: FontWeight.w600))),
          const Spacer(),
          Text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(log.createdAt)), style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
        ]),
        const SizedBox(height: 12),
        if (log.description.isNotEmpty) Text(log.description, style: const TextStyle(color: Colors.white, fontSize: 14)),
        if (log.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(log.notes, style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontStyle: FontStyle.italic))),
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _infoChip(Icons.router_outlined, '${log.deviceName} (${log.deviceSerial})'),
          if (log.customerName.isNotEmpty) _infoChip(Icons.business_outlined, log.customerName),
          _infoChip(Icons.person_outline, log.technicianName),
          if (log.photos.isNotEmpty) _infoChip(Icons.photo_outlined, '${log.photos.length} ${t('photos')}'),
        ]),
      ])),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.grey.shade600, size: 14), const SizedBox(width: 4),
      Flexible(child: Text(text, style: TextStyle(color: Colors.grey.shade500, fontSize: 12), overflow: TextOverflow.ellipsis)),
    ]);
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'refill': return AppColors.primary;
      case 'repair': return AppColors.error;
      case 'inspection': return AppColors.info;
      case 'installation': return AppColors.success;
      case 'uninstall': return AppColors.warning;
      default: return Colors.grey;
    }
  }

  Future<void> _exportPDF(String Function(String) t) async {
    if (_filteredLogs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('noServiceLogs')), backgroundColor: AppColors.warning),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t('exportPreparing')), backgroundColor: AppColors.primary),
    );

    try {
      await PdfExportService.exportAndShare(logs: _filteredLogs);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF export failed: $e'), backgroundColor: AppColors.error),
      );
    }
  }
}
