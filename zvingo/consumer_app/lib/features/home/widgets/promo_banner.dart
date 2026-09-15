import 'dart:async';

import 'package:consumer_app/common/zvingo_ui.dart';
import 'package:consumer_app/features/home/widgets/restaurant_card.dart'
    show zvTextScale;
import 'package:consumer_app/features/offers/offers_provider.dart';
import 'package:consumer_app/features/restaurant/restaurant_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Promotional carousel on home.
///
/// Auto-advances one page every 6s, pauses while the user is dragging, and
/// stops entirely when the platform asks for reduced motion. Renders nothing
/// at all when there is no live promotion — an empty promo strip is noise.
class PromoBanner extends ConsumerStatefulWidget {
  const PromoBanner({super.key});

  @override
  ConsumerState<PromoBanner> createState() => _PromoBannerState();
}

class _PromoBannerState extends ConsumerState<PromoBanner> {
  static const Duration _dwell = Duration(seconds: 6);

  /// Card padding + icon column, plus five text rows that grow with the
  /// viewer's font size.
  static double _heightFor(BuildContext context) =>
      44 + 112 * zvTextScale(context);

  final PageController _controller = PageController(viewportFraction: 0.88);
  Timer? _autoplay;
  int _page = 0;
  int _count = 0;

  @override
  void dispose() {
    _autoplay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _syncAutoplay(int count) {
    _count = count;
    final shouldRun = count > 1 && !context.reducedMotion;
    if (shouldRun && _autoplay == null) {
      _autoplay = Timer.periodic(_dwell, (_) => _advance());
    } else if (!shouldRun) {
      _autoplay?.cancel();
      _autoplay = null;
    }
  }

  void _advance() {
    if (!mounted || _count < 2 || !_controller.hasClients) return;
    final next = (_page + 1) % _count;
    _controller.animateToPage(
      next,
      duration: context.motion(AppMotion.slow),
      curve: AppMotion.standard,
    );
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Promo code $code copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final promosAsync = ref.watch(activePromotionsProvider);

    final height = _heightFor(context);

    return promosAsync.when(
      loading: () => _PromoSkeleton(height: height),
      // A failed promo fetch must never block the food feed; the Offers tab
      // carries the retry affordance for this data.
      error: (_, __) => const SizedBox.shrink(),
      data: (promos) {
        if (promos.isEmpty) return const SizedBox.shrink();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncAutoplay(promos.length);
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ZvSectionHeader(
              title: 'Deals for you',
              subtitle: promos.length == 1
                  ? '1 offer live right now'
                  : '${promos.length} offers live right now',
              actionLabel: 'All offers',
              onAction: () => context.push('/offers'),
            ),
            SizedBox(
              height: height,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification &&
                      notification.dragDetails != null) {
                    _autoplay?.cancel();
                    _autoplay = null;
                  } else if (notification is ScrollEndNotification) {
                    _syncAutoplay(promos.length);
                  }
                  return false;
                },
                child: PageView.builder(
                  controller: _controller,
                  itemCount: promos.length,
                  onPageChanged: (index) => setState(() => _page = index),
                  padEnds: false,
                  itemBuilder: (context, index) {
                    final promo = promos[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        left: index == 0 ? AppSpacing.md : AppSpacing.xs,
                        right: index == promos.length - 1
                            ? AppSpacing.md
                            : AppSpacing.xs,
                        bottom: AppSpacing.xs,
                      ),
                      child: ZvEntrance(
                        index: index,
                        child: _PromoTile(
                          promo: promo,
                          onTap: () => promo.code == null
                              ? context.push('/offers')
                              : _copyCode(promo.code!),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (promos.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Center(
                  child: _PageDots(count: promos.length, active: _page),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Two promo-shaped blocks — the same size as the real carousel cards.
class _PromoSkeleton extends StatelessWidget {
  const _PromoSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        itemCount: 2,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, __) => ZvShimmer(
          child: ZvSkeletonBox(
            height: height - AppSpacing.xs,
            width: 280,
            radius: AppRadius.lg,
          ),
        ),
      ),
    );
  }
}

class _PromoTile extends StatelessWidget {
  const _PromoTile({required this.promo, required this.onTap});

  final Promotion promo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = promo.foreground;
    final condition = promo.conditionLabel;

    return ZvTapScale(
      onTap: onTap,
      semanticLabel: '${promo.title}. ${promo.subtitle}. '
          '${promo.code != null ? 'Code ${promo.code}, tap to copy' : 'See all offers'}',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: promo.gradient,
          ),
          borderRadius: AppRadius.lgAll,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    promo.valueLabel.toUpperCase(),
                    style: AppTextStyles.overline
                        .copyWith(color: ink.withValues(alpha: 0.78)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    promo.title,
                    style: AppTextStyles.h3.copyWith(color: ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    condition ?? promo.subtitle,
                    style: AppTextStyles.caption
                        .copyWith(color: ink.withValues(alpha: 0.78)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (promo.code != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: ink.withValues(alpha: 0.14),
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_rounded, size: 12, color: ink),
                          const SizedBox(width: AppSpacing.xxs),
                          Flexible(
                            child: Text(
                              promo.code!,
                              style: AppTextStyles.overline.copyWith(color: ink),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: ink.withValues(alpha: 0.14),
                borderRadius: AppRadius.mdAll,
              ),
              child: Icon(promo.iconData, color: ink, size: 24),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(count, (index) {
        final selected = index == active;
        return AnimatedContainer(
          duration: context.motion(AppMotion.fast),
          curve: AppMotion.standard,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          height: 6,
          width: selected ? 18 : 6,
          decoration: BoxDecoration(
            color: selected ? AppColors.actionDefault : AppColors.neutral300,
            borderRadius: AppRadius.fullAll,
          ),
        );
      }),
    );
  }
}
