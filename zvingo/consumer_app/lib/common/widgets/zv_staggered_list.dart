import 'package:flutter/material.dart';

import 'package:consumer_app/core/app_motion.dart';
import 'package:consumer_app/core/app_spacing.dart';

/// Applies the §4.3 list entrance to a set of children: each fades in and
/// rises 12px over `motion/base` with `ease/enter`, staggered by **40ms**, and
/// the stagger stops accumulating after the 8th item.
///
/// Under reduced motion every child cross-fades together with no movement.
///
/// ```dart
/// ZvStaggeredList(
///   gap: AppSpacing.listGap,
///   children: [
///     for (final r in restaurants) RestaurantCard(restaurant: r),
///   ],
/// )
/// ```
class ZvStaggeredList extends StatelessWidget {
  const ZvStaggeredList({
    super.key,
    required this.children,
    this.gap = AppSpacing.listGap,
    this.padding = EdgeInsets.zero,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.enabled = true,
    this.startIndex = 0,
  });

  /// The list items, in order.
  final List<Widget> children;

  /// Vertical gap between items. Defaults to the 12px list gap (§3.1).
  final double gap;

  /// Padding around the whole column.
  final EdgeInsets padding;

  /// Cross-axis alignment of the column.
  final CrossAxisAlignment crossAxisAlignment;

  /// Set false to render instantly, e.g. when the list is already on screen
  /// and you are only appending.
  final bool enabled;

  /// Offset added to each child's stagger index — use it when this column
  /// follows another staggered block on the same screen.
  final int startIndex;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(children.length, (i) {
          return Padding(
            padding:
                EdgeInsets.only(bottom: i == children.length - 1 ? 0 : gap),
            child: ZvEntrance(
              index: startIndex + i,
              enabled: enabled,
              child: children[i],
            ),
          );
        }),
      ),
    );
  }
}

/// `ListView.builder` with the §4.3 entrance stagger applied to each row.
/// Use this instead of [ZvStaggeredList] when the list is long enough that
/// building every child up front would be wasteful.
///
/// ```dart
/// ZvStaggeredListView.builder(
///   itemCount: orders.length,
///   padding: const EdgeInsets.all(AppSpacing.md),
///   itemBuilder: (context, i) => OrderCard(order: orders[i]),
/// )
/// ```
class ZvStaggeredListView extends StatelessWidget {
  const ZvStaggeredListView.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = AppSpacing.listGap,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.physics,
    this.shrinkWrap = false,
    this.enabled = true,
  });

  /// Number of rows.
  final int itemCount;

  /// Builds one row.
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Vertical gap between rows.
  final double gap;

  /// Padding around the list.
  final EdgeInsets padding;

  /// Scroll controller.
  final ScrollController? controller;

  /// Scroll physics.
  final ScrollPhysics? physics;

  /// Shrink-wrap the list (only inside another scrollable).
  final bool shrinkWrap;

  /// Set false to skip the entrance animation.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: controller,
      physics: physics,
      shrinkWrap: shrinkWrap,
      padding: padding,
      itemCount: itemCount,
      separatorBuilder: (_, __) => SizedBox(height: gap),
      itemBuilder: (context, index) => ZvEntrance(
        index: index,
        enabled: enabled,
        child: itemBuilder(context, index),
      ),
    );
  }
}

/// A sliver version of the entrance stagger, for `CustomScrollView` screens.
///
/// ```dart
/// CustomScrollView(slivers: [
///   const SliverAppBar(...),
///   ZvStaggeredSliverList(
///     itemCount: items.length,
///     itemBuilder: (context, i) => MenuItemRow(item: items[i]),
///   ),
/// ])
/// ```
class ZvStaggeredSliverList extends StatelessWidget {
  const ZvStaggeredSliverList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = AppSpacing.listGap,
    this.enabled = true,
  });

  /// Number of rows.
  final int itemCount;

  /// Builds one row.
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Vertical gap between rows.
  final double gap;

  /// Set false to skip the entrance animation.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SliverList.separated(
      itemCount: itemCount,
      separatorBuilder: (_, __) => SizedBox(height: gap),
      itemBuilder: (context, index) => ZvEntrance(
        index: index,
        enabled: enabled,
        child: itemBuilder(context, index),
      ),
    );
  }
}
