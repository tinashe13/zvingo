import 'package:flutter/material.dart';

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_spacing.dart';
import 'package:consumer_app/core/app_text_styles.dart';

/// Semantic tones for [ZvStatusChip] and [ZvBadge] (§1.4).
///
/// Colour alone never carries meaning — every tone ships with an icon and a
/// label, because ~8% of men are colourblind (§1.5).
enum ZvTone {
  /// Quiet metadata: `neutral/100` on `neutral/600`.
  neutral,

  /// Delivered, paid, online, confirmed.
  success,

  /// Waiting, delayed, action needed soon.
  warning,

  /// Failed, cancelled, destructive.
  error,

  /// Neutral informational.
  info,

  /// Discounts, promo tags, price drops.
  deal,

  /// Brand accent — "new", highlights. Use sparingly.
  brand,
}

extension ZvToneColors on ZvTone {
  /// Foreground (text + icon) colour for this tone.
  Color get foreground {
    switch (this) {
      case ZvTone.neutral:
        return AppColors.textSecondary;
      case ZvTone.success:
        return AppColors.brandGreenDark;
      case ZvTone.warning:
        return AppColors.warning;
      case ZvTone.error:
        return AppColors.error;
      case ZvTone.info:
        return AppColors.info;
      case ZvTone.deal:
        return AppColors.deal;
      case ZvTone.brand:
        return AppColors.textPrimary;
    }
  }

  /// Tinted surface colour for this tone.
  Color get surface {
    switch (this) {
      case ZvTone.neutral:
        return AppColors.surfaceMuted;
      case ZvTone.success:
        return AppColors.brandGreenSurface;
      case ZvTone.warning:
        return AppColors.warningSurface;
      case ZvTone.error:
        return AppColors.errorSurface;
      case ZvTone.info:
        return AppColors.infoSurface;
      case ZvTone.deal:
        return AppColors.dealSurface;
      case ZvTone.brand:
        return AppColors.brandLimeSurface;
    }
  }

  /// Default glyph for this tone, used when none is supplied.
  IconData get defaultIcon {
    switch (this) {
      case ZvTone.neutral:
        return Icons.circle_outlined;
      case ZvTone.success:
        return Icons.check_circle_rounded;
      case ZvTone.warning:
        return Icons.schedule_rounded;
      case ZvTone.error:
        return Icons.cancel_rounded;
      case ZvTone.info:
        return Icons.info_rounded;
      case ZvTone.deal:
        return Icons.local_offer_rounded;
      case ZvTone.brand:
        return Icons.auto_awesome_rounded;
    }
  }
}

/// A status pill: semantic colour **plus** an icon **plus** a label (§1.5).
///
/// Use it for order state, store open/closed, payment state — anything whose
/// meaning the user must read at a glance.
///
/// ```dart
/// ZvStatusChip(tone: ZvTone.warning, label: 'Preparing')
/// ZvStatusChip.orderState('PICKED_UP')          // "On the way", info tone
/// ```
class ZvStatusChip extends StatelessWidget {
  const ZvStatusChip({
    super.key,
    required this.label,
    this.tone = ZvTone.neutral,
    this.icon,
    this.compact = false,
    this.uppercase = true,
  });

  /// Short, human-readable state, e.g. "On the way".
  final String label;

  /// Semantic tone (§1.4).
  final ZvTone tone;

  /// Glyph. Falls back to the tone's [ZvToneColors.defaultIcon].
  final IconData? icon;

  /// Tighter padding for dense rows.
  final bool compact;

  /// Render the label in `overline` UPPERCASE (the default) or sentence case.
  final bool uppercase;

