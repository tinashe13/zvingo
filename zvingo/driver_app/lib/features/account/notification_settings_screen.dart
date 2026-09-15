import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/widgets.dart';

/// The driver's notification preferences, wired to the real backend.
///
/// Contract (`backend/app/notification/`, added by agent B3):
///
/// * `GET /notification/preferences` → the caller's settings, or permissive
///   defaults when they have never customised them.
/// * `PUT /notification/preferences` → partial update; only the fields sent
///   are changed, and the stored result comes back.
/// * `GET /notification/push/status` → whether push delivery is actually
///   configured on this deployment.
///
/// That last endpoint is why this screen is honest rather than decorative.
/// Push is **not** wired end to end (cross-team finding X6: the driver app has
/// no `firebase_messaging` dependency, so `POST /auth/fcm-token` is never
/// called and `fcm_token` is always null). A toggle labelled "Push
/// notifications" with nothing behind it is exactly the kind of dead control
/// this rebuild exists to remove — so the screen reads the real server status,
/// states plainly that this build cannot receive push, and explains how
/// offers actually reach the driver today.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  Map<String, dynamic> _prefs = const {};
  bool _loading = true;
  Object? _error;
  final Set<String> _saving = {};

  /// Whether the server can deliver push at all, and why not when it cannot.
  bool? _pushAvailable;
  String _pushReason = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    final session = ref.read(authSessionProvider);
    try {
      final response =
          await session.send(() => api.get('/notification/preferences'));
      final data = response.data;
      if (!mounted) return;
      setState(() {
        _prefs = data is Map ? Map<String, dynamic>.from(data) : const {};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      return;
    }

    // Diagnostic, not load-bearing: a failure here just leaves the banner off.
    try {
      final status =
          await session.send(() => api.get('/notification/push/status'));
      final data = status.data;
      if (!mounted || data is! Map) return;
      setState(() {
        _pushAvailable = data['available'] as bool?;
        _pushReason = (data['reason'] as String?) ?? '';
      });
    } catch (_) {
      // Leave `_pushAvailable` null — we simply do not know.
    }
  }

  bool _value(String key, {bool fallback = true}) =>
      _prefs[key] as bool? ?? fallback;

  String? _time(String key) {
    final value = _prefs[key];
    return (value is String && value.isNotEmpty) ? value : null;
  }

  /// Optimistic toggle: flip it locally, `PUT` the single field, roll back and
  /// explain if the server refuses.
  Future<void> _set(String key, Object? value) async {
    final previous = _prefs[key];
    setState(() {
      _prefs = {..._prefs, key: value};
      _saving.add(key);
    });

    try {
      final response = await ref.read(authSessionProvider).send(
            () => ref
                .read(apiClientProvider)
                .put('/notification/preferences', data: {key: value}),
          );
      final data = response.data;
      if (!mounted) return;
      setState(() {
        if (data is Map) _prefs = Map<String, dynamic>.from(data);
        _saving.remove(key);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _prefs = {..._prefs, key: previous};
        _saving.remove(key);
      });
      DriverSnack.error(
        context,
        e is DioException && e.response?.statusCode == 503
            ? 'Notification settings are temporarily unavailable.'
            : 'That setting did not save. Check your connection.',
        onRetry: () => _set(key, value),
      );
    }
  }

  Future<void> _pickQuietHours() async {
    final start = await showTimePicker(
      context: context,
      helpText: 'Quiet hours start',
      initialTime: _parseTime(_time('quiet_hours_start')) ??
          const TimeOfDay(hour: 22, minute: 0),
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      helpText: 'Quiet hours end',
      initialTime: _parseTime(_time('quiet_hours_end')) ??
          const TimeOfDay(hour: 6, minute: 0),
    );
    if (end == null) return;
    await _set('quiet_hours_start', _formatTime(start));
    await _set('quiet_hours_end', _formatTime(end));
  }

  Future<void> _clearQuietHours() async {
    await _set('quiet_hours_start', null);
    await _set('quiet_hours_end', null);
  }

  static TimeOfDay? _parseTime(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final padding = AppSpacing.screenPaddingOf(context);

    return Scaffold(
      appBar: const DriverAppBar(
        title: 'Notifications',
        subtitle: 'What Zvingo may interrupt you for',
        fallbackRoute: '/account',
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? _skeleton(padding)
            : _error != null
                ? ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: padding,
                      vertical: AppSpacing.xxl,
                    ),
                    children: [
                      DriverErrorState(
                        title: 'Could not load your settings',
                        message:
                            'We could not reach your notification settings. '
                            'Check your connection and try again.',
                        onRetry: _load,
                      ),
                    ],
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _body(context, padding),
                  ),
      ),
    );
  }

  Widget _body(BuildContext context, double padding) {
    final quietStart = _time('quiet_hours_start');
    final quietEnd = _time('quiet_hours_end');

    return ListView(
      padding: EdgeInsets.fromLTRB(
        padding,
        AppSpacing.lg,
        padding,
        AppSpacing.section,
      ),
      children: [
        StaggeredEntrance(index: 0, child: _DeliveryRealityNotice(
          pushAvailable: _pushAvailable,
          reason: _pushReason,
        )),
        Gap.section,
        const StaggeredEntrance(
          index: 1,
          child: _GroupTitle('Channels'),
        ),
        Gap.md,
        StaggeredEntrance(
          index: 2,
          child: _SettingCard(
            children: [
              _SwitchRow(
                icon: Icons.notifications_active_outlined,
                title: 'Push notifications',
                subtitle:
                    'Alerts on your phone, even when Zvingo is in the background.',
                value: _value('push_enabled'),
                busy: _saving.contains('push_enabled'),
                onChanged: (v) => _set('push_enabled', v),
              ),
              _SwitchRow(
                icon: Icons.sms_outlined,
                title: 'SMS',
                subtitle:
                    'Text messages. These still arrive with no data connection.',
                value: _value('sms_enabled'),
                busy: _saving.contains('sms_enabled'),
                onChanged: (v) => _set('sms_enabled', v),
              ),
            ],
          ),
        ),
        Gap.section,
        const StaggeredEntrance(index: 3, child: _GroupTitle('What to tell you about')),
        Gap.md,
        StaggeredEntrance(
          index: 4,
          child: _SettingCard(
            children: [
              _SwitchRow(
                icon: Icons.local_shipping_outlined,
                title: 'Delivery offers',
                subtitle: 'New jobs while you are online. This is your income.',
                value: _value('driver_offers'),
                busy: _saving.contains('driver_offers'),
                onChanged: (v) => _set('driver_offers', v),
                warnWhenOff:
                    'With this off you will not be told about new offers.',
              ),
              _SwitchRow(
                icon: Icons.route_outlined,
                title: 'Order updates',
                subtitle:
                    'Changes to a delivery you are on — cancellations, '
                    'address changes.',
                value: _value('order_updates'),
                busy: _saving.contains('order_updates'),
                onChanged: (v) => _set('order_updates', v),
              ),
              _SwitchRow(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Messages',
                subtitle: 'Customers and merchants messaging you about a job.',
                value: _value('chat_messages'),
                busy: _saving.contains('chat_messages'),
                onChanged: (v) => _set('chat_messages', v),
              ),
              _SwitchRow(
                icon: Icons.campaign_outlined,
                title: 'Promotions and news',
                subtitle: 'Bonuses, incentives and Zvingo announcements.',
                value: _value('promotions'),
                busy: _saving.contains('promotions'),
                onChanged: (v) => _set('promotions', v),
              ),
            ],
          ),
        ),
        Gap.section,
        const StaggeredEntrance(index: 5, child: _GroupTitle('Quiet hours')),
        Gap.md,
        StaggeredEntrance(
          index: 6,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: AppSpacing.cardDecoration(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bedtime_outlined,
                        size: 20, color: AppColors.textSecondary),
                    Gap.hSm,
                    Expanded(
                      child: Text(
                        quietStart != null && quietEnd != null
                            ? '$quietStart – $quietEnd'
                            : 'Not set',
                        style: AppTextStyles.bodyStrong
                            .copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
                Gap.sm,
                Text(
                  'Promotions and messages are held during these hours. '
                  'Delivery offers and order updates always come through '
                  '— those are the ones that cost you money to miss.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
                Gap.lg,
                Row(
                  children: [
                    Expanded(
                      child: DriverSecondaryButton(
                        label: quietStart == null ? 'Set hours' : 'Change',
                        icon: Icons.schedule_rounded,
                        onPressed: _pickQuietHours,
                      ),
                    ),
                    if (quietStart != null) ...[
                      Gap.hSm,
                      Expanded(
                        child: DriverTextButton(
                          label: 'Clear',
                          expanded: true,
                          onPressed: _clearQuietHours,
                        ),
                      ),
                    ],
                  ],
                ),
                if (_prefs['timezone'] is String) ...[
                  Gap.md,
                  Text(
                    'Times are ${_prefs['timezone']}.',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _skeleton(double padding) {
    return ListView(
      padding: EdgeInsets.fromLTRB(padding, AppSpacing.lg, padding, padding),
      children: const [
        SkeletonBox(height: 96),
        Gap.section,
        SkeletonBox(height: 160),
        Gap.section,
        SkeletonBox(height: 280),
      ],
    );
  }
}

/// Tells the driver how alerts actually reach them on this build.
class _DeliveryRealityNotice extends StatelessWidget {
  final bool? pushAvailable;
  final String reason;

  const _DeliveryRealityNotice({
    required this.pushAvailable,
    required this.reason,
  });

  @override
  Widget build(BuildContext context) {
    // The client half of push does not exist in this app (finding X6), so even
    // a server that *can* send push has nothing to send to. Saying so is the
    // difference between a setting and a promise we cannot keep.
    final serverReady = pushAvailable == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.infoSurfaceOf(context),
        borderRadius: AppSpacing.brLg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 20, color: AppColors.infoOf(context)),
          Gap.hMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How offers reach you today',
                  style: AppTextStyles.bodyStrong
                      .copyWith(color: AppColors.infoOf(context)),
                ),
                Gap.xs,
                Text(
                  'This version of the Zvingo Driver app receives offers while '
                  'it is open, over a live connection. Phone push notifications '
                  'are not switched on yet, so keep the app in the foreground '
                  'while you are online.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
                if (!serverReady && reason.isNotEmpty) ...[
                  Gap.xs,
                  Text(
                    'Server status: $reason',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
                Gap.sm,
                Text(
                  'The settings below are saved to your account now, so they '
                  'apply the moment push is switched on.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  final String text;

  const _GroupTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.overline.copyWith(color: AppColors.textSecondary),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppSpacing.cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: AppSpacing.huge,
                color: AppColors.borderOf(context),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool busy;
  final ValueChanged<bool> onChanged;

  /// Extra warning shown when the driver turns this one off.
  final String? warnWhenOff;

  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.busy,
    required this.onChanged,
    this.warnWhenOff,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Icon(icon, size: 20, color: AppColors.textSecondary),
          ),
          Gap.hMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyStrong
                      .copyWith(color: AppColors.textPrimary),
                ),
                Gap.xxs,
                Text(
                  subtitle,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                ),
                if (!value && warnWhenOff != null) ...[
                  Gap.sm,
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 14, color: AppColors.warningOf(context)),
                      Gap.hXs,
                      Expanded(
                        child: Text(
                          warnWhenOff!,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.warningOf(context)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Gap.hSm,
          SizedBox(
            width: 52,
            height: AppSpacing.minTouchTarget,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Switch(
                      value: value,
                      onChanged: onChanged,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
