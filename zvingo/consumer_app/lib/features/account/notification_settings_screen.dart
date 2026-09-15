import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/account/notification_settings_provider.dart';

/// What Zvingo may send, and when.
///
/// Wired to `GET`/`PUT /notification/preferences`, which agent B3 shipped. Each
/// switch sends only its own field, matching
/// `NotificationPreferenceUpdate`'s partial-update contract.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  static Future<void> push(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const NotificationSettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider);
    final pushConfigured = ref.watch(pushConfiguredProvider);

    return ZvScreen(
      title: 'Notifications',
      subtitle: 'Choose what Zvingo may send you',
      fallbackRoute: '/account',
      child: settings.when(
        loading: () => const ZvSkeletonList.tiles(count: 6),
        error: (error, _) => ZvErrorState(
          error: error,
          title: 'Notification settings are unavailable',
          onRetry: () => ref.invalidate(notificationSettingsProvider),
        ),
        data: (prefs) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          children: [
            if (pushConfigured.valueOrNull == false)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: const BoxDecoration(
                    color: AppColors.warningSurface,
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.notifications_off_outlined,
                          size: 20, color: AppColors.warning),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'Push notifications are switched off on Zvingo\'s '
                          'side right now, so you will get SMS updates instead. '
                          'Your choices below are still saved.',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.warning),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const ZvSectionHeader(
              title: 'How we reach you',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: AppSpacing.sm),
            _SettingSwitch(
              icon: Icons.notifications_active_outlined,
              title: 'Push notifications',
              subtitle: 'Alerts on this phone',
              value: prefs.pushEnabled,
              onChanged: (value) => _apply(
                context,
                ref,
                label: 'Push notifications',
                change: (p) => p.copyWith(pushEnabled: value),
                payload: {'push_enabled': value},
              ),
            ),
            _SettingSwitch(
              icon: Icons.sms_outlined,
              title: 'SMS',
              subtitle: 'Text messages, including when push is unavailable',
              value: prefs.smsEnabled,
              onChanged: (value) => _apply(
                context,
                ref,
                label: 'SMS',
                change: (p) => p.copyWith(smsEnabled: value),
                payload: {'sms_enabled': value},
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const ZvSectionHeader(
              title: 'What we send',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: AppSpacing.sm),
            _SettingSwitch(
              icon: Icons.local_shipping_outlined,
              title: 'Order updates',
              subtitle: 'Accepted, collected, arriving — always delivered, '
                  'even during quiet hours',
              value: prefs.orderUpdates,
              onChanged: (value) => _apply(
                context,
                ref,
                label: 'Order updates',
                change: (p) => p.copyWith(orderUpdates: value),
                payload: {'order_updates': value},
              ),
            ),
            _SettingSwitch(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Messages from your driver',
              subtitle: 'When a driver messages about your delivery',
              value: prefs.chatMessages,
              onChanged: (value) => _apply(
                context,
                ref,
                label: 'Driver messages',
                change: (p) => p.copyWith(chatMessages: value),
                payload: {'chat_messages': value},
              ),
            ),
            _SettingSwitch(
              icon: Icons.local_offer_outlined,
              title: 'Offers and promotions',
              subtitle: 'Deals from restaurants near you',
              value: prefs.promotions,
              onChanged: (value) => _apply(
                context,
                ref,
                label: 'Promotions',
                change: (p) => p.copyWith(promotions: value),
                payload: {'promotions': value},
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const ZvSectionHeader(
              title: 'Quiet hours',
              subtitle: 'Nothing but order updates during this window.',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: AppSpacing.sm),
            _QuietHoursCard(prefs: prefs),
          ],
        ),
      ),
    );
  }

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref, {
    required String label,
    required NotificationPreferences Function(NotificationPreferences) change,
    required Map<String, dynamic> payload,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(notificationSettingsProvider.notifier)
        .update(change, payload);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('$label could not be saved. Check your connection '
              'and try again.'),
        ),
      );
    }
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: ZvCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: value,
          onChanged: onChanged,
          secondary: Icon(icon, color: AppColors.textSecondary),
          title: Text(title, style: AppTextStyles.bodyStrong),
          subtitle: Text(
            subtitle,
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _QuietHoursCard extends ConsumerWidget {
  const _QuietHoursCard({required this.prefs});

  final NotificationPreferences prefs;

  static const String _defaultStart = '22:00';
  static const String _defaultEnd = '07:00';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = prefs.quietHoursOn;

    return ZvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: on,
            onChanged: (value) => _toggle(context, ref, value),
            secondary: const Icon(Icons.bedtime_outlined,
                color: AppColors.textSecondary),
            title: const Text('Quiet hours', style: AppTextStyles.bodyStrong),
            subtitle: Text(
              on
                  ? 'Silent from ${prefs.quietHoursStart} to '
                      '${prefs.quietHoursEnd}'
                  : 'Off — we may message you at any hour',
              style: AppTextStyles.tabular(AppTextStyles.caption)
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          if (on) ...[
            const Divider(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _TimeButton(
                    label: 'From',
                    time: prefs.quietHoursStart ?? _defaultStart,
                    onPick: (value) => _setWindow(
                      context,
                      ref,
                      start: value,
                      end: prefs.quietHoursEnd ?? _defaultEnd,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _TimeButton(
                    label: 'Until',
                    time: prefs.quietHoursEnd ?? _defaultEnd,
                    onPick: (value) => _setWindow(
                      context,
                      ref,
                      start: prefs.quietHoursStart ?? _defaultStart,
                      end: value,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Order updates still come through — you should always know where '
              'your food is.',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool on) async {
    if (on) {
      await _setWindow(context, ref, start: _defaultStart, end: _defaultEnd);
      return;
    }
    await ref.read(notificationSettingsProvider.notifier).update(
          (p) => p.copyWith(clearQuietHours: true),
          {'quiet_hours_start': null, 'quiet_hours_end': null},
        );
  }

  Future<void> _setWindow(
    BuildContext context,
    WidgetRef ref, {
    required String start,
    required String end,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(notificationSettingsProvider.notifier).update(
          (p) => p.copyWith(quietHoursStart: start, quietHoursEnd: end),
          {'quiet_hours_start': start, 'quiet_hours_end': end},
        );
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Quiet hours could not be saved. Try again.'),
        ),
      );
    }
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.time,
    required this.onPick,
  });

  final String label;
  final String time;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return ZvButton.secondary(
      label: '$label  $time',
      icon: Icons.schedule_rounded,
      onPressed: () async {
        final parts = time.split(':');
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(
            hour: int.tryParse(parts.first) ?? 22,
            minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
          ),
          helpText: 'Quiet hours $label'.toUpperCase(),
        );
        if (picked == null) return;
        onPick('${picked.hour.toString().padLeft(2, '0')}:'
            '${picked.minute.toString().padLeft(2, '0')}');
      },
    );
  }
}
