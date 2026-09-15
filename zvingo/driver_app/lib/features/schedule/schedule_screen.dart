import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/app_motion.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../providers/schedule_provider.dart';
import '../../widgets/widgets.dart';

/// Recurring weekly availability.
///
/// The defect this screen used to have was subtle and expensive: the toggles
/// were in-memory only, so a driver set their week, saw it highlighted, closed
/// the app, and came back to an empty grid — having told Zvingo nothing. The
/// grid now reflects what the **server** has, at all times:
///
/// * a tap applies instantly (optimistic) and persists shortly after;
/// * the header says plainly whether it is saved or still saving;
/// * a failed write rolls the grid back and offers a retry, so what is
///   highlighted is never a shift Zvingo does not know about.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(scheduleProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(scheduleProvider);
    final notifier = ref.read(scheduleProvider.notifier);
    final padding = AppSpacing.screenPaddingOf(context);

    ref.listen<ScheduleState>(scheduleProvider, (previous, next) {
      if (previous?.failure == null && next.failure != null) {
        DriverSnack.error(
          context,
          _failureMessage(next.failure!),
          onRetry: next.failure == ScheduleFailure.noSession
              ? null
              : notifier.retrySave,
        );
      }
    });

    return Scaffold(
      appBar: DriverAppBar(
        title: 'Your week',
        subtitle: _subtitle(schedule),
        showBack: false,
        actions: [
          if (!schedule.isEmpty)
            DriverIconButton(
              icon: Icons.layers_clear_outlined,
              tooltip: 'Clear the whole week',
              onPressed: () => _confirmClear(context, schedule, notifier),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: notifier.load,
          child: schedule.loading && schedule.selected.isEmpty
              ? _ScheduleSkeleton(padding: padding)
              : _grid(context, schedule, notifier, padding),
        ),
      ),
    );
  }

  String _subtitle(ScheduleState schedule) {
    if (schedule.loading) return 'Loading your shifts…';
    if (schedule.failure != null) return 'Not saved — tap retry';
    if (schedule.saving) return 'Saving…';
    if (schedule.isEmpty) return 'No shifts set';
    final hours = schedule.weeklyHours;
    final hourLabel = hours % 1 == 0
        ? '${hours.toInt()}h'
        : '${hours.toStringAsFixed(1)}h';
    return '${schedule.totalShifts} shifts · about $hourLabel a week';
  }

  Widget _grid(
    BuildContext context,
    ScheduleState schedule,
    ScheduleNotifier notifier,
    double padding,
  ) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        padding,
        AppSpacing.lg,
        padding,
        AppSpacing.section,
      ),
      children: [
        StaggeredEntrance(
          index: 0,
          child: _SaveStatusBar(schedule: schedule, notifier: notifier),
        ),
        Gap.md,
        StaggeredEntrance(
          index: 1,
          child: _TimezoneNote(schedule: schedule),
        ),
        if (schedule.isEmpty) ...[
          Gap.md,
          StaggeredEntrance(
            index: 2,
            child: _Presets(schedule: schedule, notifier: notifier),
          ),
        ],
        Gap.lg,
        for (var day = 0; day < 7; day++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: StaggeredEntrance(
              index: day + 3,
              child: _DayCard(
                dayIndex: day,
                schedule: schedule,
                onToggle: notifier.toggle,
              ),
            ),
          ),
        Gap.sm,
        Text(
          'This repeats every week. Zvingo uses it to plan how many drivers '
          'are needed — you can still go online outside these hours '
          'whenever you want.',
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  String _failureMessage(ScheduleFailure failure) {
    switch (failure) {
      case ScheduleFailure.network:
        return 'No connection, so your shift change was not saved.';
      case ScheduleFailure.rejected:
        return 'Zvingo could not accept that shift. Try a different slot.';
      case ScheduleFailure.noSession:
        return 'Your session ended. Sign in again to change your week.';
      case ScheduleFailure.unknown:
        return 'Your shift change was not saved. Tap retry.';
    }
  }

  Future<void> _confirmClear(
    BuildContext context,
    ScheduleState schedule,
    ScheduleNotifier notifier,
  ) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Clear your whole week?',
      consequence:
          'All ${schedule.totalShifts} shifts will be removed and Zvingo will '
          'plan as if you are not available. You can set them again any time.',
      confirmLabel: 'Clear the week',
      icon: Icons.layers_clear_outlined,
    );
    if (!confirmed) return;
    notifier.clearWeek();
    if (context.mounted) {
      DriverSnack.show(context, 'Week cleared', icon: Icons.check_rounded);
    }
  }
}

