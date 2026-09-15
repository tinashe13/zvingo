import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ratings_provider.dart';
import '../../widgets/widgets.dart';
import 'app_info.dart';

/// Account.
///
/// Every row here goes somewhere real. The previous version had **seven**
/// `onTap: () {}` entries — Vehicle Details, Notifications, Safety, About,
/// Help, Terms of Service and Privacy Policy — a menu that looked complete and
/// did nothing. Each is now either wired to a working screen or gone:
///
/// * Vehicle details → `GET`/`PUT /driver/vehicle`
/// * Notifications → `GET`/`PUT /notification/preferences`
/// * Safety → emergency contact, emergency actions, location sharing
/// * About → real build version, and the legal documents
/// * Help → in-app answers plus support contact
/// * Terms / Privacy → the hosted document, or an honest "not published yet"
///
/// There is deliberately **no "Delete account" row**. Google Play requires
/// in-app account deletion, but no backend route exists to delete a driver
/// (cross-team finding X4), and a delete button that does not delete is worse
/// than no button at all. The exact endpoint needed is specified in the report.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Log out of Zvingo?',
      consequence:
          'You will stop receiving delivery offers on this phone until you '
          'sign in again. Finish any delivery you are on first.',
      confirmLabel: 'Log out',
      cancelLabel: 'Stay signed in',
      icon: Icons.logout_rounded,
    );
    if (!confirmed || !mounted) return;

    setState(() => _signingOut = true);
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    setState(() => _signingOut = false);
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final ratings = ref.watch(ratingsProvider);
    final padding = AppSpacing.screenPaddingOf(context);

    return Scaffold(
      appBar: const DriverAppBar(
        title: 'Account',
        showBack: false,
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => ref.read(authProvider.notifier).refreshProfile(),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              padding,
              AppSpacing.lg,
              padding,
              AppSpacing.section,
            ),
            children: [
              StaggeredEntrance(
                index: 0,
                child: _ProfileCard(auth: auth, ratings: ratings),
              ),
              Gap.section,
              const StaggeredEntrance(index: 1, child: _GroupLabel('Driving')),
              Gap.sm,
              StaggeredEntrance(
                index: 2,
                child: _MenuGroup(
                  items: [
                    _MenuItem(
                      icon: Icons.directions_car_outlined,
                      label: 'Vehicle details',
                      description: 'What the customer sees when you arrive',
                      onTap: () => context.push('/vehicle'),
                    ),
                    _MenuItem(
                      icon: Icons.event_available_outlined,
                      label: 'Your week',
                      description: 'The shifts you plan to work',
                      onTap: () => context.go('/schedule'),
                    ),
                    _MenuItem(
                      icon: Icons.receipt_long_outlined,
                      label: 'Delivery history',
                      description: 'Every delivery and how it was paid',
                      onTap: () => context.go('/earnings/history'),
                    ),
                  ],
                ),
              ),
              Gap.xl,
              const StaggeredEntrance(index: 3, child: _GroupLabel('App')),
              Gap.sm,
              StaggeredEntrance(
                index: 4,
                child: _MenuGroup(
                  items: [
                    _MenuItem(
                      icon: Icons.notifications_outlined,
                      label: 'Notifications',
                      description: 'What Zvingo may interrupt you for',
                      onTap: () => context.push('/account/notifications'),
                    ),
                    _MenuItem(
                      icon: Icons.shield_outlined,
                      label: 'Safety',
                      description: 'Emergency contact and sharing where you are',
                      onTap: () => context.push('/account/safety'),
                    ),
                  ],
                ),
              ),
              Gap.xl,
              const StaggeredEntrance(index: 5, child: _GroupLabel('Support & legal')),
              Gap.sm,
              StaggeredEntrance(
                index: 6,
                child: _MenuGroup(
                  items: [
                    _MenuItem(
                      icon: Icons.help_outline_rounded,
                      label: 'Help',
                      description: 'Answers, and how to reach a person',
                      onTap: () => context.push('/account/help'),
                    ),
                    _MenuItem(
                      icon: Icons.description_outlined,
                      label: 'Terms of Service',
                      trailing: LegalDocument.terms.isConfigured
                          ? null
                          : const StatusChip(
                              label: 'Not published',
                              tone: StatusTone.warning,
                            ),
                      onTap: () => context.push('/account/terms'),
                    ),
                    _MenuItem(
                      icon: Icons.privacy_tip_outlined,
                      label: 'Privacy Policy',
                      trailing: LegalDocument.privacy.isConfigured
                          ? null
                          : const StatusChip(
                              label: 'Not published',
                              tone: StatusTone.warning,
                            ),
                      onTap: () => context.push('/account/privacy'),
                    ),
                    _MenuItem(
                      icon: Icons.info_outline_rounded,
                      label: 'About',
                      description: AppInfo.versionLabel,
                      onTap: () => context.push('/account/about'),
                    ),
                  ],
                ),
              ),
              Gap.section,
              StaggeredEntrance(
                index: 7,
                child: DriverDestructiveButton(
                  label: 'Log out',
                  icon: Icons.logout_rounded,
                  isLoading: _signingOut,
                  onPressed: _signingOut ? null : _signOut,
                ),
              ),
              Gap.lg,
              Center(
                child: Text(
                  '${AppInfo.appName} · ${AppInfo.versionLabel}',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Profile ─────────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final AuthState auth;
  final RatingsState ratings;

  const _ProfileCard({required this.auth, required this.ratings});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: AppSpacing.cardDecoration(context),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.brandGreenSurface,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  auth.initials,
                  style: AppTextStyles.h3
                      .copyWith(color: AppColors.brandGreenDark),
                ),
              ),
              Gap.hMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppTextStyles.onSurface(context, AppTextStyles.h3),
                    ),
                    if (auth.phone.isNotEmpty) ...[
                      Gap.xxs,
                      Text(
                        auth.phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.money
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                    if (auth.email.isNotEmpty) ...[
                      Gap.xxs,
                      Text(
                        auth.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (ratings.hasRating || ratings.lifetimeDeliveries > 0) ...[
            Gap.lg,
            Divider(height: 1, color: AppColors.borderOf(context)),
            Gap.lg,
            Row(
              children: [
                if (ratings.hasRating)
                  Expanded(
                    child: _MiniStat(
                      icon: Icons.star_rounded,
                      iconColor: AppColors.rating,
                      value: ratings.formattedRating,
                      label: 'Your rating',
                    ),
                  ),
                if (ratings.hasRating && ratings.lifetimeDeliveries > 0)
                  Container(
                    width: 1,
                    height: 36,
                    color: AppColors.borderOf(context),
                  ),
                if (ratings.lifetimeDeliveries > 0)
                  Expanded(
                    child: _MiniStat(
                      icon: Icons.local_shipping_outlined,
                      iconColor: AppColors.textSecondary,
                      value: '${ratings.lifetimeDeliveries}',
                      label: 'Deliveries',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _MiniStat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: iconColor),
            Gap.hXs,
            Text(
              value,
              style: AppTextStyles.metric
                  .copyWith(color: AppColors.textPrimary, fontSize: 18),
            ),
          ],
        ),
        Gap.xxs,
        Text(
          label,
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

// ── Menu ────────────────────────────────────────────────────────────────────

class _GroupLabel extends StatelessWidget {
  final String text;

  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.overline.copyWith(color: AppColors.textSecondary),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  final List<_MenuItem> items;

  const _MenuGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppSpacing.cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: AppSpacing.huge,
                color: AppColors.borderOf(context),
              ),
            items[i],
          ],
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? description;
  final Widget? trailing;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.description,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        constraints:
            const BoxConstraints(minHeight: AppSpacing.minTouchTarget + 8),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.textSecondary),
            Gap.hMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.body
                        .copyWith(color: AppColors.textPrimary),
                  ),
                  if (description != null) ...[
                    Gap.xxs,
                    Text(
                      description!,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[Gap.hSm, trailing!],
            Gap.hXs,
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
