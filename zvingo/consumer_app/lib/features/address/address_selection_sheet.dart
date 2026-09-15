import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/address_provider.dart';

/// "Where are we delivering?" — opened from the home header, the cart, the map
/// and checkout.
class AddressSelectionSheet extends ConsumerWidget {
  const AddressSelectionSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (_) => const AddressSelectionSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedAddressesProvider);
    final currentLocation = ref.watch(currentLocationAddressProvider);
    final delivery = ref.watch(deliveryLocationNotifierProvider);

    bool isActive(double lat, double lng) =>
        delivery != null &&
        (delivery.lat - lat).abs() < 0.00001 &&
        (delivery.lng - lng).abs() < 0.00001;

    return ZvSheet(
      title: 'Delivery address',
      subtitle: 'Pick where this order should go.',
      footer: Row(
        children: [
          Expanded(
            child: ZvButton.secondary(
              label: 'Manage',
              icon: Icons.tune_rounded,
              onPressed: () {
                Navigator.pop(context);
                context.push('/addresses');
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: ZvButton.primary(
              label: 'Add address',
              icon: Icons.add_rounded,
              onPressed: () {
                Navigator.pop(context);
                context.push('/addresses/add');
              },
            ),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.55,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          children: [
            currentLocation.when(
              loading: () => const ZvListTileSkeleton(),
              error: (_, __) => _OptionTile(
                icon: Icons.location_disabled_rounded,
                title: 'Current location unavailable',
                subtitle: 'Turn location on for Zvingo, then tap to retry.',
                selected: false,
                onTap: () => ref.invalidate(currentLocationAddressProvider),
                trailing: const Icon(Icons.refresh_rounded,
                    color: AppColors.neutral400),
              ),
              data: (current) => _OptionTile(
                icon: Icons.my_location_rounded,
                title: 'Current location',
                subtitle: current.address,
                selected: isActive(current.lat, current.lng),
                onTap: () {
                  ref
                      .read(savedAddressesProvider.notifier)
                      .selectAddress(current);
                  Navigator.pop(context);
                },
              ),
            ),
            if (saved.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.md),
                child: ZvEmptyState(
                  icon: Icons.bookmark_add_outlined,
                  title: 'No saved addresses',
                  message: 'Save home or work and your next order starts '
                      'there automatically.',
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                ),
              )
            else ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xxs,
                  AppSpacing.md,
                  0,
                  AppSpacing.xs,
                ),
                child: Text('SAVED', style: AppTextStyles.overline),
              ),
              ...saved.map(
                (address) => _OptionTile(
                  icon: _iconForLabel(address.label),
                  title: address.label,
                  subtitle: address.address,
                  note: address.hasDeliveryNotes ? address.notesSummary : null,
                  isDefault: address.isDefault,
                  selected: isActive(address.lat, address.lng),
                  onTap: () {
                    ref
                        .read(savedAddressesProvider.notifier)
                        .selectAddress(address);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconForLabel(String label) => switch (label.toLowerCase()) {
        'home' => Icons.home_outlined,
        'work' => Icons.work_outline_rounded,
        'recent' => Icons.history_rounded,
        _ => Icons.place_outlined,
      };
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.note,
    this.isDefault = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final String? note;
  final bool isDefault;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: ZvCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.sm),
        borderColor: selected ? AppColors.actionDefault : AppColors.border,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color:
                    selected ? AppColors.actionDefault : AppColors.surfaceMuted,
                borderRadius: AppRadius.smAll,
              ),
              child: Icon(
                icon,
                size: 20,
                color:
                    selected ? AppColors.textOnDark : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: AppTextStyles.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: AppSpacing.xs),
                        const ZvBadge(label: 'Default', tone: ZvTone.brand),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxxs),
                  Text(
                    subtitle,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (note != null) ...[
                    const SizedBox(height: AppSpacing.xxxs),
                    Text(
                      note!,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 22),
          ],
        ),
      ),
    );
  }
}
