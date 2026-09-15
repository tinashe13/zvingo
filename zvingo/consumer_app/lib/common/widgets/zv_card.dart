import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_spacing.dart';
import 'package:consumer_app/core/app_text_styles.dart';

import 'zv_skeletons.dart';
import 'zv_tap_scale.dart';

/// The standard Zvingo card (§5.2): `neutral/0` surface, `radius/lg`,
/// `shadow/sm`, 1px `neutral/200` hairline, 16 padding.
///
/// Pass [onTap] to make it tappable — it gets the §4.3 tap-scale for free.
/// Set [raised] while the card is being dragged or hovered to swap to
/// `shadow/md`. Never stack shadows.
///
/// ```dart
/// ZvCard(
///   onTap: () => context.push('/order/$id'),
///   child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [...]),
/// )
/// ```
class ZvCard extends StatelessWidget {
  const ZvCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.cardPadding),
    this.margin = EdgeInsets.zero,
    this.color = AppColors.surface,
    this.borderColor = AppColors.border,
    this.borderRadius = AppRadius.lgAll,
    this.raised = false,
    this.semanticLabel,
    this.clipBehavior = Clip.antiAlias,
  });

  /// Card content.
  final Widget child;

  /// Tap handler; null renders a static card.
  final VoidCallback? onTap;

  /// Inner padding. Defaults to 16 (§3.1).
  final EdgeInsets padding;

  /// Outer margin.
  final EdgeInsets margin;

  /// Surface colour. Defaults to `neutral/0`.
  final Color color;

  /// Hairline colour. Defaults to `neutral/200`.
  final Color borderColor;

  /// Corner radius. Defaults to `radius/lg`.
  final BorderRadius borderRadius;

  /// Use `shadow/md` instead of `shadow/sm` (dragged / hovered card).
  final bool raised;

  /// Screen-reader label for the whole card when tappable.
  final String? semanticLabel;

  /// Clip behaviour, so edge-to-edge images honour the radius.
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final surface = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor),
        boxShadow: raised ? AppShadows.md : AppShadows.sm,
      ),
      clipBehavior: clipBehavior,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    if (onTap == null) return surface;
    return ZvTapScale(
      onTap: onTap,
      behavior: HitTestBehavior.deferToChild,
      enableFeedback: false,
      semanticLabel: semanticLabel,
      child: surface,
    );
  }
}

/// Aspect ratios allowed on an image-led card (§5.2).
enum ZvImageCardRatio {
  /// 16:9 — restaurants, promos, hero images.
  landscape,

  /// 1:1 — menu items, products.
  square,
}

