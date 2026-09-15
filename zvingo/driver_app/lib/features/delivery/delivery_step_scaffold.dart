import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../core/app_text_styles.dart';
import '../../core/router.dart';
import '../../models/delivery_state.dart';
import '../../providers/delivery_provider.dart';
import '../../widgets/widgets.dart';

/// The frame every delivery step shares.
///
/// A driver glances at this screen for about a second, on a bike, in sunlight.
/// The frame therefore answers the same three questions in the same three
/// places every single time, so the answers are found by muscle memory rather
/// than by reading:
///
/// | Question | Where |
/// |---|---|
/// | Where am I going? | the app-bar title, largest text at the top |
/// | How far through am I? | the step rail directly under it |
/// | What is the one action? | the sticky footer, the only filled control |
///
/// It also carries the two things that stop a driver getting stranded:
/// a **Dash** action that returns to the map without abandoning the job (the
/// shell's active-delivery bar brings them straight back), and a single place
/// where the provider's one-shot `error` / `notice` are surfaced as snackbars,
/// so no step has to remember to do it.
class DeliveryStepScaffold extends ConsumerStatefulWidget {
  /// Where the driver is going, in the imperative. The largest text on screen.
  final String title;

  /// One line of context under the title — normally the order id.
  final String? subtitle;

  /// Which node of the rail to light up.
  final DeliveryState state;

  /// The body.
  final Widget child;

  /// The single action. Usually a [DriverSlideToConfirm].
  final Widget footer;

  /// Optional context above [footer] — a total to collect, a warning.
  final Widget? supporting;

  /// True when [child] should fill the remaining height itself, e.g. a map.
  /// False wraps it in a scroll view with screen padding, so it survives 200%
  /// text scale.
  final bool fillBody;

  const DeliveryStepScaffold({
    super.key,
    required this.title,
    required this.state,
    required this.child,
    required this.footer,
    this.subtitle,
    this.supporting,
    this.fillBody = false,
  });

  @override
  ConsumerState<DeliveryStepScaffold> createState() =>
      _DeliveryStepScaffoldState();
}

class _DeliveryStepScaffoldState extends ConsumerState<DeliveryStepScaffold> {
  @override
  Widget build(BuildContext context) {
    // Errors and notices are one-shot values on the provider. Surfacing them
    // here means every step gets them without a line of its own, and a message
    // raised on one step is still seen if the driver has already moved on.
    ref.listen<DeliveryFlowState>(deliveryProvider, (previous, next) {
      final error = next.error;
      final notice = next.notice;
      if (error == null && notice == null) return;
      if (error != null && error != previous?.error) {
        DriverSnack.error(context, error);
      } else if (notice != null && notice != previous?.notice) {
        DriverSnack.show(context, notice, icon: Icons.info_outline_rounded);
      }
      ref.read(deliveryProvider.notifier).clearMessages();
    });

    final body = widget.fillBody
        ? widget.child
        : SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenPaddingOf(context),
              AppSpacing.lg,
              AppSpacing.screenPaddingOf(context),
              AppSpacing.xxl,
            ),
            child: widget.child,
          );

    return Scaffold(
      appBar: DriverAppBar(
        title: widget.title,
        subtitle: widget.subtitle,
        // There is no meaningful "back" mid-delivery: the previous step has
        // already been reported to the server. "Dash" is the honest escape —
        // it goes to the map, and the shell's active-delivery bar brings the
        // driver straight back to this exact step.
        showBack: false,
        actions: [
          DriverIconButton(
            icon: Icons.explore_outlined,
            tooltip: 'Back to dash',
            onPressed: () => context.go(routeHome),
          ),
        ],
        bottom: _StepRail(state: widget.state),
      ),
      body: SafeArea(top: false, child: body),
      bottomNavigationBar: DriverActionFooter(
        supporting: widget.supporting,
        child: widget.footer,
      ),
    );
  }
}

/// The step rail, sized so it can hang off an app bar.
class _StepRail extends StatelessWidget implements PreferredSizeWidget {
  final DeliveryState state;

  const _StepRail({required this.state});

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: DeliveryStepIndicator(currentState: state),
    );
  }
}

/// A labelled fact inside a delivery card — "Order", "Collect", "Distance".
class DeliveryFactRow extends StatelessWidget {
  final String label;
  final String value;

  /// Emphasised values (money to collect) use the money token and the full
  /// text colour; everything else stays quiet.
  final bool emphasise;

  const DeliveryFactRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.onSurface(context, AppTextStyles.caption),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTextStyles.onSurface(
                context,
                emphasise ? AppTextStyles.money : AppTextStyles.bodyStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The standard card used by the non-map steps: a headline, an explanation,
/// and any number of facts.
class DeliveryInfoCard extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String headline;
  final String explanation;
  final List<Widget> children;

  const DeliveryInfoCard({
    super.key,
    required this.icon,
    required this.headline,
    required this.explanation,
    this.iconColor,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    final tint = iconColor ?? AppColors.brandGreen;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: AppSpacing.cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: AppSpacing.brMd,
            ),
            child: Icon(icon, size: 28, color: tint),
          ),
          Gap.lg,
          Text(
            headline,
            style: AppTextStyles.onSurface(context, AppTextStyles.h2),
          ),
          Gap.sm,
          Text(
            explanation,
            style: AppTextStyles.onSurface(
              context,
              AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
          ),
          if (children.isNotEmpty) ...[
            Gap.lg,
            Divider(height: 1, color: AppColors.borderOf(context)),
            Gap.md,
            ...children,
          ],
        ],
      ),
    );
  }
}

/// Shown by a delivery step when there is no active job to render — the driver
/// deep-linked, or the order was cancelled underneath them.
class NoActiveDelivery extends StatelessWidget {
  const NoActiveDelivery({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DriverAppBar(title: 'Delivery', showBack: false),
      body: Padding(
        padding: EdgeInsets.all(AppSpacing.screenPaddingOf(context)),
        child: DriverEmptyState(
          icon: Icons.local_shipping_outlined,
          title: 'No delivery in progress',
          message: "You don't have a job right now. Go back to the dash and "
              "stay online — we'll send the next offer straight to you.",
          actionLabel: 'Back to dash',
          onAction: () => context.go(routeHome),
        ),
      ),
    );
  }
}

/// Money formatter shared by the delivery steps. Always an explicit symbol and
/// two decimals — never a bare number a driver has to interpret.
String formatUsdCents(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';
