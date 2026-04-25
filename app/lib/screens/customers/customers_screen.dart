import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';
import '../../providers/locale_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../models/customer_model.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  @override
  void initState() {
    super.initState();
    // Always refresh from backend when opening this screen so staff see
    // the current list (not a stale cache from another device).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customerProvider.notifier).refresh();
    });
  }

  Future<void> _load() => ref.read(customerProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    final user = ref.watch(authProvider).user;
    final canManage = user?.isAdmin == true || user?.isManager == true;
    final custState = ref.watch(customerProvider);
    final customers = custState.customers;
    final loading = custState.isLoading && customers.isEmpty;
    final error = custState.error;
    String t(String key) => AppStrings.get(key, lang);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.pop()),
        title: Text(t('customersTitle'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)), centerTitle: true,
        actions: [
          if (canManage) IconButton(icon: const Icon(Icons.add, color: AppColors.primary), onPressed: () => _showAddDialog(t)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : (error != null && customers.isEmpty)
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.error_outline, size: 60, color: AppColors.error), const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _load, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary), child: Text(t('retry'))),
                ]))
              : customers.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                        const SizedBox(height: 120),
                        const Icon(Icons.business, size: 80, color: Colors.grey),
                        const SizedBox(height: 16),
                        Center(child: Text(t('noCustomers'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500))),
                      ]),
                    )
                  : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                      padding: const EdgeInsets.all(16), itemCount: customers.length,
                      itemBuilder: (_, i) => _card(customers[i], t, canManage),
                    )),
    );
  }

  Widget _card(CustomerModel c, String Function(String) t, bool canManage) {
    return Card(
      color: AppColors.cardBackground, margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3))),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.business, color: AppColors.primary),
        ),
        title: Text(c.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (c.contactName.isNotEmpty) Text('${t('contact')}: ${c.contactName}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Row(children: [
            Text('${c.deviceCount} ${t('devices')}', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
            if (c.packageQty > 0) Text('  /  ${c.packageQty} ${t('packageQty')}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
        ]),
        trailing: canManage ? PopupMenuButton(
          icon: const Icon(Icons.more_vert, color: Colors.grey), color: AppColors.cardBackground,
          itemBuilder: (_) => [
            PopupMenuItem(child: Text(t('editCustomer'), style: const TextStyle(color: Colors.white)),
              onTap: () => Future.delayed(Duration.zero, () => _showEditDialog(c, t))),
            PopupMenuItem(child: Text(t('delete'), style: const TextStyle(color: AppColors.error)),
              onTap: () => Future.delayed(Duration.zero, () => _confirmDelete(c, t))),
          ],
        ) : null,
        onTap: () => _showDetail(c, t),
      ),
    );
  }

  void _showDetail(CustomerModel c, String Function(String) t) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.cardBackground,
      title: Text(c.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (c.contactName.isNotEmpty) _infoRow(Icons.person, t('contact'), c.contactName),
        if (c.contactPhone.isNotEmpty) _infoRow(Icons.phone, t('phone'), c.contactPhone),
        if (c.contactEmail.isNotEmpty) _infoRow(Icons.email, t('email'), c.contactEmail),
        if (c.address.isNotEmpty) _infoRow(Icons.location_on, t('address'), c.address),
        if (c.packageQty > 0) _infoRow(Icons.router, t('packageQty'), '${c.packageQty}'),
        if (c.notes.isNotEmpty) _infoRow(Icons.note, t('notes'), c.notes),
        const Divider(color: Colors.grey, height: 24),
        _infoRow(Icons.router, t('devices'), '${c.deviceCount} ${t('machines')}'),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('close'), style: const TextStyle(color: AppColors.primary)))],
    ));
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: AppColors.primary, size: 18), const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
      ])),
    ]));
  }

  void _showAddDialog(String Function(String) t) {
    final nameC = TextEditingController();
    final contactC = TextEditingController();
    final phoneC = TextEditingController();
    final emailC = TextEditingController();
    final addrC = TextEditingController();
    final noteC = TextEditingController();
    final pkgC = TextEditingController(text: '1');

    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.cardBackground,
      title: Text(t('addCustomer'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _field(nameC, t('customerName'), Icons.business),
        const SizedBox(height: 10), _field(contactC, t('contact'), Icons.person),
        const SizedBox(height: 10), _field(phoneC, t('phone'), Icons.phone, type: TextInputType.phone),
        const SizedBox(height: 10), _field(emailC, t('email'), Icons.email, type: TextInputType.emailAddress),
        const SizedBox(height: 10), _field(addrC, t('address'), Icons.location_on),
        const SizedBox(height: 10), _field(pkgC, t('packageQty'), Icons.router, type: TextInputType.number),
        const SizedBox(height: 10), _field(noteC, t('notes'), Icons.note),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: const TextStyle(color: Colors.grey))),
        TextButton(onPressed: () async {
          if (nameC.text.trim().isEmpty) return;
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
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(t('saveSuccess')),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
              ));
            }
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(e.toString()),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 6),
              ));
            }
          }
        }, child: Text(t('create'), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600))),
      ],
    ));
  }

  void _showEditDialog(CustomerModel c, String Function(String) t) {
    final nameC = TextEditingController(text: c.name);
    final contactC = TextEditingController(text: c.contactName);
    final phoneC = TextEditingController(text: c.contactPhone);
    final emailC = TextEditingController(text: c.contactEmail);
    final addrC = TextEditingController(text: c.address);
    final noteC = TextEditingController(text: c.notes);
    final pkgC = TextEditingController(text: c.packageQty.toString());

    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.cardBackground,
      title: Text(t('editCustomer'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _field(nameC, t('customerName'), Icons.business),
        const SizedBox(height: 10), _field(contactC, t('contact'), Icons.person),
        const SizedBox(height: 10), _field(phoneC, t('phone'), Icons.phone),
        const SizedBox(height: 10), _field(emailC, t('email'), Icons.email),
        const SizedBox(height: 10), _field(addrC, t('address'), Icons.location_on),
        const SizedBox(height: 10), _field(pkgC, t('packageQty'), Icons.router, type: TextInputType.number),
        const SizedBox(height: 10), _field(noteC, t('notes'), Icons.note),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: const TextStyle(color: Colors.grey))),
        TextButton(onPressed: () async {
          try {
            await ref.read(customerProvider.notifier).updateCustomer(
              c.id,
              name: nameC.text.trim(),
              contactName: contactC.text.trim(),
              contactPhone: phoneC.text.trim(),
              contactEmail: emailC.text.trim(),
              address: addrC.text.trim(),
              packageQty: int.tryParse(pkgC.text) ?? c.packageQty,
              notes: noteC.text.trim(),
            );
            if (ctx.mounted) Navigator.pop(ctx);
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(e.toString()),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 6),
              ));
            }
          }
        }, child: Text(t('save'), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600))),
      ],
    ));
  }

  void _confirmDelete(CustomerModel c, String Function(String) t) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.cardBackground,
      title: Text(t('deleteCustomer'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      content: Text('${t('deleteCustomerConfirm')}\n\n${c.name}', style: const TextStyle(color: Colors.grey)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: const TextStyle(color: Colors.grey))),
        TextButton(onPressed: () async {
          try {
            await ref.read(customerProvider.notifier).deleteCustomer(c.id);
            if (ctx.mounted) Navigator.pop(ctx);
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(e.toString()),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 6),
              ));
            }
          }
        }, child: Text(t('delete'), style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600))),
      ],
    ));
  }

  Widget _field(TextEditingController c, String label, IconData icon, {TextInputType? type}) => TextField(
    controller: c, keyboardType: type, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
    decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.grey), prefixIcon: Icon(icon, color: Colors.grey, size: 20), isDense: true,
      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)), focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.primary))));
}