// ── Save status ─────────────────────────────────────────────────────────────

/// The proof that this screen persists. It is deliberately always visible
/// rather than a transient toast: a driver setting their week needs to know,
/// at a glance, whether Zvingo has it.
class _SaveStatusBar extends StatelessWidget {
  final ScheduleState schedule;
  final ScheduleNotifier notifier;

  const _SaveStatusBar({required this.schedule, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final (icon, tone, message) = _status(context);

    final color = switch (tone) {
      StatusTone.error => AppColors.errorOf(context),
      StatusTone.warning => AppColors.warningOf(context),
      StatusTone.success => AppColors.successOf(context),
      _ => AppColors.textSecondary,
    };
    final surface = switch (tone) {
      StatusTone.error => AppColors.errorSurfaceOf(context),
      StatusTone.warning => AppColors.warningSurfaceOf(context),
      StatusTone.success => AppColors.successSurfaceOf(context),
      _ => AppColors.surfaceMutedOf(context),
    };

    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.fast),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: AppSpacing.brMd,
      ),
      child: Row(
        children: [
          if (schedule.saving)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Icon(icon, size: 18, color: color),
          Gap.hMd,
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.caption.copyWith(color: color),
            ),
          ),
          if (schedule.failure != null &&
              schedule.failure != ScheduleFailure.noSession) ...[
            Gap.hSm,
            DriverTextButton(
              label: 'Retry',
              onPressed: notifier.retrySave,
            ),
          ],
        ],
      ),
    );
  }

  (IconData, StatusTone, String) _status(BuildContext context) {
    if (schedule.failure != null) {
      return (
        Icons.cloud_off_rounded,
        StatusTone.error,
        'Not saved. Your week is showing what Zvingo currently has.',
      );
    }
    if (schedule.saving) {
      return (Icons.sync_rounded, StatusTone.neutral, 'Saving your week…');
    }
    if (schedule.savedRecently) {
      return (
        Icons.cloud_done_rounded,
        StatusTone.success,
        'Saved. Zvingo has your week.',
      );
    }
    if (schedule.isEmpty) {
      return (
        Icons.event_available_outlined,
        StatusTone.neutral,
        'Tap the shifts you plan to work. Changes save on their own.',
      );
    }
    return (
      Icons.cloud_done_rounded,
      StatusTone.success,
      'Saved. Changes save on their own.',
    );
  }
}

/// Which clock these times are on.
///
/// The schedule is stored as Africa/Harare wall-clock (the server echoes the
/// zone on every read). A phone set to another zone would otherwise silently
/// read "6am" as its own 6am, which is a missed shift.
class _TimezoneNote extends StatelessWidget {
  final ScheduleState schedule;

  const _TimezoneNote({required this.schedule});

