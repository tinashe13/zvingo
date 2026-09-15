import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/app_motion.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../providers/ratings_provider.dart';
import '../../widgets/widgets.dart';

/// How customers rate this driver, framed as feedback rather than as a score
/// hanging over them.
///
/// Three deliberate choices:
///
/// * A driver with no ratings yet sees "not rated yet", **not 0.0 stars**.
///   Same for the three performance rates: the backend returns `null` rather
///   than `0` when there is nothing to measure, and that distinction survives
///   all the way to the screen.
/// * Nothing here threatens deactivation. Each rate explains what it measures
///   and what moves it.
/// * Comments come first among the detail, because that is where the
///   actionable information actually is.
class RatingsScreen extends ConsumerStatefulWidget {
  const RatingsScreen({super.key});

  @override
  ConsumerState<RatingsScreen> createState() => _RatingsScreenState();
}

class _RatingsScreenState extends ConsumerState<RatingsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(ratingsProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ratings = ref.watch(ratingsProvider);
    final notifier = ref.read(ratingsProvider.notifier);
    final padding = AppSpacing.screenPaddingOf(context);

    return Scaffold(
      appBar: const DriverAppBar(
        title: 'Your rating',
        subtitle: 'What customers say about your deliveries',
        showBack: false,
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: notifier.refresh,
          child: _body(context, ratings, notifier, padding),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    RatingsState ratings,
    RatingsNotifier notifier,
    double padding,
  ) {
    if (ratings.failure != null && ratings.lifetimeDeliveries == 0) {
      return ListView(
        padding:
            EdgeInsets.symmetric(horizontal: padding, vertical: AppSpacing.xxl),
        children: [_failureState(ratings.failure!, notifier.refresh)],
      );
    }

    if (ratings.isLoading && ratings.recentFeedback.isEmpty && !ratings.hasRating) {
      return _RatingsSkeleton(padding: padding);
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        padding,
        AppSpacing.lg,
        padding,
        AppSpacing.section,
      ),
      children: [
        StaggeredEntrance(index: 0, child: _ScoreCard(ratings: ratings)),
        Gap.md,
        StaggeredEntrance(
          index: 1,
          child: _EncouragementCard(message: ratings.encouragement),
        ),
        if (ratings.ratedReviews > 0) ...[
          Gap.section,
          StaggeredEntrance(
            index: 2,
            child: _SectionTitle(
              'How customers rated you',
              subtitle:
                  '${ratings.ratedReviews} ${ratings.ratedReviews == 1 ? 'rating' : 'ratings'} in total',
            ),
          ),
          Gap.md,
          StaggeredEntrance(
            index: 3,
            child: _DistributionCard(ratings: ratings),
          ),
        ],
        Gap.section,
        StaggeredEntrance(
          index: 4,
          child: _SectionTitle(
            'Your delivery record',
            subtitle: 'Last ${ratings.windowDays} days',
          ),
        ),
        Gap.md,
        StaggeredEntrance(
          index: 5,
          child: _RateCard(
            icon: Icons.verified_outlined,
            label: 'Deliveries completed',
            rate: ratings.completionRate,
            help:
                'Of the deliveries you accepted, how many you saw through to '
                'the customer.',
          ),
        ),
        Gap.md,
        StaggeredEntrance(
          index: 6,
          child: _RateCard(
            icon: Icons.schedule_rounded,
            label: 'On time',
            rate: ratings.onTimeRate,
            help:
                'Delivered within ${ratings.onTimeSlaMinutes} minutes of '
                'accepting. Traffic happens — this is measured over many '
                'trips, not one bad afternoon.',
          ),
        ),
        Gap.md,
        StaggeredEntrance(
          index: 7,
          child: _RateCard(
            icon: Icons.notifications_active_outlined,
            label: 'Offers accepted',
            rate: ratings.acceptanceRate,
            help:
                'How often you take an offer when one reaches you. Declining '
                'an offer that does not work for you is fine — this is '
                'here so you can see the pattern, not to police it.',
          ),
        ),
        Gap.md,
        StaggeredEntrance(
          index: 8,
          child: _LifetimeCard(ratings: ratings),
        ),
        Gap.section,
        StaggeredEntrance(
          index: 9,
          child: const _SectionTitle(
            'What customers wrote',
            subtitle: 'Most recent first',
          ),
        ),
        Gap.md,
        if (ratings.recentFeedback.isEmpty)
          _NoFeedbackYet(hasDeliveries: ratings.lifetimeDeliveries > 0)
        else
          ...ratings.recentFeedback.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: StaggeredEntrance(
                    index: entry.key + 10,
                    child: _FeedbackCard(item: entry.value),
                  ),
                ),
              ),
        if (ratings.failure != null) ...[
          Gap.md,
          _InlineRetry(onRetry: notifier.refresh),
        ],
      ],
    );
  }

  Widget _failureState(RatingsFailure failure, VoidCallback onRetry) {
    switch (failure) {
      case RatingsFailure.notFound:
        return DriverErrorState(
          title: 'We could not find your driver profile',
          message:
              'Your ratings live on your Zvingo driver profile and we could '
              'not load it. Signing out and back in usually fixes this.',
          onRetry: onRetry,
        );
      case RatingsFailure.noSession:
        return DriverErrorState(
          title: 'Sign in to see your rating',
          message:
              'We could not tell which driver you are. Signing in again will '
              'reconnect your rating.',
          onRetry: onRetry,
        );
      case RatingsFailure.network:
        return DriverErrorState(
          title: 'No connection',
          message:
              'We cannot reach your ratings right now. Check your mobile data '
              'and try again.',
          onRetry: onRetry,
        );
      case RatingsFailure.unknown:
        return DriverErrorState(
          title: 'Could not load your rating',
          message:
              'Something went wrong on our side. Try again in a moment.',
          onRetry: onRetry,
        );
    }
  }
}