  /// Maps a backend `OrderState` value onto a customer-facing chip.
  ///
  /// Accepted values: `CREATED`, `OFFERED`, `ACCEPTED`,
  /// `ARRIVED_AT_MERCHANT`, `READY_FOR_PICKUP`, `PICKED_UP`,
  /// `ARRIVED_AT_CUSTOMER`, `DELIVERED`, `CANCELLED` (case-insensitive).
  factory ZvStatusChip.orderState(String state,
      {Key? key, bool compact = false}) {
    final normalized = state.trim().toUpperCase();
    switch (normalized) {
      case 'CREATED':
        return ZvStatusChip(
          key: key,
          compact: compact,
          tone: ZvTone.warning,
          icon: Icons.receipt_long_rounded,
          label: 'Order placed',
        );
      case 'OFFERED':
        return ZvStatusChip(
          key: key,
          compact: compact,
          tone: ZvTone.warning,
          icon: Icons.person_search_rounded,
          label: 'Finding a driver',
        );
      case 'ACCEPTED':
        return ZvStatusChip(
          key: key,
          compact: compact,
          tone: ZvTone.info,
          icon: Icons.restaurant_rounded,
          label: 'Preparing',
        );
      case 'ARRIVED_AT_MERCHANT':
        return ZvStatusChip(
          key: key,
          compact: compact,
          tone: ZvTone.info,
          icon: Icons.storefront_rounded,
          label: 'Driver at restaurant',
        );
      case 'READY_FOR_PICKUP':
        return ZvStatusChip(
          key: key,
          compact: compact,
          tone: ZvTone.info,
          icon: Icons.shopping_bag_rounded,
          label: 'Ready for pickup',
        );
      case 'PICKED_UP':
        return ZvStatusChip(
          key: key,
          compact: compact,
          tone: ZvTone.info,
          icon: Icons.directions_bike_rounded,
          label: 'On the way',
        );
      case 'ARRIVED_AT_CUSTOMER':
        return ZvStatusChip(
          key: key,
          compact: compact,
          tone: ZvTone.success,
          icon: Icons.location_on_rounded,
          label: 'Driver has arrived',
        );
      case 'DELIVERED':
        return ZvStatusChip(
          key: key,
          compact: compact,
          tone: ZvTone.success,
          icon: Icons.check_circle_rounded,
          label: 'Delivered',
        );
      case 'CANCELLED':
        return ZvStatusChip(
          key: key,
          compact: compact,
          tone: ZvTone.error,
          icon: Icons.cancel_rounded,
          label: 'Cancelled',
        );
      default:
        return ZvStatusChip(
          key: key,
          compact: compact,
          tone: ZvTone.neutral,
          icon: Icons.info_outline_rounded,
          label: 'In progress',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = tone.foreground;
    final glyph = icon ?? tone.defaultIcon;
    final text = uppercase ? label.toUpperCase() : label;

    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.xs : AppSpacing.sm - 2,
          vertical: compact ? 3 : AppSpacing.xxs + 1,
        ),
        decoration: BoxDecoration(
          color: tone.surface,
          borderRadius: AppRadius.smAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(glyph, size: compact ? 12 : 13, color: fg),
            SizedBox(width: compact ? 3 : AppSpacing.xxs + 1),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: uppercase
                    ? AppTextStyles.overline.copyWith(color: fg)
                    : AppTextStyles.caption.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small solid badge for an overlay or an inline marker — "20% OFF",
/// "NEW", "CLOSED". Higher contrast than [ZvStatusChip] so it reads on top of
/// photography.
///
/// ```dart
/// ZvBadge.deal(label: '20% off')
/// ZvBadge(label: 'Closed', tone: ZvTone.neutral, icon: Icons.bedtime_rounded)
/// ```
class ZvBadge extends StatelessWidget {
  const ZvBadge({
    super.key,
    required this.label,
    this.tone = ZvTone.brand,
    this.icon,
  });

  /// Promo / discount badge in the `deal` tone.
  const ZvBadge.deal({super.key, required this.label})
      : tone = ZvTone.deal,
        icon = Icons.local_offer_rounded;

  /// "New" badge in the brand accent.
  const ZvBadge.brandNew({super.key, this.label = 'New'})
      : tone = ZvTone.brand,
        icon = Icons.auto_awesome_rounded;

  /// Badge text. Keep it to one or two words.
  final String label;

  /// Semantic tone.
  final ZvTone tone;

  /// Optional glyph. Omit for a text-only badge.
  final IconData? icon;

  Color get _fill {
    switch (tone) {
      case ZvTone.neutral:
        return AppColors.neutral800;
      case ZvTone.success:
        return AppColors.brandGreen;
      case ZvTone.warning:
        return AppColors.warning;
      case ZvTone.error:
        return AppColors.error;
      case ZvTone.info:
        return AppColors.info;
      case ZvTone.deal:
        return AppColors.deal;
      case ZvTone.brand:
        return AppColors.brandLime;
    }
  }

  Color get _ink =>
      tone == ZvTone.brand ? AppColors.textPrimary : AppColors.textOnDark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs + 1,
        ),
        decoration: BoxDecoration(
          color: _fill,
          borderRadius: AppRadius.smAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: _ink),
              const SizedBox(width: 3),
            ],
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.overline.copyWith(color: _ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single-line metadata row: star rating, ETA, distance, delivery fee.
/// Each entry pairs an icon with a value, separated by a hairline dot.
///
/// ```dart
/// ZvMetaRow(items: [
///   ZvMetaItem(icon: Icons.star_rounded, label: '4.6', tint: AppColors.rating),
///   ZvMetaItem(icon: Icons.schedule_rounded, label: '25–35 min'),
///   ZvMetaItem(icon: Icons.pedal_bike_rounded, label: r'$1.50'),
/// ])
/// ```
class ZvMetaRow extends StatelessWidget {
  const ZvMetaRow({super.key, required this.items});

  /// Metadata entries, in reading order.
  final List<ZvMetaItem> items;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        children.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Text('·', style: AppTextStyles.caption),
          ),
        );
      }
      children.add(items[i]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// One icon + value pair inside a [ZvMetaRow].
class ZvMetaItem extends StatelessWidget {
  const ZvMetaItem({
    super.key,
    required this.icon,
    required this.label,
    this.tint,
    this.tabularFigures = true,
  });

  /// Metadata glyph.
  final IconData icon;

  /// Metadata value, e.g. "25–35 min".
  final String label;

  /// Overrides the icon colour, e.g. `AppColors.rating` for a star.
  final Color? tint;

  /// Keeps digits from jittering as the value updates.
  final bool tabularFigures;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: tint ?? AppColors.textSecondary),
        const SizedBox(width: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tabularFigures ? AppTextStyles.time : AppTextStyles.caption,
        ),
      ],
    );
  }
}
