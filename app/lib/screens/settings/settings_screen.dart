// lib/screens/settings/settings_screen.dart — v5.2.1 (Apr 2026)
// ─────────────────────────────────────────────────────────────
// Removed:
//   • "Change password" tile and dialog. Policy is that only
//     Admin / Manager can reset passwords via the user-management
//     flow (see UserManagementScreen). Self-service password change
//     is not supported anywhere in this app anymore.
//   • The "Notifications" section (enableNotifications /
//     lowLevelAlert / deviceOfflineAlert / maintenanceAlert).
//     Those toggles only flipped local widget state — they did not
//     persist, they did not alter backend subscription, and there
//     was no push channel to mute. Fake UI.
// Kept / improved:
//   • App version is now read from package_info_plus so it reflects
//     the real build (was a hardcoded '1.0.0' string).
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = '${info.version}+${info.buildNumber}');
      }
    } catch (_) {
      // If the platform channel fails, show nothing rather than a
      // misleading placeholder.
      if (mounted) setState(() => _version = '-');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final lang = ref.watch(localeProvider).languageCode;
    String t(String k) => AppStrings.get(k, lang);

    return Scaffold(
      backgroundColor: AppColors.bodyBg,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24))),
          child: SafeArea(bottom: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Row(children: [
              GestureDetector(onTap: () => context.pop(),
                child: Container(width: 34, height: 34, decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.cardBorder)),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 16))),
              const SizedBox(width: 10),
              Text(t('settings'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
          )),
        ),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(children: [
          // Profile card
          Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.cardWhite, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.borderLight)),
            child: Row(children: [
              Container(width: 52, height: 52, decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(14)),
                child: Center(child: Text(user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'A',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary)))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.name ?? '', style: const TextStyle(color: AppColors.textDark, fontSize: 16, fontWeight: FontWeight.w700)),
                Text(user?.email ?? '', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 4),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
                  child: Text(user?.isAdmin == true ? t('admin') : user?.isManager == true ? t('manager') : t('technician'),
                    style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w600))),
              ])),
            ])),
          const SizedBox(height: 20),
          _section(t('account')),
          _tile(Icons.person_outline_rounded, t('personalInfo'), onTap: () => _showProfile(t)),
          const SizedBox(height: 16),
          _section(t('language')),
          _tile(Icons.language_rounded, t('selectLanguage'),
            subtitle: lang == 'th' ? t('thai') : t('english'),
            onTap: () => _showLanguage(t)),
          const SizedBox(height: 16),
          _section(t('about')),
          _tile(Icons.info_outline_rounded, t('version'), subtitle: _version),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: () => _logout(t),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: Text(t('logout'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorBg, foregroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), minimumSize: const Size(double.infinity, 52), elevation: 0),
          )),
          const SizedBox(height: 20),
        ]))),
      ]),
    );
  }

  Widget _section(String title) => Padding(padding: const EdgeInsets.only(bottom: 8), child:
    Text(title, style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700)));

  Widget _tile(IconData icon, String title, {String? subtitle, VoidCallback? onTap}) =>
    Container(margin: const EdgeInsets.only(bottom: 6), decoration: BoxDecoration(color: AppColors.cardWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.borderLight)),
      child: ListTile(leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.primary, size: 20)),
        title: Text(title, style: const TextStyle(color: AppColors.textDark, fontSize: 14)),
        subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)) : null,
        trailing: onTap != null ? Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary.withValues(alpha: 0.4), size: 20) : null,
        onTap: onTap, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));

  void _showProfile(String Function(String) t) {
    final user = ref.read(authProvider).user;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.cardBackground, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(t('personalInfo'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _infoRow(Icons.person_outline_rounded, t('name'), user?.name ?? '-'),
        const Divider(color: AppColors.cardBorder, height: 20),
        _infoRow(Icons.email_outlined, t('email'), user?.email ?? '-'),
        const Divider(color: AppColors.cardBorder, height: 20),
        _infoRow(Icons.badge_outlined, t('role'), user?.isAdmin == true ? t('admin') : user?.isManager == true ? t('manager') : t('technician')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('close'), style: const TextStyle(color: AppColors.primary)))],
    ));
  }

  Widget _infoRow(IconData icon, String label, String value) => Row(children: [
    Icon(icon, color: AppColors.textSecondary, size: 18),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
    ])),
  ]);

  void _showLanguage(String Function(String) t) {
    showDialog(context: context, builder: (ctx) => Consumer(builder: (_, ref, __) {
      final cur = ref.watch(localeProvider);
      return AlertDialog(
        backgroundColor: AppColors.cardBackground, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('\u0e20\u0e32\u0e29\u0e32 / Language', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _langOpt(ctx, ref, '\u{1F1F9}\u{1F1ED}  \u0e20\u0e32\u0e29\u0e32\u0e44\u0e17\u0e22', const Locale('th'), cur.languageCode == 'th'),
          const SizedBox(height: 10),
          _langOpt(ctx, ref, '\u{1F1EC}\u{1F1E7}  English', const Locale('en'), cur.languageCode == 'en'),
        ]),
      );
    }));
  }

  Widget _langOpt(BuildContext ctx, WidgetRef ref, String label, Locale locale, bool sel) =>
    GestureDetector(
      onTap: () { Navigator.pop(ctx); ref.read(localeProvider.notifier).setLocale(locale); },
      child: Container(padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: sel ? AppColors.primaryLight : AppColors.surface, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? AppColors.primary : AppColors.cardBorder, width: sel ? 1.5 : 1)),
        child: Row(children: [
          Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: sel ? AppColors.primary : AppColors.textSecondary, size: 20),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: sel ? AppColors.primary : AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        ])),
    );

  Future<void> _logout(String Function(String) t) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.cardBackground, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(t('logout'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
      content: Text(t('logoutConfirm'), style: TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'), style: const TextStyle(color: AppColors.textSecondary))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () => Navigator.pop(ctx, true), child: Text(t('logout'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
      ],
    ));
    if (ok == true) { await ref.read(authProvider.notifier).logout(); if (mounted) context.go('/login'); }
  }
}