  @override
  Widget build(BuildContext context) {
    final differs = schedule.deviceClockDiffers;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: differs
            ? AppColors.warningSurfaceOf(context)
            : AppColors.surfaceMutedOf(context),
        borderRadius: AppSpacing.brMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            differs ? Icons.public_off_rounded : Icons.schedule_rounded,
            size: 16,
            color: differs
                ? AppColors.warningOf(context)
                : AppColors.textSecondary,
          ),
          Gap.hSm,
          Expanded(
            child: Text(
              differs
                  ? 'These times are ${schedule.timezone} (Zimbabwe). Your '
                      'phone is on ${schedule.deviceOffsetLabel}, so they will '
                      'not match your phone clock.'
                  : 'All times are ${schedule.timezone} — the same clock '
                      'your phone is on.',
              style: AppTextStyles.caption.copyWith(
                color: differs
                    ? AppColors.warningOf(context)
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fast ways in, for a driver staring at an empty grid.
class _Presets extends StatelessWidget {
  final ScheduleState schedule;
  final ScheduleNotifier notifier;

  const _Presets({required this.schedule, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final slotIds = schedule.slots.map((s) => s.id).toSet();

    Map<int, Set<int>> forDays(Iterable<int> days, Set<int> slots) => {
          for (final day in days) day: Set<int>.from(slots),
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick start',
          style: AppTextStyles.overline
              .copyWith(color: AppColors.textSecondary),
        ),
        Gap.sm,
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _PresetChip(
              label: 'Weekday evenings',
              onTap: () => notifier.applyPreset(
                forDays([0, 1, 2, 3, 4], {slotIds.contains(2) ? 2 : slotIds.last}),
              ),
            ),
            _PresetChip(
              label: 'Weekends, all day',
              onTap: () => notifier.applyPreset(forDays([5, 6], slotIds)),
            ),
            _PresetChip(
              label: 'Every day, all day',
              onTap: () => notifier.applyPreset(
                forDays([0, 1, 2, 3, 4, 5, 6], slotIds),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: TapScale(
        onTap: onTap,
        enforceMinTarget: false,
        child: Container(
          constraints:
              const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: AppSpacing.brFull,
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt_rounded,
                  size: 16, color: AppColors.textSecondary),
              Gap.hSm,
              Text(
                label,
                style: AppTextStyles.bodyStrong
                    .copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── The grid ────────────────────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  final int dayIndex;
  final ScheduleState schedule;
  final void Function(int day, int slot) onToggle;

  const _DayCard({
    required this.dayIndex,
    required this.schedule,
    required this.onToggle,
  });

  static const List<String> _longNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final selectedCount = schedule.selected[dayIndex]?.length ?? 0;
    final isToday = DateTime.now().weekday - 1 == dayIndex;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppSpacing.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _longNames[dayIndex],
                  style: AppTextStyles.onSurface(context, AppTextStyles.h3),
                ),
              ),
              if (isToday) ...[
                const StatusChip(label: 'Today', tone: StatusTone.info),
                Gap.hSm,
              ],
              Text(
                selectedCount == 0
                    ? 'Off'
                    : '$selectedCount ${selectedCount == 1 ? 'shift' : 'shifts'}',
                style: AppTextStyles.caption.copyWith(
                  color: selectedCount == 0
                      ? AppColors.textTertiary
                      : AppColors.successOf(context),
                ),
              ),
            ],
          ),
          Gap.md,
          // Wrap, not Row: at 320px and 200% text scale three fixed columns
          // overflow. Wrapping degrades to a stack instead of clipping.
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = schedule.slots.length;
              final gaps = AppSpacing.sm * (columns - 1);
              final available = constraints.maxWidth - gaps;
              final tileWidth = available / columns;
              final tooNarrow = tileWidth < 92;

              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final slot in schedule.slots)
                    SizedBox(
                      width: tooNarrow ? constraints.maxWidth : tileWidth,
                      child: _SlotTile(
                        slot: slot,
                        selected: schedule.isSelected(dayIndex, slot.id),
                        wide: tooNarrow,
                        onTap: () => onToggle(dayIndex, slot.id),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  final ShiftSlot slot;
  final bool selected;
  final bool wide;
  final VoidCallback onTap;

  const _SlotTile({
    required this.slot,
    required this.selected,
    required this.wide,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? AppColors.onActionOf(context)
        : AppColors.textPrimary;

    return Semantics(
      button: true,
      selected: selected,
      label: '${slot.label}, ${slot.window}',
      child: TapScale(
        onTap: onTap,
        enforceMinTarget: false,
        child: AnimatedContainer(
          duration: AppMotion.durationOf(context, AppMotion.fast),
          curve: AppMotion.standard,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.actionOf(context)
                : AppColors.surfaceMutedOf(context),
            borderRadius: AppSpacing.brMd,
            border: Border.all(
              color: selected
                  ? AppColors.actionOf(context)
                  : AppColors.borderOf(context),
            ),
          ),
          child: Row(
            mainAxisAlignment:
                wide ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              // State is never colour alone (§1.5): a check icon appears when
              // the shift is on.
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 18,
                color: selected ? fg : AppColors.textTertiary,
              ),
              Gap.hSm,
              Flexible(
                child: Column(
                  crossAxisAlignment: wide
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      slot.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyStrong.copyWith(color: fg),
                    ),
                    Text(
                      slot.window,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: selected
                            ? fg.withValues(alpha: 0.8)
                            : AppColors.textSecondary,
                      ),
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
}

class _ScheduleSkeleton extends StatelessWidget {
  final double padding;

  const _ScheduleSkeleton({required this.padding});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(padding, AppSpacing.lg, padding, padding),
      children: [
        const SkeletonBox(height: AppSpacing.minTouchTarget),
        Gap.md,
        const SkeletonBox(height: 44),
        Gap.lg,
        for (var i = 0; i < 4; i++) ...[
          const SkeletonBox(height: 132),
          Gap.md,
        ],
      ],
    );
  }
}