/// An image-led card (§5.2): the image is edge-to-edge at the top with the
/// card's radius on the top corners only, at **16:9** for restaurants or
/// **1:1** for menu items.
///
/// The image always loads through [ZvNetworkImage], so it has a shimmer
/// placeholder while loading and a branded fallback on error — never a broken
/// image glyph.
///
/// ```dart
/// ZvImageCard(
///   imageUrl: restaurant.bannerUrl,
///   ratio: ZvImageCardRatio.landscape,
///   overlay: ZvBadge.deal(label: '20% off'),
///   onTap: () => context.push('/restaurant/${restaurant.id}'),
///   child: Column(...),   // title, cuisine, ETA
/// )
/// ```
class ZvImageCard extends StatelessWidget {
  const ZvImageCard({
    super.key,
    required this.imageUrl,
    required this.child,
    this.ratio = ZvImageCardRatio.landscape,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.cardPadding),
    this.margin = EdgeInsets.zero,
    this.overlay,
    this.footerOverlay,
    this.fallbackLabel,
    this.dimmed = false,
    this.semanticLabel,
  });

  /// Remote image URL. Null or empty renders the branded fallback.
  final String? imageUrl;

  /// Body of the card, below the image.
  final Widget child;

  /// 16:9 for restaurants, 1:1 for menu items.
  final ZvImageCardRatio ratio;

  /// Tap handler.
  final VoidCallback? onTap;

  /// Padding for [child] only; the image is always edge-to-edge.
  final EdgeInsets padding;

  /// Outer margin.
  final EdgeInsets margin;

  /// Widget pinned to the image's top-left, e.g. a deal badge.
  final Widget? overlay;

  /// Widget pinned to the image's bottom-left, e.g. a "Closed" chip.
  final Widget? footerOverlay;

  /// Text shown in the branded fallback, normally the restaurant name.
  final String? fallbackLabel;

  /// Dims the image, e.g. when the restaurant is closed.
  final bool dimmed;

  /// Screen-reader label for the whole card.
  final String? semanticLabel;

  double get _aspect => ratio == ZvImageCardRatio.landscape ? 16 / 9 : 1;

  @override
  Widget build(BuildContext context) {
    final image = Stack(
      children: [
        Positioned.fill(
          child: ZvNetworkImage(
            url: imageUrl,
            aspectRatio: _aspect,
            fallbackLabel: fallbackLabel,
            borderRadius: BorderRadius.zero,
          ),
        ),
        if (dimmed)
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.neutral900.withValues(alpha: 0.42),
            ),
          ),
        if (overlay != null)
          Positioned(
            top: AppSpacing.sm,
            left: AppSpacing.sm,
            child: overlay!,
          ),
        if (footerOverlay != null)
          Positioned(
            bottom: AppSpacing.sm,
            left: AppSpacing.sm,
            child: footerOverlay!,
          ),
      ],
    );

    return ZvCard(
      onTap: onTap,
      margin: margin,
      padding: EdgeInsets.zero,
      semanticLabel: semanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(aspectRatio: _aspect, child: image),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Every remote image in the app goes through this widget (§5.2).
///
/// * loading → a shimmer block the exact size of the final image
/// * error / missing URL → the **branded fallback**: a `brand/green-surface`
///   panel with the Zvingo mark and an optional label. Never a broken-image
///   icon.
///
/// ```dart
/// ZvNetworkImage(
///   url: item.imageUrl,
///   aspectRatio: 1,
///   fallbackLabel: item.name,
///   borderRadius: AppRadius.mdAll,
/// )
/// ```
class ZvNetworkImage extends StatelessWidget {
  const ZvNetworkImage({
    super.key,
    required this.url,
    this.aspectRatio,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.borderRadius = AppRadius.mdAll,
    this.fallbackLabel,
    this.fallbackIcon = Icons.storefront_rounded,
  });

  /// Remote URL. Null / empty goes straight to the branded fallback.
  final String? url;

  /// Constrain to this ratio (16/9, 1). Ignored when [height] is given.
  final double? aspectRatio;

  /// Fixed height, when not using [aspectRatio].
  final double? height;

  /// Fixed width.
  final double? width;

  /// How the image fills its box.
  final BoxFit fit;

  /// Corner radius applied to image, placeholder and fallback alike.
  final BorderRadius borderRadius;

  /// Label drawn in the fallback, normally the item or restaurant name.
  final String? fallbackLabel;

  /// Glyph drawn in the fallback.
  final IconData fallbackIcon;

  Widget _wrap(Widget child) {
    Widget result = ClipRRect(borderRadius: borderRadius, child: child);
    if (aspectRatio != null && height == null) {
      result = AspectRatio(aspectRatio: aspectRatio!, child: result);
    }
    if (height != null || width != null) {
      result = SizedBox(height: height, width: width, child: result);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final source = url?.trim();
    if (source == null || source.isEmpty) {
      return _wrap(_ZvImageFallback(label: fallbackLabel, icon: fallbackIcon));
    }

    return _wrap(
      CachedNetworkImage(
        imageUrl: source,
        fit: fit,
        fadeInDuration: const Duration(milliseconds: 180),
        placeholder: (context, _) => const ZvShimmer(
          child: DecoratedBox(
            decoration: BoxDecoration(color: AppColors.shimmerBase),
            child: SizedBox.expand(),
          ),
        ),
        errorWidget: (context, _, __) =>
            _ZvImageFallback(label: fallbackLabel, icon: fallbackIcon),
      ),
    );
  }
}

/// The branded image fallback. Private: always reach it via [ZvNetworkImage].
class _ZvImageFallback extends StatelessWidget {
  const _ZvImageFallback({this.label, required this.icon});

  final String? label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.brandGreenSurface),
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 72;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: compact ? 20 : 28,
                  color: AppColors.brandGreen,
                ),
                if (!compact && label != null && label!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Text(
                      label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.brandGreenDark,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
