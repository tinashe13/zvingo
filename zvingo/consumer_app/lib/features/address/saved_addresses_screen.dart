import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/address_provider.dart';
import 'package:consumer_app/features/address/saved_address.dart';

/// Every address this customer has saved, with exactly one marked default.
class SavedAddressesScreen extends ConsumerWidget {
  const SavedAddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(savedAddressesProvider);
    final delivery = ref.watch(deliveryLocationNotifierProvider);

    return ZvScreen(
      title: 'Saved addresses',
      subtitle: addresses.isEmpty
          ? null
          : '${addresses.length} saved · tap one to deliver there',
      fallbackRoute: '/account',
      footer: addresses.isEmpty
          ? null
          : ZvStickyFooter(
              child: ZvButton.primary(
                label: 'Add another address',
                icon: Icons.add_rounded,
                onPressed: () => context.push('/addresses/add'),
              ),
            ),
      child: addresses.isEmpty
          ? ZvEmptyState(
              icon: Icons.location_on_outlined,
              title: 'No saved addresses yet',
              message: 'Save home and work once and checkout takes two taps '
                  'from then on.',
              actionLabel: 'Add your first address',
              onAction: () => context.push('/addresses/add'),
            )
          : ZvStaggeredListView.builder(
              itemCount: addresses.length,
              padding: const EdgeInsets.all(AppSpacing.md),
              itemBuilder: (context, index) {
                final address = addresses[index];
                final selected = delivery != null &&
                    (delivery.lat - address.lat).abs() < 0.00001 &&
                    (delivery.lng - address.lng).abs() < 0.00001;
                return _AddressCard(
                  address: address,
                  selected: selected,
                  onUse: () => _use(context, ref, address),
                  onEdit: () =>
                      context.push('/addresses/edit', extra: address),
                  onMakeDefault: address.isDefault
                      ? null
                      : () => ref
                          .read(savedAddressesProvider.notifier)
                          .setDefault(address.id),
                  onDelete: () => _confirmDelete(context, ref, address),
                );
              },
            ),
    );
  }

  void _use(BuildContext context, WidgetRef ref, SavedAddress address) {
    ref.read(savedAddressesProvider.notifier).selectAddress(address);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Delivering to ${address.label}')),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SavedAddress address,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(savedAddressesProvider.notifier);

    final confirmed = await showZvConfirmSheet(
      context,
      title: 'Delete "${address.label}"?',
      consequence: address.isDefault
          ? 'This is your default address. Deleting it means your next order '
              'starts with no address chosen, and any delivery notes on it are '
              'lost.'
          : 'The address and its delivery notes are removed from this account. '
              'Orders already on their way are not affected.',
      confirmLabel: 'Delete address',
      icon: Icons.delete_outline_rounded,
    );
    if (confirmed != true) return;

    await notifier.deleteAddress(address.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text('${address.label} deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => notifier.addAddress(address),
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.selected,
    required this.onUse,
    required this.onEdit,
    required this.onDelete,
    this.onMakeDefault,
  });

  final SavedAddress address;
  final bool selected;
  final VoidCallback onUse;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onMakeDefault;

  @override
  Widget build(BuildContext context) {
    return ZvCard(
      onTap: onUse,
      borderColor: selected ? AppColors.actionDefault : AppColors.border,
      semanticLabel: 'Deliver to ${address.label}, ${address.address}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.actionDefault
                      : AppColors.surfaceMuted,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Icon(
                  _iconForLabel(address.label),
                  size: 22,
                  color: selected
                      ? AppColors.textOnDark
                      : AppColors.textSecondary,
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
                            address.label,
                            style: AppTextStyles.h3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (address.isDefault) ...[
                          const SizedBox(width: AppSpacing.xs),
                          const ZvBadge(
                            label: 'Default',
                            tone: ZvTone.brand,
                            icon: Icons.star_rounded,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxxs),
                    Text(
                      address.address,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More options for ${address.label}',
                icon: const Icon(Icons.more_vert_rounded,
                    color: AppColors.neutral400),
                onSelected: (value) {
                  switch (value) {
                    case 'use':
                      onUse();
                    case 'default':
                      onMakeDefault?.call();
                    case 'edit':
                      onEdit();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'use',
                    child: Text('Deliver here'),
                  ),
                  if (onMakeDefault != null)
                    const PopupMenuItem(
                      value: 'default',
                      child: Text('Make default'),
                    ),
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete',
                        style: TextStyle(color: AppColors.error)),
                  ),
                ],
              ),
            ],
          ),
          if (address.hasDeliveryNotes) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: const BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: AppRadius.smAll,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.notes_rounded,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      address.notesSummary,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (selected) ...[
            const SizedBox(height: AppSpacing.sm),
            const ZvStatusChip(
              label: 'Delivering here',
              tone: ZvTone.success,
              icon: Icons.check_circle_rounded,
              compact: true,
            ),
          ],
        ],
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
