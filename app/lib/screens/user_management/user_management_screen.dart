import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../models/user_model.dart';
import '../../services/user_service.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});
  @override
  ConsumerState<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  final _userService = UserService();
  List<UserModel> _users = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() { super.initState(); _loadUsers(); }

  Future<void> _loadUsers() async {
    setState(() { _isLoading = true; _error = null; });
    try { _users = await _userService.getUsers(); } catch (e) { _error = e.toString(); }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
    String t(String key) => AppStrings.get(key, lang);
    final me = ref.watch(authProvider).user;
    final isAdmin = me?.isAdmin == true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.pop()),
        title: Text(t('userManagementTitle'), style: const TextStyle(color: Colors.white)), centerTitle: true,
        actions: [
          // Only admins can add/delete users. Managers can edit
          // (including reset passwords) — see _showEditDialog.
          if (isAdmin)
            IconButton(icon: const Icon(Icons.add, color: AppColors.primary), onPressed: () => _showAddDialog(t)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.error_outline, size: 60, color: AppColors.error), const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.grey)), const SizedBox(height: 16),
                  ElevatedButton(onPressed: _loadUsers, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary), child: Text(t('retry'))),
                ]))
              : RefreshIndicator(onRefresh: _loadUsers, child: ListView.builder(
                  padding: const EdgeInsets.all(16), itemCount: _users.length,
                  itemBuilder: (ctx, i) => _userCard(_users[i], t, isAdmin),
                )),
    );
  }

  Widget _userCard(UserModel user, String Function(String) t, bool isAdmin) {
    return Card(
      color: AppColors.cardBackground, margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.withValues(alpha: 0.3))),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: user.isAdmin || user.isManager ? AppColors.primary : Colors.grey.shade700,
          child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        title: Text(user.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user.email, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: (user.isAdmin || user.isManager ? AppColors.primary : Colors.grey).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
            child: Text(user.isAdmin ? t('admin') : user.isManager ? t('manager') : t('technician'), style: TextStyle(color: user.isAdmin || user.isManager ? AppColors.primary : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ]),
        trailing: PopupMenuButton(
          icon: const Icon(Icons.more_vert, color: Colors.grey), color: AppColors.cardBackground,
          itemBuilder: (c) => [
            PopupMenuItem(child: Text(t('editUser'), style: const TextStyle(color: Colors.white)), onTap: () => Future.delayed(Duration.zero, () => _showEditDialog(user, t))),
            // Delete is admin-only.
            if (isAdmin)
              PopupMenuItem(child: Text(t('deleteUser'), style: const TextStyle(color: AppColors.error)), onTap: () => Future.delayed(Duration.zero, () => _confirmDelete(user, t))),
          ],
        ),
      ),
    );
  }

  void _showAddDialog(String Function(String) t) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String role = 'technician';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      backgroundColor: AppColors.cardBackground,
      title: Text(t('addUser'), style: const TextStyle(color: Colors.white)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _field(nameCtrl, t('name'), Icons.person),
        const SizedBox(height: 12), _field(emailCtrl, t('email'), Icons.email, type: TextInputType.emailAddress),
        const SizedBox(height: 12), _field(passCtrl, t('password'), Icons.lock, obscure: true),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
          child: DropdownButtonHideUnderline(child: DropdownButton<String>(isExpanded: true, value: role, dropdownColor: AppColors.cardBackground, style: const TextStyle(color: Colors.white),
            items: [DropdownMenuItem(value: 'technician', child: Text(t('technician'))), DropdownMenuItem(value: 'manager', child: Text(t('manager'))), DropdownMenuItem(value: 'admin', child: Text(t('admin')))],
            onChanged: (v) => setD(() => role = v!)))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: const TextStyle(color: Colors.grey))),
        TextButton(onPressed: () async {
          if (nameCtrl.text.isEmpty || emailCtrl.text.isEmpty || passCtrl.text.isEmpty) { ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t('enterName')), backgroundColor: AppColors.error)); return; }
          try { await _userService.createUser(name: nameCtrl.text, email: emailCtrl.text, password: passCtrl.text, role: role); if (ctx.mounted) Navigator.pop(ctx); await _loadUsers(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('userAdded')), backgroundColor: AppColors.success));
          } catch (e) { if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error)); }
        }, child: Text(t('create'), style: const TextStyle(color: AppColors.primary))),
      ],
    )));
  }

  void _showEditDialog(UserModel user, String Function(String) t) {
    final nameCtrl = TextEditingController(text: user.name);
    final emailCtrl = TextEditingController(text: user.email);
    final passCtrl = TextEditingController();
    String role = user.role;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      backgroundColor: AppColors.cardBackground,
      title: Text(t('editUser'), style: const TextStyle(color: Colors.white)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _field(nameCtrl, t('name'), Icons.person),
        const SizedBox(height: 12), _field(emailCtrl, t('email'), Icons.email),
        const SizedBox(height: 12),
        // Reset-password field. Leaving this blank keeps the current
        // password; any value is sent to the backend and becomes the
        // new password. The backend enforces the min-length rule.
        _field(passCtrl, t('newPassword'), Icons.lock_reset, obscure: true),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
          child: DropdownButtonHideUnderline(child: DropdownButton<String>(isExpanded: true, value: role, dropdownColor: AppColors.cardBackground, style: const TextStyle(color: Colors.white),
            items: [DropdownMenuItem(value: 'technician', child: Text(t('technician'))), DropdownMenuItem(value: 'manager', child: Text(t('manager'))), DropdownMenuItem(value: 'admin', child: Text(t('admin')))],
            onChanged: (v) => setD(() => role = v!)))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: const TextStyle(color: Colors.grey))),
        TextButton(onPressed: () async {
          try {
            await _userService.updateUser(
              user.id,
              name: nameCtrl.text,
              email: emailCtrl.text,
              role: role,
              password: passCtrl.text.isEmpty ? null : passCtrl.text,
            );
            if (ctx.mounted) Navigator.pop(ctx);
            await _loadUsers();
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('userEdited')), backgroundColor: AppColors.success));
          } catch (e) { if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error)); }
        }, child: Text(t('save'), style: const TextStyle(color: AppColors.primary))),
      ],
    )));
  }

  void _confirmDelete(UserModel user, String Function(String) t) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.cardBackground,
      title: Text(t('deleteUser'), style: const TextStyle(color: Colors.white)),
      content: Text('${t('deleteUserConfirm')}\n\n${user.name} (${user.email})', style: const TextStyle(color: Colors.grey)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'), style: const TextStyle(color: Colors.grey))),
        TextButton(onPressed: () async {
          try { await _userService.deleteUser(user.id); if (ctx.mounted) Navigator.pop(ctx); await _loadUsers(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('userDeleted')), backgroundColor: AppColors.success));
          } catch (e) { if (ctx.mounted) { Navigator.pop(ctx); ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error)); } }
        }, child: Text(t('delete'), style: const TextStyle(color: AppColors.error))),
      ],
    ));
  }

  Widget _field(TextEditingController c, String label, IconData icon, {bool obscure = false, TextInputType? type}) {
    return TextField(controller: c, obscureText: obscure, keyboardType: type, style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.grey), prefixIcon: Icon(icon, color: Colors.grey),
        enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)), focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.primary))));
  }
}
