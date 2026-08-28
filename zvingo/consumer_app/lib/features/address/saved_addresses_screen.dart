import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/common/widgets/app_ui.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/address_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SavedAddressesScreen extends ConsumerWidget {
  const SavedAddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(savedAddressesProvider);
    final deliveryLoc = ref.watch(deliveryLocationNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text('Saved addresses'),
      ),
      body: addresses.isEmpty
          ? _emptyState(context)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: addresses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final addr = addresses[index];
                final isSelected = deliveryLoc?.lat == addr.lat &&
                    deliveryLoc?.lng == addr.lng;

                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.divider,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.accent
                            : AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _iconForLabel(addr.label),
                        color: isSelected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        size: 22,
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(addr.label, style: AppTextStyles.titleSmall),
                        if (addr.isDefault) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentSurface,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Default',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        addr.address,
                        style: AppTextStyles.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          size: 20, color: AppColors.textHint),
                      onSelected: (value) async {
                        switch (value) {
                          case 'select':
                            ref
                                .read(savedAddressesProvider.notifier)
                                .selectAddress(addr);
                            break;
                          case 'default':
                            await ref
                                .read(savedAddressesProvider.notifier)
                                .setDefault(addr.id);
                            break;
                          case 'edit':
                            context.push('/addresses/edit', extra: addr);
                            break;
                          case 'delete':
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete Address'),
                                content: Text(
                                    'Remove "${addr.label}" from saved addresses?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete',
                                        style:
                                            TextStyle(color: AppColors.error)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await ref
                                  .read(savedAddressesProvider.notifier)
                                  .deleteAddress(addr.id);
                            }
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'select', child: Text('Use this address')),
                        if (!addr.isDefault)
                          const PopupMenuItem(
                              value: 'default', child: Text('Set as default')),
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        const PopupMenuItem(
                            value: 'delete', child: Text('Delete')),
                      ],
                    ),
                    onTap: () {
                      ref
                          .read(savedAddressesProvider.notifier)
                          .selectAddress(addr);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('Delivering to ${addr.label}')),
                        );
                      }
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/addresses/add'),
        backgroundColor: AppColors.selectedDark,
        foregroundColor: AppColors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add address'),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return AppEmptyState(
      icon: Icons.location_on_outlined,
      title: 'No saved addresses',
      message: 'Save home or work to make checkout almost instant.',
      action: ElevatedButton.icon(
        onPressed: () => context.push('/addresses/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add address'),
      ),
    );
  }

  IconData _iconForLabel(String label) {
    switch (label.toLowerCase()) {
      case 'home':
        return Icons.home_outlined;
      case 'work':
        return Icons.work_outline;
      default:
        return Icons.location_on_outlined;
    }
  }
}
