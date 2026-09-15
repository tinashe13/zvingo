import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:consumer_app/core/app_colors.dart';
import 'package:consumer_app/core/app_spacing.dart';
import 'package:consumer_app/core/app_text_styles.dart';

/// The scaffold every non-top-level screen should use.
///
/// It guarantees the two "stupid-easy navigation" rules of §5.4: a **back
/// affordance in the top-left** and a **title naming where you are**. Swipe
/// back is never the only way out.
///
/// ```dart
/// ZvScreen(
///   title: 'Checkout',
///   subtitle: 'Kudya Kitchen · 25–35 min',
///   actions: [ZvIconButton(icon: Icons.help_outline, tooltip: 'Help', onPressed: _help)],
///   footer: ZvStickyFooter(child: ZvButton.primary(label: 'Pay now', onPressed: _pay)),
///   child: ListView(...),
/// )
/// ```
class ZvScreen extends StatelessWidget {
  const ZvScreen({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
    this.footer,
    this.banner,
    this.showBack = true,
    this.onBack,
    this.backTooltip = 'Back',
    this.fallbackRoute = '/home',
    this.backgroundColor = AppColors.background,
    this.appBarColor = AppColors.surface,
    this.centerTitle = false,
    this.bottomBorder = true,
    this.safeAreaBottom = true,
    this.floatingActionButton,
  });

  /// Names where the user is. Required — a titleless screen is a defect.
  final String title;

  /// Screen body.
  final Widget child;

  /// Optional one-line context under the title, e.g. the restaurant name.
  final String? subtitle;

  /// App-bar actions on the right.
  final List<Widget>? actions;

  /// Pinned footer — normally a `ZvStickyFooter` with the one primary action.
  final Widget? footer;

  /// Full-width strip directly under the app bar, e.g. a `ZvOfflineBanner` or
  /// a `ZvOrderBanner`.
  final Widget? banner;

  /// Show the back affordance. Only top-level tabs set this false.
  final bool showBack;

  /// Custom back handler. Defaults to pop, falling back to [fallbackRoute]
  /// when there is nothing to pop (e.g. a deep link opened cold).
  final VoidCallback? onBack;

  /// Accessible name of the back affordance.
  final String backTooltip;

  /// Where to go when there is no route to pop back to.
  final String fallbackRoute;

  /// Scaffold background.
  final Color backgroundColor;

  /// App-bar background.
  final Color appBarColor;

  /// Centre the title (rare — default is leading-aligned).
  final bool centerTitle;

  /// Draw the hairline under the app bar.
  final bool bottomBorder;

  /// Apply bottom safe-area padding to [child] when there is no [footer].
  final bool safeAreaBottom;

  /// Optional FAB.
  final Widget? floatingActionButton;

  void _handleBack(BuildContext context) {
    if (onBack != null) {
      onBack!();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    if (GoRouter.of(context).canPop()) {
      GoRouter.of(context).pop();
      return;
    }
    GoRouter.of(context).go(fallbackRoute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      floatingActionButton: floatingActionButton,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(subtitle == null ? 56 : 68),
        child: Container(
          decoration: BoxDecoration(
            color: appBarColor,
            border: bottomBorder
                ? const Border(
                    bottom: BorderSide(color: AppColors.divider),
                  )
                : null,
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: subtitle == null ? 56 : 68,
              child: Row(
                children: [
                  if (showBack)
                    _BackAffordance(
                      tooltip: backTooltip,
                      onPressed: () => _handleBack(context),
                    )
                  else
                    const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: centerTitle
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.h2,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption,
                          ),
                      ],
                    ),
                  ),
                  if (actions != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    ...actions!,
                    const SizedBox(width: AppSpacing.xs),
                  ] else
                    const SizedBox(width: AppSpacing.md),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (banner != null) banner!,
          Expanded(
            child: SafeArea(
              top: false,
              bottom: safeAreaBottom && footer == null,
              child: child,
            ),
          ),
        ],
      ),
      bottomNavigationBar: footer,
    );
  }
}

/// Safety net applied by `router.dart` to every non-top-level route.
///
/// §5.4 requires that every non-top-level screen shows a back affordance in
/// the top-left and a title naming where you are. Screens should get that by
/// using [ZvScreen] (or a `Scaffold` with an `AppBar`). This guard checks the
/// route's subtree after it settles and, if it finds no chrome at all, floats
/// a labelled back pill over the top-left corner so the route can never
/// become a dead end.
///
/// It is a backstop, not a licence to skip [ZvScreen] — the pill has no title.
class ZvBackGuard extends StatefulWidget {
  const ZvBackGuard({
    super.key,
    required this.child,
    this.title,
    this.fallbackRoute = '/home',
    this.force,
  });

  /// The routed screen.
  final Widget child;

  /// Route title, used as the pill's accessible name.
  final String? title;

  /// Where to go when there is nothing to pop.
  final String fallbackRoute;

  /// Skip detection: `true` always shows the pill, `false` never does.
  final bool? force;

  @override
  State<ZvBackGuard> createState() => _ZvBackGuardState();
}

class _ZvBackGuardState extends State<ZvBackGuard> {
  final GlobalKey _childKey = GlobalKey();
  bool _needsChrome = false;

  @override
  void initState() {
    super.initState();
    if (widget.force != null) {
      _needsChrome = widget.force!;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    // Second pass, for screens that only build their app bar once data
    // arrives. After this the answer is final.
    Future<void>.delayed(const Duration(milliseconds: 600), _check);
  }

  void _check() {
    if (!mounted || widget.force != null) return;
    final context = _childKey.currentContext;
    if (context == null) return;

    var found = false;
    void visit(Element element) {
      if (found) return;
      final candidate = element.widget;
      if (candidate is ZvScreen ||
          candidate is AppBar ||
          candidate is SliverAppBar ||
          candidate is BackButton ||
          candidate is CloseButton ||
          (candidate is Scaffold && candidate.appBar != null)) {
        found = true;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    if (mounted && _needsChrome == found) {
      setState(() => _needsChrome = !found);
    }
  }

  void _back() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    if (GoRouter.of(context).canPop()) {
      GoRouter.of(context).pop();
      return;
    }
    GoRouter.of(context).go(widget.fallbackRoute);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        KeyedSubtree(key: _childKey, child: widget.child),
        if (_needsChrome)
          Positioned(
            top: MediaQuery.paddingOf(context).top + AppSpacing.xs,
            left: AppSpacing.sm,
            child: Semantics(
              button: true,
              label:
                  widget.title == null ? 'Back' : 'Back from ${widget.title}',
              child: Tooltip(
                message: 'Back',
                child: Material(
                  color: AppColors.surface,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _back,
                    child: const SizedBox(
                      height: AppSpacing.minTapTarget,
                      width: AppSpacing.minTapTarget,
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 22,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BackAffordance extends StatelessWidget {
  const _BackAffordance({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkResponse(
          onTap: onPressed,
          radius: 26,
          child: const SizedBox(
            height: AppSpacing.minTapTarget,
            width: AppSpacing.minTapTarget,
            child: Icon(
              Icons.arrow_back_rounded,
              size: 22,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
