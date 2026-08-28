import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_colors.dart';
import '../../providers/schedule_provider.dart';

/// ScheduleScreen — day/slot toggles for driver shifts.
/// Port of ScheduleScreen.kt, wired to the backend schedule provider.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  final _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final _slots = [
    'Morning\n6am-12pm',
    'Afternoon\n12pm-6pm',
    'Evening\n6pm-12am',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(scheduleProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(scheduleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
      ),
      body: schedule.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _days.length,
              itemBuilder: (context, dayIndex) {
                final daySlots = schedule.selected[dayIndex] ?? {};

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _days[dayIndex],
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: List.generate(_slots.length, (slotIndex) {
                          final isSelected = daySlots.contains(slotIndex);
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => ref
                                  .read(scheduleProvider.notifier)
                                  .toggle(dayIndex, slotIndex),
                              child: Container(
                                margin: EdgeInsets.only(
                                    left: slotIndex == 0 ? 0 : 8),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primaryLight
                                      : AppColors.neutral100,
                                  borderRadius: BorderRadius.circular(12),
                                  border: isSelected
                                      ? Border.all(
                                          color: AppColors.primary, width: 1.5)
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    _slots[slotIndex],
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? AppColors.primaryHover
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
