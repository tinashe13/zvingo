import 'package:consumer_app/common/widgets/app_ui.dart';
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
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => AppEmptyState(
            icon: Icons.person_off_outlined,
            title: 'Profile unavailable',
            message: 'We could not load your account right now.',
            action: ElevatedButton(
              onPressed: () => ref.invalidate(userProfileProvider),
              child: const Text('Try again'),
            ),
          ),
          data: (profile) => ListView(
            padding: const EdgeInsets.only(bottom: 118),
            children: [
              const AppPageTitle(
                eyebrow: 'Your Zvingo',
                title: 'Account',
                subtitle: 'Personal details, payments, addresses and support.',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AppSurface(
                  color: AppColors.selectedDark,
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.person_rounded,
                            size: 30, color: AppColors.textPrimary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile['full_name'] ?? 'Zvingo customer',
                              style: AppTextStyles.titleLarge
                                  .copyWith(color: AppColors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              profile['email'] ?? profile['phone'] ?? '',
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit account',
                        onPressed: () => context.push('/account/edit'),
                        icon: const Icon(Icons.edit_outlined,
                            color: AppColors.white),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              _section(
                children: [
                  AppIconTile(
                    icon: Icons.person_outline_rounded,
                    title: 'Manage account',
                    subtitle: 'Name, email and phone',
                    onTap: () => context.push('/account/edit'),
                  ),
                  AppIconTile(
                    icon: Icons.credit_card_rounded,
                    title: 'Payment methods',
                    subtitle: 'Manage how you pay',
                    onTap: () => context.push('/payment-methods'),
                  ),
                  AppIconTile(
                    icon: Icons.location_on_outlined,
                    title: 'Saved addresses',
                    subtitle: 'Home, work and recent places',
                    onTap: () => context.push('/addresses'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _section(
                children: [
                  AppIconTile(
                    icon: Icons.favorite_border_rounded,
                    title: 'Saved stores',
                    onTap: () => context.push('/favourites'),
                  ),
                  AppIconTile(
                    icon: Icons.local_offer_outlined,
                    title: 'Promotions',
                    onTap: () => context.push('/offers'),
                  ),
                  AppIconTile(
                    icon: Icons.help_outline_rounded,
                    title: 'Help and support',
                    onTap: () => context.push('/help'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _section(
                children: [
                  AppIconTile(
                    icon: Icons.info_outline_rounded,
                    title: 'About Zvingo',
                    onTap: () => showAboutDialog(
                      context: context,
                      applicationName: 'Zvingo',
                      applicationVersion: '1.0.0',
                      children: const [
                        Text(
                            'Food and everyday delivery, thoughtfully designed.')
                      ],
                    ),
                  ),
                  AppIconTile(
                    icon: Icons.logout_rounded,
                    title: 'Sign out',
                    destructive: true,
                    trailing: const SizedBox.shrink(),
                    onTap: () async {
                      await ref.read(authProvider.notifier).signOut();
                      if (context.mounted) context.go('/login');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppSurface(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i != children.length - 1)
                const Divider(indent: 70, endIndent: 16),
            ],
          ],
        ),
      ),
    );
  }
}
