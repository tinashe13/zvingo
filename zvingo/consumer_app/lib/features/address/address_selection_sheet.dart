import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/core/delivery_location_provider.dart';
import 'package:consumer_app/features/address/address_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AddressSelectionSheet extends ConsumerWidget {
  const AddressSelectionSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddressSelectionSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedAddresses = ref.watch(savedAddressesProvider);
    final currentLocationAsync = ref.watch(currentLocationAddressProvider);
    final deliveryLoc = ref.watch(deliveryLocationNotifierProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                const Text('Delivery Address', style: AppTextStyles.titleLarge),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    context.push('/addresses');
                  },
                  child: Text(
                    'Manage',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Current Location option
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: currentLocationAsync.when(
              data: (currentAddr) => _AddressTile(
                icon: Icons.my_location,
                iconColor: AppColors.info,
                label: 'Current Location',
                address: currentAddr.address,
                isSelected: deliveryLoc?.displayName == currentAddr.address,
                onTap: () {
                  ref
                      .read(savedAddressesProvider.notifier)
                      .selectAddress(currentAddr);
                  Navigator.pop(context);
                },
              ),
              loading: () => const ListTile(
                leading: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text('Detecting your location...'),
              ),
              error: (e, _) => _AddressTile(
                icon: Icons.location_off,
                iconColor: AppColors.textHint,
                label: 'Current Location',
                address: 'Tap to retry',
                isSelected: false,
                onTap: () {
                  ref.invalidate(currentLocationAddressProvider);
                },
              ),
            ),
          ),

          if (savedAddresses.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                'SAVED ADDRESSES',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textHint,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],

          // Saved addresses list
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: savedAddresses.length,
              itemBuilder: (context, index) {
                final addr = savedAddresses[index];
                final isSelected = deliveryLoc?.lat == addr.lat &&
                    deliveryLoc?.lng == addr.lng;
                return _AddressTile(
                  icon: _iconForLabel(addr.label),
                  iconColor: AppColors.primary,
                  label: addr.label,
                  address: addr.address,
                  isSelected: isSelected,
                  isDefault: addr.isDefault,
                  onTap: () {
                    ref
                        .read(savedAddressesProvider.notifier)
                        .selectAddress(addr);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),

          // Add new address button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                context.push('/addresses/add');
              },
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add New Address'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
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

class _AddressTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;
  final bool isSelected;
  final bool isDefault;
  final VoidCallback onTap;

  const _AddressTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.address,
    required this.isSelected,
    this.isDefault = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primarySurface : AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Row(
        children: [
          Text(
            label,
            style: AppTextStyles.titleSmall.copyWith(
              color: isSelected ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
          if (isDefault) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Default',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        address,
        style: AppTextStyles.bodySmall,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
          : null,
      onTap: onTap,
    );
  }
}
