import 'package:flutter/material.dart';
import '../../core/app_colors.dart';

/// ScheduleScreen — day/slot toggles for driver shifts.
/// Port of ScheduleScreen.kt.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final _slots = ['Morning\n6am-12pm', 'Afternoon\n12pm-6pm', 'Evening\n6pm-12am'];

  // Map<dayIndex, Set<slotIndex>>
  final Map<int, Set<int>> _selected = {};

  void _toggleSlot(int day, int slot) {
    setState(() {
      _selected.putIfAbsent(day, () => {});
      if (_selected[day]!.contains(slot)) {
        _selected[day]!.remove(slot);
      } else {
        _selected[day]!.add(slot);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _days.length,
        itemBuilder: (context, dayIndex) {
          final daySlots = _selected[dayIndex] ?? {};

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
                        onTap: () => _toggleSlot(dayIndex, slotIndex),
                        child: Container(
                          margin: EdgeInsets.only(
                              left: slotIndex == 0 ? 0 : 8),
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
