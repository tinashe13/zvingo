import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:consumer_app/common/zvingo_ui.dart';

/// Shared chrome for the three signed-out screens (sign in, create account,
/// reset password).
///
/// A short brand header, then the form. The header shrinks out of the way when
/// the keyboard is up, so the field being typed into is never pushed off screen
/// on a small phone.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.eyebrow,
    this.subtitle,
    this.showBack = false,
    this.footer,
  });

  /// Screen title (`h1`). Names where the user is.
  final String title;

  /// Form body.
  final Widget child;

  /// Small uppercase line above the title.
  final String? eyebrow;

  /// One sentence explaining what this screen is for.
  final String? subtitle;

  /// Back affordance in the header (§5.4). Sign-in is the root, so it has none.
  final bool showBack;

  /// Pinned bottom content, e.g. a legal line.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSize(
              duration: context.motion(AppMotion.base),
              curve: context.motionCurve(AppMotion.standard),
              alignment: Alignment.topCenter,
              child: keyboardUp
                  ? const SizedBox(height: AppSpacing.xs)
                  : _Header(showBack: showBack),
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: AppSpacing.xxs,
                        ),
                        decoration: const BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: AppRadius.fullAll,
                        ),
                        child: Text(
                          eyebrow!,
                          style: AppTextStyles.overline
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    Text(title, style: AppTextStyles.h1),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle!,
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    child,
                  ],
                ),
              ),
            ),
            if (footer != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.md + MediaQuery.paddingOf(context).bottom,
                ),
                child: footer!,
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.showBack});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.actionDefault,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(AppRadius.xl),
                  bottomRight: Radius.circular(AppRadius.xl),
                ),
              ),
            ),
          ),
          Positioned(
            right: -30,
            top: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: const BoxDecoration(
                color: AppColors.actionHover,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.xl,
            bottom: AppSpacing.xl,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.brandLime,
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: AppColors.neutral900,
                    size: 26,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'zvingo',
                  style: AppTextStyles.h2.copyWith(color: AppColors.textOnDark),
                ),
              ],
            ),
          ),
          if (showBack)
            Positioned(
              left: AppSpacing.xs,
              top: AppSpacing.xs,
              child: ZvIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                background: AppColors.actionHover,
                foreground: AppColors.textOnDark,
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else if (GoRouter.of(context).canPop()) {
                    GoRouter.of(context).pop();
                  } else {
                    GoRouter.of(context).go('/login');
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
