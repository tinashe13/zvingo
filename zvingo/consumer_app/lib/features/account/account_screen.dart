import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_text_styles.dart';
import 'package:consumer_app/features/auth/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error loading profile')),
          data: (profile) => ListView(
            children: [
              const SizedBox(height: 24),
              // Avatar + Name
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: AppColors.primarySurface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person, size: 36, color: AppColors.primary),
                    ),
                    const SizedBox(height: 12),
                    Text(profile['full_name'] ?? 'User', style: AppTextStyles.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      profile['email'] ?? profile['phone'] ?? '',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Divider(),

              _settingsTile(context, Icons.person_outline, 'Manage Account', onTap: () {
                // Could navigate to profile edit screen
              }),
              _settingsTile(context, Icons.payment, 'Payment Methods', onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment methods coming soon')),
                );
              }),
              _settingsTile(context, Icons.location_on_outlined, 'Saved Addresses', onTap: () {
                context.push('/addresses');
              }),
              _settingsTile(context, Icons.favorite_border, 'Saved Stores', onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saved stores coming soon')),
                );
              }),
              _settingsTile(context, Icons.local_offer_outlined, 'Promotions', onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Promotions coming soon')),
                );
              }),
              const Divider(),
              _settingsTile(context, Icons.help_outline, 'Help', onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Help center coming soon')),
                );
              }),
              _settingsTile(context, Icons.info_outline, 'About', onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'Zvingo',
                  applicationVersion: '1.0.0',
                  children: [const Text('Food delivery made easy.')],
                );
              }),
              _settingsTile(context, Icons.logout, 'Sign Out', isDestructive: true, onTap: () async {
                await ref.read(authProvider.notifier).signOut();
                if (context.mounted) {
                  context.go('/login');
                }
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingsTile(BuildContext context, IconData icon, String title,
      {bool isDestructive = false, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon,
          color: isDestructive ? AppColors.error : AppColors.textSecondary,
          size: 22),
      title: Text(
        title,
        style: AppTextStyles.bodyLarge.copyWith(
          color: isDestructive ? AppColors.error : AppColors.textPrimary,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textHint, size: 20),
      onTap: onTap,
    );
  }
}
