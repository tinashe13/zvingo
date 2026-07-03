import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/delivery_state.dart';

/// DeliveryStepIndicator — progress dots for the delivery flow.
/// Port of DeliveryStepIndicator.kt.
class DeliveryStepIndicator extends StatelessWidget {
  final DeliveryState currentState;

  const DeliveryStepIndicator({
    super.key,
    required this.currentState,
  });

  static const _steps = [
    ('Accept', DeliveryState.accepted),
    ('Pickup', DeliveryState.enRoutePickup),
    ('At Store', DeliveryState.arrivedPickup),
    ('Picked Up', DeliveryState.pickedUp),
    ('Deliver', DeliveryState.enRouteDelivery),
    ('Arrived', DeliveryState.arrivedDelivery),
    ('Done', DeliveryState.delivered),
  ];

  @override
  Widget build(BuildContext context) {
    final currentIndex =
        _steps.indexWhere((s) => s.$2 == currentState).clamp(0, _steps.length - 1);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(_steps.length, (index) {
        final (label, _) = _steps[index];
        final isComplete = index < currentIndex;
        final isCurrent = index == currentIndex;

        final dotColor = isComplete
            ? AppColors.primary
            : isCurrent
                ? AppColors.warning
                : Theme.of(context).colorScheme.surfaceContainerHighest;

        return Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: isCurrent ? 14 : 10,
                height: isCurrent ? 14 : 10,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }),
    );
  }
}
