import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_strings.dart';
import '../../providers/locale_provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/notification_model.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationProvider);
    final lang = ref.watch(localeProvider).languageCode;
    String t(String k) => AppStrings.get(k, lang);
    final notifs = state.notifications;
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
              Expanded(child: Text(t('notifications'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700))),
              if (notifs.isNotEmpty) PopupMenuButton(
                icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
                color: AppColors.cardBackground,
                itemBuilder: (_) => [
                  PopupMenuItem(child: Text(t('markAllRead'), style: const TextStyle(color: AppColors.textPrimary)), onTap: () => ref.read(notificationProvider.notifier).markAllAsRead()),
                  PopupMenuItem(child: Text(t('deleteAll'), style: const TextStyle(color: AppColors.error)), onTap: () => ref.read(notificationProvider.notifier).clearAll()),
                ],
              ),
            ]),
          )),
        ),
        Expanded(child: notifs.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 64, height: 64, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
                child: Icon(Icons.notifications_none_rounded, color: AppColors.primary.withValues(alpha: 0.4), size: 32)),
              const SizedBox(height: 16),
              Text(t('noNotifications'), style: const TextStyle(color: AppColors.textDark, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(t('youWillReceiveHere'), style: TextStyle(color: AppColors.textDark.withValues(alpha: 0.5), fontSize: 13)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(14), itemCount: notifs.length,
              itemBuilder: (_, i) => _card(context, ref, notifs[i], t),
            )),
      ]),
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, NotificationItem n, String Function(String) t) {
    final unread = !n.isRead;
    return Dismissible(
      key: Key(n.id), direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.delete_rounded, color: Colors.white)),
      onDismissed: (_) { ref.read(notificationProvider.notifier).clearNotification(n.id);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('notificationDeleted')), backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))); },
      child: GestureDetector(
        onTap: () {
          ref.read(notificationProvider.notifier).markAsRead(n.id);
          if (n.deviceId.isNotEmpty) context.push('/device/${n.deviceId}');
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: unread ? AppColors.cardWhite : AppColors.cardWhite.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: unread ? n.typeColor.withValues(alpha: 0.3) : AppColors.borderLight),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: n.typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(n.typeIcon, color: n.typeColor, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(n.title, style: TextStyle(color: AppColors.textDark, fontSize: 13, fontWeight: unread ? FontWeight.w700 : FontWeight.w500))),
                if (unread) Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
              ]),
              const SizedBox(height: 3),
              Text(n.message, style: TextStyle(color: AppColors.textDark.withValues(alpha: 0.6), fontSize: 12)),
              const SizedBox(height: 5),
              Row(children: [
                Text(_fmtTime(n.timestamp, t), style: TextStyle(color: AppColors.textDark.withValues(alpha: 0.4), fontSize: 10)),
                if (n.deviceId.isNotEmpty) ...[
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded, color: AppColors.textDark.withValues(alpha: 0.3), size: 16),
                ],
              ]),
            ])),
          ]),
        ),
      ),
    );
  }

  String _fmtTime(DateTime ts, String Function(String) t) {
    final d = DateTime.now().difference(ts);
    if (d.inMinutes < 1) return t('justNow');
    if (d.inHours < 1) return '${d.inMinutes} ${t('minutesAgo')}';
    if (d.inDays < 1) return '${d.inHours} ${t('hoursAgo')}';
    if (d.inDays < 7) return '${d.inDays} ${t('daysAgo')}';
    return DateFormat('dd/MM/yyyy HH:mm').format(ts);
  }
}