// ── Score ───────────────────────────────────────────────────────────────────

class _ScoreCard extends StatelessWidget {
  final RatingsState ratings;

  const _ScoreCard({required this.ratings});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        // §1.2: `AppColors.primary` is the near-black action colour now. A
        // rating is a positive, brand moment, so it uses brand green rather
        // than turning into a black slab.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandGreen, AppColors.brandGreenDark],
        ),
        borderRadius: AppSpacing.brLg,
      ),
      child: Column(
        children: [
          Text(
            ratings.hasRating ? 'Your rating' : 'Not rated yet',
            style: AppTextStyles.overline.copyWith(
              color: AppColors.textOnDark.withValues(alpha: 0.85),
            ),
          ),
          Gap.sm,
          if (ratings.hasRating)
            Semantics(
              label:
                  '${ratings.formattedRating} out of 5 stars from ${ratings.ratedReviews} ratings',
              child: AnimatedCount(
                value: ratings.overallRating!,
                formatter: (v) => v.toStringAsFixed(1),
                style: AppTextStyles.moneyHero
                    .copyWith(color: AppColors.textOnDark),
              ),
            )
          else
            Icon(
              Icons.auto_awesome_rounded,
              size: 48,
              color: AppColors.textOnDark.withValues(alpha: 0.9),
            ),
          Gap.sm,
          _Stars(
            value: ratings.overallRating ?? 0,
            size: 26,
            color: AppColors.textOnDark,
            emptyColor: AppColors.textOnDark.withValues(alpha: 0.35),
          ),
          Gap.md,
          Text(
            ratings.hasRating
                ? '${ratings.ratedReviews} ${ratings.ratedReviews == 1 ? 'customer has' : 'customers have'} rated you'
                : 'Complete a few deliveries to get your first rating',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textOnDark.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  final double value;
  final double size;
  final Color color;
  final Color emptyColor;

  const _Stars({
    required this.value,
    this.size = 18,
    this.color = AppColors.rating,
    this.emptyColor = AppColors.neutral300,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            value >= i
                ? Icons.star_rounded
                : (value >= i - 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded),
            size: size,
            color: value >= i - 0.5 ? color : emptyColor,
          ),
      ],
    );
  }
}

