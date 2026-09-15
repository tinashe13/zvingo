import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/account/notification_settings_screen.dart';
import 'package:consumer_app/features/account/payment_preferences_provider.dart';
import 'package:consumer_app/features/account/promotions_screen.dart';
import 'package:consumer_app/features/address/address_provider.dart';
import 'package:consumer_app/features/auth/auth_provider.dart';
import 'package:consumer_app/features/favourites/favourites_provider.dart';

/// The account tab.
///
/// Every row here goes somewhere real. The five rows that used to raise a
/// "coming soon" SnackBar — payment methods, saved stores, promotions, help and
/// manage account — now lead to working screens, and each row carries the value
/// it is about (the saved wallet, the number of saved stores) so the list is
/// informative before it is tapped.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: profileAsync.when(
          loading: () => const _AccountSkeleton(),
          error: (error, _) => ZvErrorState(
            error: error,
            title: 'We could not load your account',
            onRetry: () => ref.invalidate(userProfileProvider),
            secondaryActionLabel: 'Sign out',
            onSecondaryAction: () => _signOut(context, ref),
          ),
          data: (profile) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(userProfileProvider),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 128),
              children: [
                const AppPageTitle(
                  eyebrow: 'YOUR ZVINGO',
                  title: 'Account',
                  subtitle: 'Details, payments, addresses and support.',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: _ProfileCard(profile: profile),
                ),
                const SizedBox(height: AppSpacing.xl),
                _Section(
                  title: 'Your details',
                  children: [
                    AppIconTile(
                      icon: Icons.person_outline_rounded,
                      title: 'Manage account',
                      subtitle: 'Name, email, password and account deletion',
                      onTap: () => context.push('/account/edit'),
                    ),
                    const _AddressTile(),
                    const _PaymentTile(),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _Section(
                  title: 'Ordering',
                  children: [
                    const _SavedStoresTile(),
                    AppIconTile(
                      icon: Icons.local_offer_outlined,
                      title: 'Promotions',
                      subtitle: 'Your codes and live deals',
                      onTap: () => PromotionsScreen.push(context),
                    ),
                    AppIconTile(
                      icon: Icons.receipt_long_outlined,
                      title: 'Your orders',
                      subtitle: 'Track, reorder and get receipts',
                      onTap: () => context.go('/orders'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _Section(
                  title: 'Preferences and support',
                  children: [
                    AppIconTile(
                      icon: Icons.notifications_none_rounded,
                      title: 'Notifications',
                      subtitle: 'What we send and when',
                      onTap: () => NotificationSettingsScreen.push(context),
                    ),
                    AppIconTile(
                      icon: Icons.help_outline_rounded,
                      title: 'Help and support',
                      subtitle: 'Answers, order help and contact details',
                      onTap: () => context.push('/help'),
                    ),
                    AppIconTile(
                      icon: Icons.info_outline_rounded,
                      title: 'About Zvingo',
                      onTap: () => showAboutDialog(
                        context: context,
                        applicationName: 'Zvingo',
                        applicationVersion: '1.0.0',
                        applicationLegalese:
                            '© ${DateTime.now().year} Zvingo. Delivery in '
                            'Zimbabwe.',
                        children: const [
                          SizedBox(height: AppSpacing.sm),
                          Text(
                            'Food and everyday delivery, thoughtfully '
                            'designed. Maps © OpenStreetMap contributors, '
                            'tiles © CARTO.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _Section(
                  children: [
                    AppIconTile(
                      icon: Icons.logout_rounded,
                      title: 'Sign out',
                      subtitle: 'Clears this device',
                      destructive: true,
                      trailing: const SizedBox.shrink(),
                      onTap: () => _signOut(context, ref),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showZvConfirmSheet(
      context,
      title: 'Sign out of Zvingo?',
      consequence: 'Your cart, saved addresses and saved stores are cleared '
          'from this phone. Everything comes back when you sign in again — '
          'orders in progress are not affected.',
      confirmLabel: 'Sign out',
      cancelLabel: 'Stay signed in',
      icon: Icons.logout_rounded,
    );
    if (confirmed != true || !context.mounted) return;

    await ref.read(authProvider.notifier).signOut();
    if (!context.mounted) return;
    context.go('/login');
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final ZvUserProfile profile;

  @override
  Widget build(BuildContext context) {
    final initials = profile.initials;

    return ZvCard(
      color: AppColors.actionDefault,
      borderColor: AppColors.actionDefault,
      padding: const EdgeInsets.all(AppSpacing.lg),
      onTap: () => context.push('/account/edit'),
      semanticLabel: 'Edit ${profile.fullName}\'s details',
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: AppColors.brandLime,
              borderRadius: AppRadius.lgAll,
            ),
            alignment: Alignment.center,
            child: initials.isEmpty
                ? const Icon(Icons.person_rounded,
                    size: 30, color: AppColors.neutral900)
                : Text(
                    initials,
                    style:
                        AppTextStyles.h1.copyWith(color: AppColors.neutral900),
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.fullName.isEmpty
                      ? 'Zvingo customer'
                      : profile.fullName,
                  style: AppTextStyles.h2.copyWith(color: AppColors.textOnDark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxxs),
                Text(
                  profile.displayPhone,
                  style: AppTextStyles.tabular(AppTextStyles.caption)
                      .copyWith(color: AppColors.neutral300),
                ),
                if (profile.email != null) ...[
                  const SizedBox(height: AppSpacing.xxxs),
                  Text(
                    profile.email!,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.neutral400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.edit_outlined, color: AppColors.textOnDark),
        ],
      ),
    );
  }
}

/// Saved addresses, with the count and the default in the subtitle.
class _AddressTile extends ConsumerWidget {
  const _AddressTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(savedAddressesProvider);
    final defaultLabel = addresses
        .where((a) => a.isDefault)
        .map((a) => a.label)
        .firstOrNull;

    return AppIconTile(
      icon: Icons.location_on_outlined,
      title: 'Saved addresses',
      subtitle: addresses.isEmpty
          ? 'Add home or work for faster checkout'
          : defaultLabel != null
              ? '${addresses.length} saved · $defaultLabel is default'
              : '${addresses.length} saved',
      onTap: () => context.push('/addresses'),
    );
  }
}

/// Payment preferences — mobile money, never cards.
class _PaymentTile extends ConsumerWidget {
  const _PaymentTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(paymentPreferencesStoreProvider);

    return AppIconTile(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Payment preferences',
      subtitle: prefs.wallet == null
          ? 'EcoCash, OneMoney or InnBucks'
          : 'Default: ${prefs.wallet!.label}',
      onTap: () => context.push('/payment-methods'),
      trailing: prefs.wallet == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WalletChip(wallet: prefs.wallet!),
                const SizedBox(width: AppSpacing.xs),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.neutral400),
              ],
            ),
    );
  }
}

/// "Saved stores" is the same list as Favourites — one screen, one truth.
class _SavedStoresTile extends ConsumerWidget {
  const _SavedStoresTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(favouritesProvider).length;

    return AppIconTile(
      icon: Icons.favorite_border_rounded,
      title: 'Saved stores',
      subtitle: count == 0
          ? 'Tap the heart on a restaurant to save it'
          : '$count saved ${count == 1 ? 'store' : 'stores'}',
      onTap: () => context.push('/favourites'),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xxs,
                bottom: AppSpacing.xs,
              ),
              child: Text(title!, style: AppTextStyles.overline),
            ),
          ],
          ZvCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i != children.length - 1)
                    const Divider(
                      height: 1,
                      indent: 64,
                      endIndent: AppSpacing.md,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountSkeleton extends StatelessWidget {
  const _AccountSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
        128,
      ),
      children: const [
        ZvSkeletonBox(height: 28, width: 160),
        SizedBox(height: AppSpacing.sm),
        ZvSkeletonBox(height: 16, width: 240),
        SizedBox(height: AppSpacing.xl),
        ZvSkeletonBox(height: 100, radius: AppRadius.lg),
        SizedBox(height: AppSpacing.xl),
        ZvSkeletonBox(height: 180, radius: AppRadius.lg),
        SizedBox(height: AppSpacing.md),
        ZvSkeletonBox(height: 180, radius: AppRadius.lg),
      ],
    );
  }
}