/// The one-sentence, constructive read on where this driver stands.
class _EncouragementCard extends StatelessWidget {
  final String message;

  const _EncouragementCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.brandGreenSurface,
        borderRadius: AppSpacing.brLg,
        border: Border.all(
          color: AppColors.brandGreen.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.tips_and_updates_outlined,
              size: 20, color: AppColors.brandGreenDark),
          Gap.hMd,
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.body
                  .copyWith(color: AppColors.brandGreenDark),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Distribution ────────────────────────────────────────────────────────────

class _DistributionCard extends StatelessWidget {
  final RatingsState ratings;

  const _DistributionCard({required this.ratings});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppSpacing.cardDecoration(context),
      child: Column(
        children: [
          for (var star = 5; star >= 1; star--) ...[
            if (star < 5) Gap.sm,
            _DistributionRow(
              star: star,
              count: ratings.starCount(star),
              fraction: ratings.starFraction(star),
            ),
          ],
          if (ratings.happyShare != null) ...[
            Gap.lg,
            Divider(height: 1, color: AppColors.borderOf(context)),
            Gap.lg,
            Row(
              children: [
                Icon(Icons.sentiment_very_satisfied_rounded,
                    size: 18, color: AppColors.successOf(context)),
                Gap.hSm,
                Expanded(
                  child: Text(
                    '${(ratings.happyShare! * 100).round()}% of your ratings '
                    'are 4 or 5 stars',
                    style: AppTextStyles.bodyStrong
                        .copyWith(color: AppColors.textPrimary),
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

class _DistributionRow extends StatelessWidget {
  final int star;
  final int count;
  final double fraction;

  const _DistributionRow({
    required this.star,
    required this.count,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$star stars, $count ${count == 1 ? 'rating' : 'ratings'}',
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Row(
              children: [
                Text(
                  '$star',
                  style: AppTextStyles.money
                      .copyWith(color: AppColors.textSecondary, fontSize: 14),
                ),
                const Icon(Icons.star_rounded,
                    size: 12, color: AppColors.rating),
              ],
            ),
          ),
          Gap.hSm,
          Expanded(
            child: ClipRRect(
              borderRadius: AppSpacing.brFull,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction),
                duration: AppMotion.durationOf(context, AppMotion.slow),
                curve: AppMotion.standard,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 10,
                  backgroundColor: AppColors.surfaceMutedOf(context),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    star >= 4
                        ? AppColors.successOf(context)
                        : (star == 3
                            ? AppColors.warningOf(context)
                            : AppColors.errorOf(context)),
                  ),
                ),
              ),
            ),
          ),
          Gap.hSm,
          SizedBox(
            width: 32,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: AppTextStyles.money
                  .copyWith(color: AppColors.textSecondary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Rates ───────────────────────────────────────────────────────────────────

class _RateCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final DriverRate rate;
  final String help;

  const _RateCard({
    required this.icon,
    required this.label,
    required this.rate,
    required this.help,
  });

  @override
  Widget build(BuildContext context) {
    final measured = rate.isMeasured;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppSpacing.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textSecondary),
              Gap.hSm,
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.bodyStrong
                      .copyWith(color: AppColors.textPrimary),
                ),
              ),
              Text(
                rate.formatted,
                style: AppTextStyles.metric.copyWith(
                  color: measured
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ],
          ),
          Gap.md,
          ClipRRect(
            borderRadius: AppSpacing.brFull,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: measured ? rate.fraction : 0),
              duration: AppMotion.durationOf(context, AppMotion.slow),
              curve: AppMotion.standard,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: AppColors.surfaceMutedOf(context),
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.successOf(context),
                ),
              ),
            ),
          ),
          Gap.sm,
          Text(
            measured
                ? rate.basis
                : 'Not enough deliveries to measure this yet — nothing to '
                    'worry about.',
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
          Gap.xs,
          Text(
            help,
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _LifetimeCard extends StatelessWidget {
  final RatingsState ratings;

  const _LifetimeCard({required this.ratings});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppSpacing.cardDecoration(context),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              value: ratings.lifetimeDeliveries,
              label: 'Deliveries all time',
            ),
          ),
          Container(
            width: 1,
            height: 44,
            color: AppColors.borderOf(context),
          ),
          Expanded(
            child: _Stat(
              value: ratings.deliveriesInWindow,
              label: 'In the last ${ratings.windowDays} days',
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final int value;
  final String label;

  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedCount.whole(
          value: value,
          style: AppTextStyles.metric,
        ),
        Gap.xs,
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

// ── Feedback ────────────────────────────────────────────────────────────────

class _FeedbackCard extends StatelessWidget {
  final FeedbackItem item;

  const _FeedbackCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppSpacing.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyStrong
                      .copyWith(color: AppColors.textPrimary),
                ),
              ),
              Gap.hSm,
              _Stars(value: item.rating.toDouble(), size: 16),
            ],
          ),
          if (item.relativeDate.isNotEmpty) ...[
            Gap.xxs,
            Text(
              item.relativeDate,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textTertiary),
            ),
          ],
          if (item.comment.trim().isNotEmpty) ...[
            Gap.md,
            Text(
              item.comment.trim(),
              style:
                  AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (item.tags.isNotEmpty) ...[
            Gap.md,
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final tag in item.tags)
                  StatusChip(
                    label: tag,
                    tone: item.isPositive
                        ? StatusTone.success
                        : StatusTone.neutral,
                    icon: item.isPositive
                        ? Icons.thumb_up_alt_outlined
                        : Icons.chat_bubble_outline_rounded,
                    preserveCase: true,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NoFeedbackYet extends StatelessWidget {
  final bool hasDeliveries;

  const _NoFeedbackYet({required this.hasDeliveries});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: AppSpacing.cardDecoration(context),
      child: Column(
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 32, color: AppColors.textTertiary),
          Gap.md,
          Text(
            hasDeliveries
                ? 'No written feedback yet'
                : 'No feedback yet',
            style: AppTextStyles.onSurface(context, AppTextStyles.h3),
          ),
          Gap.sm,
          Text(
            hasDeliveries
                ? 'Most customers rate without writing anything. When someone '
                    'does leave a comment, it shows up here.'
                : 'Once customers start rating your deliveries, anything they '
                    'write appears here.',
            textAlign: TextAlign.center,
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Chrome ──────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _SectionTitle(this.title, {this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.onSurface(context, AppTextStyles.h2)),
        if (subtitle != null) ...[
          Gap.xxs,
          Text(
            subtitle!,
            style:
                AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

class _InlineRetry extends StatelessWidget {
  final VoidCallback onRetry;

  const _InlineRetry({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceMutedOf(context),
        borderRadius: AppSpacing.brLg,
      ),
      child: Column(
        children: [
          Text(
            'Showing your last known ratings — we could not refresh just now.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textSecondary),
          ),
          Gap.sm,
          DriverTextButton(
            label: 'Try again',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _RatingsSkeleton extends StatelessWidget {
  final double padding;

  const _RatingsSkeleton({required this.padding});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(padding, AppSpacing.lg, padding, padding),
      children: [
        const SkeletonBox(height: 180),
        Gap.md,
        const SkeletonBox(height: 72),
        Gap.section,
        const SkeletonBox(height: 160),
        Gap.section,
        const SkeletonList(count: 3, builder: EarningsRowSkeleton.new),
      ],
    );
  }
}
